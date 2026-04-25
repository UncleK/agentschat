import { execFile } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { extname, join, resolve } from 'node:path';
import { promisify } from 'node:util';
import {
  BadRequestException,
  Inject,
  Injectable,
  PayloadTooLargeException,
  ServiceUnavailableException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { APP_ENVIRONMENT, type AppEnvironment } from '../../config/environment';

const execFileAsync = promisify(execFile);

type AgentCantModule = typeof import('agentscant');

interface SttScriptResult {
  text?: string;
  language?: string | null;
}

export interface SpeechTranscriptionResult {
  transcript: string;
  language: 'zh' | 'en' | null;
  inputDurationMs: number;
}

@Injectable()
export class SpeechService {
  private agentCantModulePromise: Promise<AgentCantModule> | null = null;

  constructor(
    @Inject(APP_ENVIRONMENT)
    private readonly environment: AppEnvironment,
  ) {}

  async transcribeUploadedAudio(input: {
    bytes: Buffer;
    originalFileName?: string | null;
    mimeType?: string | null;
  }): Promise<SpeechTranscriptionResult> {
    if (input.bytes.byteLength === 0) {
      throw new BadRequestException('file is required.');
    }

    if (input.bytes.byteLength > this.environment.speech.maxUploadBytes) {
      throw new PayloadTooLargeException(
        `Voice uploads must be ${this.environment.speech.maxUploadBytes} bytes or smaller.`,
      );
    }

    const tempDir = await mkdtemp(join(tmpdir(), 'agents-chat-voice-'));
    const sourcePath = join(
      tempDir,
      `source${this.resolveTempExtension(input.originalFileName, input.mimeType)}`,
    );
    const wavPath = join(tempDir, 'normalized.wav');

    try {
      await writeFile(sourcePath, input.bytes);
      await this.runCommand({
        command: this.environment.speech.ffmpegBin,
        args: [
          '-hide_banner',
          '-loglevel',
          'error',
          '-y',
          '-i',
          sourcePath,
          '-ac',
          '1',
          '-ar',
          '16000',
          '-f',
          'wav',
          wavPath,
        ],
        timeoutMs: this.environment.speech.timeoutMs,
        failureMessage: 'Voice transcription failed during audio normalization.',
      });

      const wavBytes = await readFile(wavPath);
      const inputDurationMs = this.readWavDurationMs(wavBytes);

      if (
        inputDurationMs >
        this.environment.speech.maxDurationSeconds * 1_000
      ) {
        throw new UnprocessableEntityException(
          `Voice messages must be ${this.environment.speech.maxDurationSeconds} seconds or shorter.`,
        );
      }

      const sttOutput = await this.runCommand({
        command: this.environment.speech.pythonBin,
        args: [
          this.transcribeScriptPath,
          '--audio',
          wavPath,
          '--model-size',
          this.environment.speech.modelSize,
          '--device',
          this.environment.speech.device,
          '--compute-type',
          this.environment.speech.computeType,
          ...(this.environment.speech.modelDir
            ? ['--model-dir', this.environment.speech.modelDir]
            : []),
        ],
        timeoutMs: this.environment.speech.timeoutMs,
        failureMessage: 'Voice transcription failed.',
        timeoutMessage: 'Voice transcription timed out.',
      });

      const result = this.parseSttScriptOutput(sttOutput.stdout);
      const transcript = this.normalizeTranscript(result.text);

      if (!transcript) {
        throw new UnprocessableEntityException(
          'Voice transcription produced an empty transcript.',
        );
      }

      return {
        transcript,
        language: this.normalizeTranscriptLanguage(result.language),
        inputDurationMs,
      };
    } finally {
      await rm(tempDir, { recursive: true, force: true });
    }
  }

  async encodeLookupAgentCant(input: {
    messageId: string;
    text: string;
  }): Promise<{
    wavBytes: Uint8Array;
    mimeType: 'audio/wav';
    durationMs: number;
    token: string;
    checksum: string;
  }> {
    const { encodeAgentCant } = await this.getAgentCantModule();
    const encoded = encodeAgentCant({
      messageId: input.messageId,
      text: input.text,
      secret: this.environment.speech.agentCantSecret,
    });

    return {
      wavBytes: encoded.wavBytes,
      mimeType: encoded.mimeType,
      durationMs: encoded.durationMs,
      token: encoded.token,
      checksum: encoded.checksum,
    };
  }

  private async getAgentCantModule(): Promise<AgentCantModule> {
    if (!this.agentCantModulePromise) {
      this.agentCantModulePromise = import('agentscant');
    }

    return this.agentCantModulePromise;
  }

  private async runCommand(input: {
    command: string;
    args: string[];
    timeoutMs: number;
    failureMessage: string;
    timeoutMessage?: string;
  }): Promise<{ stdout: string; stderr: string }> {
    try {
      const result = await execFileAsync(input.command, input.args, {
        timeout: input.timeoutMs,
        windowsHide: true,
        maxBuffer: 10 * 1024 * 1024,
      });

      return {
        stdout: result.stdout,
        stderr: result.stderr,
      };
    } catch (error) {
      if (
        typeof error === 'object' &&
        error !== null &&
        'code' in error &&
        (error as { code?: string }).code === 'ENOENT'
      ) {
        throw new ServiceUnavailableException(
          `Voice transcription dependency was not found: ${input.command}`,
        );
      }

      if (this.isTimeoutError(error)) {
        throw new UnprocessableEntityException(
          input.timeoutMessage ?? 'Voice transcription timed out.',
        );
      }

      const errorWithStreams = error as {
        message?: string;
        stderr?: string;
        stdout?: string;
      };
      const detail =
        errorWithStreams.stderr?.trim() ||
        errorWithStreams.stdout?.trim() ||
        errorWithStreams.message ||
        'Unknown command failure.';

      throw new UnprocessableEntityException(
        `${input.failureMessage} ${detail}`.trim(),
      );
    }
  }

  private isTimeoutError(error: unknown): boolean {
    if (!error || typeof error !== 'object') {
      return false;
    }

    const errorWithSignal = error as {
      killed?: boolean;
      signal?: string;
      code?: string;
    };

    return (
      errorWithSignal.killed === true ||
      errorWithSignal.signal === 'SIGTERM' ||
      errorWithSignal.code === 'ETIMEDOUT'
    );
  }

  private parseSttScriptOutput(stdout: string): SttScriptResult {
    try {
      const parsed = JSON.parse(stdout) as SttScriptResult;

      if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
        throw new Error('Speech transcription output must be an object.');
      }

      return parsed;
    } catch (error) {
      throw new ServiceUnavailableException(
        `Voice transcription produced invalid JSON output: ${error instanceof Error ? error.message : 'Unknown parse failure.'}`,
      );
    }
  }

  private normalizeTranscript(value: unknown): string | null {
    if (typeof value !== 'string') {
      return null;
    }

    const normalized = value.replace(/\s+/g, ' ').trim();
    return normalized ? normalized : null;
  }

  private normalizeTranscriptLanguage(value: unknown): 'zh' | 'en' | null {
    if (typeof value !== 'string') {
      return null;
    }

    const normalized = value.trim().toLowerCase();
    if (normalized.startsWith('zh')) {
      return 'zh';
    }
    if (normalized.startsWith('en')) {
      return 'en';
    }

    return null;
  }

  private resolveTempExtension(
    originalFileName?: string | null,
    mimeType?: string | null,
  ): string {
    const fileExtension = originalFileName ? extname(originalFileName) : '';
    if (fileExtension) {
      return fileExtension.toLowerCase();
    }

    const normalizedMimeType = mimeType?.trim().toLowerCase();
    switch (normalizedMimeType) {
      case 'audio/wav':
      case 'audio/x-wav':
        return '.wav';
      case 'audio/webm':
        return '.webm';
      case 'audio/mpeg':
        return '.mp3';
      case 'audio/mp4':
      case 'audio/x-m4a':
      case 'audio/aac':
        return '.m4a';
      case 'audio/ogg':
      case 'application/ogg':
        return '.ogg';
      default:
        return '.bin';
    }
  }

  private readWavDurationMs(wavBytes: Buffer): number {
    if (
      wavBytes.byteLength < 44 ||
      wavBytes.toString('ascii', 0, 4) !== 'RIFF' ||
      wavBytes.toString('ascii', 8, 12) !== 'WAVE'
    ) {
      throw new UnprocessableEntityException(
        'Voice transcription failed because normalized audio was not a valid WAV file.',
      );
    }

    let byteRate: number | null = null;
    let dataSize: number | null = null;
    let offset = 12;

    while (offset + 8 <= wavBytes.byteLength) {
      const chunkId = wavBytes.toString('ascii', offset, offset + 4);
      const chunkSize = wavBytes.readUInt32LE(offset + 4);
      const chunkStart = offset + 8;

      if (chunkId === 'fmt ' && chunkSize >= 12) {
        byteRate = wavBytes.readUInt32LE(chunkStart + 8);
      } else if (chunkId === 'data') {
        dataSize = chunkSize;
      }

      offset = chunkStart + chunkSize + (chunkSize % 2);
    }

    if (!byteRate || dataSize == null || byteRate <= 0) {
      throw new UnprocessableEntityException(
        'Voice transcription failed because normalized audio metadata could not be read.',
      );
    }

    return Math.round((dataSize / byteRate) * 1_000);
  }

  private get transcribeScriptPath(): string {
    return resolve(__dirname, 'scripts', 'transcribe.py');
  }
}
