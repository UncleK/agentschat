import { existsSync } from 'node:fs';
import { writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';
import {
  PayloadTooLargeException,
  UnprocessableEntityException,
} from '@nestjs/common';
import type { AppEnvironment } from '../../config/environment';
import { SpeechService } from './speech.service';

function buildTestEnvironment(): AppEnvironment {
  return {
    nodeEnv: 'test',
    serviceName: 'agents-chat-server',
    port: 3000,
    apiPrefix: 'api/v1',
    auth: {
      jwtSecret: 'test-secret',
      operatorToken: 'test-operator-token',
      emailVerificationCodeTtlSeconds: 600,
      passwordResetCodeTtlSeconds: 900,
      emailCodeCooldownSeconds: 60,
    },
    mail: {
      deliveryMode: 'log',
      fromAddress: 'Agents Chat <test@example.com>',
      resendApiKey: null,
    },
    database: {
      url: 'postgres://agents_chat:agents_chat@localhost:5432/agents_chat',
    },
    redis: {
      url: 'redis://localhost:6379',
    },
    presence: {
      staleAfterSeconds: 180,
      sweepIntervalSeconds: 30,
    },
    minio: {
      endpoint: 'localhost',
      port: 9000,
      useSsl: false,
      accessKey: 'minioadmin',
      secretKey: 'minioadmin',
      bucket: 'agents-chat-local',
    },
    speech: {
      agentCantSecret: 'test-agent-cant-secret',
      pythonBin: 'python',
      modelSize: 'small',
      device: 'cpu',
      computeType: 'int8',
      timeoutMs: 90_000,
      maxUploadBytes: 1024,
      maxDurationSeconds: 60,
      ffmpegBin: 'ffmpeg',
      modelDir: null,
    },
    transport: {
      appRealtime: {
        transport: 'websocket',
        path: '/ws',
      },
      federation: {
        transport: 'http',
        claimPath: '/api/v1/agents/claim',
        actionsPath: '/api/v1/actions',
        pollingPath: '/api/v1/deliveries/poll',
        acksPath: '/api/v1/acks',
      },
    },
  };
}

function createSilentWav(durationMs: number): Buffer {
  const sampleRate = 16_000;
  const channels = 1;
  const bitsPerSample = 16;
  const sampleCount = Math.floor((sampleRate * durationMs) / 1000);
  const pcmBytes = Buffer.alloc(sampleCount * 2);
  const byteRate = sampleRate * channels * bitsPerSample / 8;
  const blockAlign = channels * bitsPerSample / 8;
  const wavBytes = Buffer.alloc(44 + pcmBytes.length);

  wavBytes.write('RIFF', 0, 'ascii');
  wavBytes.writeUInt32LE(36 + pcmBytes.length, 4);
  wavBytes.write('WAVE', 8, 'ascii');
  wavBytes.write('fmt ', 12, 'ascii');
  wavBytes.writeUInt32LE(16, 16);
  wavBytes.writeUInt16LE(1, 20);
  wavBytes.writeUInt16LE(channels, 22);
  wavBytes.writeUInt32LE(sampleRate, 24);
  wavBytes.writeUInt32LE(byteRate, 28);
  wavBytes.writeUInt16LE(blockAlign, 32);
  wavBytes.writeUInt16LE(bitsPerSample, 34);
  wavBytes.write('data', 36, 'ascii');
  wavBytes.writeUInt32LE(pcmBytes.length, 40);
  pcmBytes.copy(wavBytes, 44);

  return wavBytes;
}

describe('SpeechService', () => {
  it('transcribes normalized audio and cleans up temp files', async () => {
    const service = new SpeechService(buildTestEnvironment());
    let normalizedWavPath = '';

    jest
      .spyOn(service as never, 'runCommand')
      .mockImplementation(
        async (input: {
          command: string;
          args: string[];
        }): Promise<{ stdout: string; stderr: string }> => {
          if (input.command === 'ffmpeg') {
            normalizedWavPath = input.args[input.args.length - 1];
            await writeFile(normalizedWavPath, createSilentWav(1200));
            return { stdout: '', stderr: '' };
          }

          return {
            stdout: JSON.stringify({
              text: '  Hello   Agent Cant  ',
              language: 'en',
            }),
            stderr: '',
          };
        },
      );

    const result = await service.transcribeUploadedAudio({
      bytes: Buffer.from([1, 2, 3]),
      originalFileName: 'clip.webm',
      mimeType: 'audio/webm',
    });

    expect(result).toEqual({
      transcript: 'Hello Agent Cant',
      language: 'en',
      inputDurationMs: 1200,
    });
    expect(normalizedWavPath).not.toBe('');
    expect(existsSync(dirname(normalizedWavPath))).toBe(false);
  });

  it('rejects empty transcripts and still cleans up temp files', async () => {
    const service = new SpeechService(buildTestEnvironment());
    let normalizedWavPath = '';

    jest
      .spyOn(service as never, 'runCommand')
      .mockImplementation(
        async (input: {
          command: string;
          args: string[];
        }): Promise<{ stdout: string; stderr: string }> => {
          if (input.command === 'ffmpeg') {
            normalizedWavPath = input.args[input.args.length - 1];
            await writeFile(normalizedWavPath, createSilentWav(800));
            return { stdout: '', stderr: '' };
          }

          return {
            stdout: JSON.stringify({
              text: '   ',
              language: 'zh',
            }),
            stderr: '',
          };
        },
      );

    await expect(
      service.transcribeUploadedAudio({
        bytes: Buffer.from([1, 2, 3]),
        originalFileName: 'clip.wav',
        mimeType: 'audio/wav',
      }),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);
    expect(existsSync(dirname(normalizedWavPath))).toBe(false);
  });

  it('rejects uploads above the configured byte limit', async () => {
    const service = new SpeechService(buildTestEnvironment());

    await expect(
      service.transcribeUploadedAudio({
        bytes: Buffer.alloc(1025),
        originalFileName: 'clip.wav',
        mimeType: 'audio/wav',
      }),
    ).rejects.toBeInstanceOf(PayloadTooLargeException);
  });

  it('encodes lookup Agent Cant audio through the SDK bridge', async () => {
    const service = new SpeechService(buildTestEnvironment());
    const encodeAgentCant = jest.fn().mockReturnValue({
      wavBytes: Uint8Array.from([1, 2, 3]),
      mimeType: 'audio/wav',
      durationMs: 3456,
      token: 'token-1',
      checksum: 'checksum-1',
    });

    jest
      .spyOn(service as never, 'getAgentCantModule')
      .mockResolvedValue({ encodeAgentCant });

    const result = await service.encodeLookupAgentCant({
      messageId: 'msg-1',
      text: 'Hello world',
    });

    expect(encodeAgentCant).toHaveBeenCalledWith({
      messageId: 'msg-1',
      text: 'Hello world',
      secret: 'test-agent-cant-secret',
    });
    expect(result).toEqual({
      wavBytes: Uint8Array.from([1, 2, 3]),
      mimeType: 'audio/wav',
      durationMs: 3456,
      token: 'token-1',
      checksum: 'checksum-1',
    });
  });
});
