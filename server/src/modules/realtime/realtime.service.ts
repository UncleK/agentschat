import {
  Injectable,
  Logger,
  OnApplicationBootstrap,
  OnModuleDestroy,
} from '@nestjs/common';
import { HttpAdapterHost } from '@nestjs/core';
import { WebSocket, WebSocketServer } from 'ws';
import type { IncomingMessage } from 'node:http';
import { Socket } from 'node:net';
import { APP_ENVIRONMENT, type AppEnvironment } from '../../config/environment';
import { AuthService } from '../auth/auth.service';
import { Inject } from '@nestjs/common';

interface HumanSocketSession {
  socket: WebSocket;
  queuedBytes: number;
  alive: boolean;
  userId: string;
  token: string;
  expiresAt: number;
  expiryTimer: NodeJS.Timeout;
  sendQueue: Promise<void>;
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
  private readonly sessionsByUserId = new Map<string, Set<WebSocket>>();
  private readonly sessionBySocket = new Map<WebSocket, HumanSocketSession>();
  private readonly websocketServer = new WebSocketServer({
    noServer: true,
    maxPayload: 65536,
    perMessageDeflate: false,
  });
  private heartbeatTimer?: NodeJS.Timeout;
  private httpServer?: UpgradeCapableServer;
  private unsubscribeInvalidation?: () => void;

  constructor(
    private readonly httpAdapterHost: HttpAdapterHost,
    private readonly authService: AuthService,
    @Inject(APP_ENVIRONMENT)
    private readonly environment: AppEnvironment,
  ) {}

  onApplicationBootstrap(): void {
    this.heartbeatTimer = setInterval(() => {
      for (const session of this.sessionBySocket.values()) {
        if (!session.alive) {
          session.socket.terminate();
          this.unregisterSocket(session.socket);
          continue;
        }
        session.alive = false;
        session.socket.ping();
      }
    }, 30_000);
    this.heartbeatTimer.unref();
    this.unsubscribeInvalidation = this.authService.onHumanTokensInvalidated(
      (userId) => {
        for (const socket of this.sessionsByUserId.get(userId) ?? []) {
          this.closeUnauthorizedSocket(socket);
        }
      },
    );
    const httpServer =
      this.httpAdapterHost.httpAdapter?.getHttpServer() as unknown;

    if (!this.isUpgradeCapableServer(httpServer)) {
      return;
    }

    this.httpServer = httpServer;
    httpServer.on('upgrade', this.handleUpgradeListener);
  }

  onModuleDestroy(): void {
    clearInterval(this.heartbeatTimer);
    this.websocketServer.close();
    this.httpServer?.off?.('upgrade', this.handleUpgradeListener);
    this.unsubscribeInvalidation?.();

    for (const session of this.sessionBySocket.values()) {
      clearTimeout(session.expiryTimer);
      session.socket.terminate();
    }

    this.sessionBySocket.clear();
    this.sessionsByUserId.clear();
  }

  emitToHuman(userId: string, payload: Record<string, unknown>): void {
    const sockets = this.sessionsByUserId.get(userId);

    if (!sockets?.size) {
      return;
    }

    const frame = JSON.stringify(payload);
    const byteSize = Buffer.byteLength(frame);

    for (const socket of sockets) {
      if (socket.readyState !== WebSocket.OPEN) {
        this.unregisterSocket(socket);
        continue;
      }

      const session = this.sessionBySocket.get(socket);
      if (!session) continue;
      if (
        byteSize > 262144 ||
        session.queuedBytes + socket.bufferedAmount + byteSize > 1048576
      ) {
        this.unregisterSocket(socket);
        socket.close(1009, 'Realtime payload or backpressure limit exceeded.');
        continue;
      }
      session.queuedBytes += byteSize;
      session.sendQueue = session.sendQueue.then(async () => {
        if (this.sessionBySocket.get(socket) !== session) return;
        try {
          await this.authService.authenticateHumanToken(session.token);
          if (this.sessionBySocket.get(socket) !== session) return;
          if (session.expiresAt <= Date.now()) {
            this.closeUnauthorizedSocket(socket);
            return;
          }
          if (socket.readyState === WebSocket.OPEN)
            socket.send(frame, (error) => {
              if (error) socket.terminate();
            });
        } catch {
          this.closeUnauthorizedSocket(socket);
        } finally {
          session.queuedBytes -= byteSize;
        }
      });
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
        socket.destroy();
        return;
      }

      const token = this.extractBearerToken(request.headers, requestUrl);
      const authenticatedHuman =
        await this.authService.authenticateHumanToken(token);
      if (
        (this.sessionsByUserId.get(authenticatedHuman.id)?.size ?? 0) >= 8 ||
        this.sessionBySocket.size >= 1024
      ) {
        socket.end(
          'HTTP/1.1 429 Too Many Requests\r\nConnection: close\r\n\r\n',
        );
        return;
      }
      socket.setNoDelay(true);
      this.websocketServer.handleUpgrade(
        request as IncomingMessage,
        socket,
        head,
        (websocket) => {
          this.registerSocket(
            authenticatedHuman.id,
            websocket,
            token,
            this.authService.readHumanTokenExpiresAt(token),
          );
          websocket.on('close', () => this.unregisterSocket(websocket));
          websocket.on('error', () => this.unregisterSocket(websocket));
          websocket.on('pong', () => {
            const session = this.sessionBySocket.get(websocket);
            if (session) session.alive = true;
          });
          this.emitToHuman(authenticatedHuman.id, {
            type: 'realtime.connected',
            path: this.environment.transport.appRealtime.path,
          });
        },
      );
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

  private registerSocket(
    userId: string,
    socket: WebSocket,
    token: string,
    expiresAt: number,
  ): void {
    const sessions = this.sessionsByUserId.get(userId) ?? new Set<WebSocket>();
    sessions.add(socket);
    this.sessionsByUserId.set(userId, sessions);
    this.sessionBySocket.set(socket, {
      socket,
      userId,
      token,
      expiresAt,
      expiryTimer: setTimeout(
        () => this.closeUnauthorizedSocket(socket),
        Math.max(0, expiresAt - Date.now()),
      ),
      sendQueue: Promise.resolve(),
      queuedBytes: 0,
      alive: true,
    });
  }

  private closeUnauthorizedSocket(socket: WebSocket): void {
    this.unregisterSocket(socket);
    if (socket.readyState === WebSocket.OPEN)
      socket.close(1008, 'Authentication expired or revoked.');
    const timer = setTimeout(() => socket.terminate(), 1000);
    timer.unref();
  }

  private unregisterSocket(socket: WebSocket): void {
    const session = this.sessionBySocket.get(socket);

    if (!session) {
      return;
    }

    clearTimeout(session.expiryTimer);
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
}
