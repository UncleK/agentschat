import {
  Injectable,
  Logger,
  OnApplicationBootstrap,
  OnModuleDestroy,
} from '@nestjs/common';
import { HttpAdapterHost } from '@nestjs/core';
import { createHash } from 'node:crypto';
import { Socket } from 'node:net';
import { APP_ENVIRONMENT, type AppEnvironment } from '../../config/environment';
import { AuthService } from '../auth/auth.service';
import { Inject } from '@nestjs/common';

interface HumanSocketSession {
  socket: Socket;
  userId: string;
}

interface UpgradeRequest {
  headers: Record<string, string | string[] | undefined>;
  url?: string;
}

type UpgradeListener = (
  request: UpgradeRequest,
  socket: Socket,
  head: Buffer,
) => void;

interface UpgradeCapableServer {
  on: (event: 'upgrade', listener: UpgradeListener) => void;
  off?: (event: 'upgrade', listener: UpgradeListener) => void;
}

@Injectable()
export class RealtimeService
  implements OnApplicationBootstrap, OnModuleDestroy
{
  private readonly logger = new Logger(RealtimeService.name);
  private readonly sessionsByUserId = new Map<string, Set<Socket>>();
  private readonly sessionBySocket = new Map<Socket, HumanSocketSession>();
  private httpServer?: UpgradeCapableServer;

  constructor(
    private readonly httpAdapterHost: HttpAdapterHost,
    private readonly authService: AuthService,
    @Inject(APP_ENVIRONMENT)
    private readonly environment: AppEnvironment,
  ) {}

  onApplicationBootstrap(): void {
    const httpServer =
      this.httpAdapterHost.httpAdapter?.getHttpServer() as unknown;

    if (!this.isUpgradeCapableServer(httpServer)) {
      return;
    }

    this.httpServer = httpServer;
    httpServer.on('upgrade', this.handleUpgradeListener);
  }

  onModuleDestroy(): void {
    this.httpServer?.off?.('upgrade', this.handleUpgradeListener);

    for (const session of this.sessionBySocket.values()) {
      session.socket.destroy();
    }

    this.sessionBySocket.clear();
    this.sessionsByUserId.clear();
  }

  emitToHuman(userId: string, payload: Record<string, unknown>): void {
    const sockets = this.sessionsByUserId.get(userId);

    if (!sockets?.size) {
      return;
    }

    const frame = this.encodeFrame(JSON.stringify(payload), 0x1);

    for (const socket of sockets) {
      if (socket.destroyed) {
        this.unregisterSocket(socket);
        continue;
      }

      socket.write(frame);
    }
  }

  private readonly handleUpgradeListener: UpgradeListener = (
    request,
    socket,
    head,
  ) => {
    void this.handleUpgrade(request, socket, head);
  };

  private async handleUpgrade(
    request: UpgradeRequest,
    socket: Socket,
    head: Buffer,
  ): Promise<void> {
    try {
      const requestUrl = new URL(
        request.url ?? '/',
        `http://localhost:${this.environment.port}`,
      );

      if (requestUrl.pathname !== this.environment.transport.appRealtime.path) {
        return;
      }

      const token = this.extractBearerToken(request.headers, requestUrl);
      const authenticatedHuman =
        await this.authService.authenticateHumanToken(token);
      const websocketKey = this.readHeader(
        request.headers,
        'sec-websocket-key',
      );

      if (!websocketKey) {
        throw new Error('Missing Sec-WebSocket-Key header.');
      }

      const acceptValue = createHash('sha1')
        .update(`${websocketKey}258EAFA5-E914-47DA-95CA-C5AB0DC85B11`)
        .digest('base64');

      socket.write(
        [
          'HTTP/1.1 101 Switching Protocols',
          'Upgrade: websocket',
          'Connection: Upgrade',
          `Sec-WebSocket-Accept: ${acceptValue}`,
          '\r\n',
        ].join('\r\n'),
      );

      socket.setNoDelay(true);
      socket.on('data', (chunk) => this.handleSocketData(socket, chunk));
      socket.on('close', () => this.unregisterSocket(socket));
      socket.on('error', () => this.unregisterSocket(socket));

      this.registerSocket(authenticatedHuman.id, socket);

      if (head.length > 0) {
        this.handleSocketData(socket, head);
      }

      this.emitToHuman(authenticatedHuman.id, {
        type: 'realtime.connected',
        path: this.environment.transport.appRealtime.path,
      });
    } catch (error) {
      this.logger.warn(
        `Realtime upgrade rejected: ${error instanceof Error ? error.message : 'unknown error'}`,
      );
      socket.write('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n');
      socket.destroy();
    }
  }

  private isUpgradeCapableServer(
    value: unknown,
  ): value is UpgradeCapableServer {
    if (typeof value !== 'object' || value === null) {
      return false;
    }

    const candidate = value as {
      on?: unknown;
      off?: unknown;
    };

    return (
      typeof candidate.on === 'function' &&
      (candidate.off === undefined || typeof candidate.off === 'function')
    );
  }

  private handleSocketData(socket: Socket, chunk: Buffer): void {
    const frame = this.decodeFrame(chunk);

    if (!frame) {
      return;
    }

    if (frame.opcode === 0x8) {
      socket.write(this.encodeFrame(Buffer.alloc(0), 0x8));
      socket.end();
      this.unregisterSocket(socket);
      return;
    }

    if (frame.opcode === 0x9) {
      socket.write(this.encodeFrame(frame.payload, 0xa));
    }
  }

  private registerSocket(userId: string, socket: Socket): void {
    const sessions = this.sessionsByUserId.get(userId) ?? new Set<Socket>();
    sessions.add(socket);
    this.sessionsByUserId.set(userId, sessions);
    this.sessionBySocket.set(socket, {
      socket,
      userId,
    });
  }

  private unregisterSocket(socket: Socket): void {
    const session = this.sessionBySocket.get(socket);

    if (!session) {
      return;
    }

    const sessions = this.sessionsByUserId.get(session.userId);
    sessions?.delete(socket);

    if (sessions && sessions.size === 0) {
      this.sessionsByUserId.delete(session.userId);
    }

    this.sessionBySocket.delete(socket);
  }

  private extractBearerToken(
    headers: Record<string, string | string[] | undefined>,
    requestUrl: URL,
  ): string {
    const authorizationHeader = this.readHeader(headers, 'authorization');

    if (authorizationHeader?.startsWith('Bearer ')) {
      const token = authorizationHeader.slice('Bearer '.length).trim();

      if (token) {
        return token;
      }
    }

    const accessToken = requestUrl.searchParams.get('access_token')?.trim();

    if (!accessToken) {
      throw new Error('Missing human access token for websocket connection.');
    }

    return accessToken;
  }

  private readHeader(
    headers: Record<string, string | string[] | undefined>,
    key: string,
  ): string | undefined {
    const value = headers[key];

    if (Array.isArray(value)) {
      return value[0];
    }

    return value;
  }

  private encodeFrame(payload: string | Buffer, opcode: number): Buffer {
    const payloadBuffer = Buffer.isBuffer(payload)
      ? payload
      : Buffer.from(payload, 'utf8');
    let header: Buffer;

    if (payloadBuffer.length < 126) {
      header = Buffer.from([0x80 | opcode, payloadBuffer.length]);
    } else {
      header = Buffer.alloc(4);
      header[0] = 0x80 | opcode;
      header[1] = 126;
      header.writeUInt16BE(payloadBuffer.length, 2);
    }

    return Buffer.concat([header, payloadBuffer]);
  }

  private decodeFrame(chunk: Buffer): {
    opcode: number;
    payload: Buffer;
  } | null {
    if (chunk.length < 2) {
      return null;
    }

    const opcode = chunk[0] & 0x0f;
    const masked = (chunk[1] & 0x80) === 0x80;
    let payloadLength = chunk[1] & 0x7f;
    let offset = 2;

    if (payloadLength === 126) {
      if (chunk.length < 4) {
        return null;
      }

      payloadLength = chunk.readUInt16BE(2);
      offset = 4;
    }

    let payload = chunk.subarray(
      offset + (masked ? 4 : 0),
      offset + (masked ? 4 : 0) + payloadLength,
    );

    if (masked) {
      const mask = chunk.subarray(offset, offset + 4);
      const unmasked = Buffer.alloc(payload.length);

      for (let index = 0; index < payload.length; index += 1) {
        unmasked[index] = payload[index] ^ mask[index % 4];
      }

      payload = unmasked;
    }

    return {
      opcode,
      payload,
    };
  }
}
