import { AddressInfo } from 'node:net';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import {
  TestApplicationContext,
  createTestApplication,
} from '../support/test-app';
import { registerHuman } from '../federation/support/federation-test-support';

interface SocketMessage {
  type: string;
  bell?: {
    hasUnread: boolean;
    unreadCount: number;
  };
  notification?: {
    kind: string;
  };
}

describe('App realtime websocket fanout (e2e)', () => {
  let app: INestApplication;
  let context: TestApplicationContext;

  beforeAll(async () => {
    context = await createTestApplication();
    app = context.app;
    await app.listen(0, '127.0.0.1');
  });

  afterAll(async () => {
    await context?.close();
  });

  it('emits notification and bell updates to human websocket clients without using federation transport', async () => {
    const sender = await registerHuman(app, 'ws-sender@example.com', 'WS Sender');
    const recipient = await registerHuman(app, 'ws-recipient@example.com', 'WS Recipient');
    const address = app.getHttpServer().address() as AddressInfo;
    const WebSocketClient = (globalThis as unknown as {
      WebSocket?: new (url: string) => {
        onopen: (() => void) | null;
        onmessage: ((event: { data: string }) => void) | null;
        onerror: ((event: unknown) => void) | null;
        close: () => void;
      };
    }).WebSocket;

    expect(WebSocketClient).toBeDefined();

    const socket = new WebSocketClient!(
      `ws://127.0.0.1:${address.port}/ws?access_token=${recipient.accessToken}`,
    );
    const receivedMessages: SocketMessage[] = [];

    await new Promise<void>((resolve, reject) => {
      socket.onopen = () => resolve();
      socket.onerror = () => reject(new Error('WebSocket connection failed.'));
      socket.onmessage = (event) => {
        receivedMessages.push(JSON.parse(event.data) as SocketMessage);
      };
    });

    await request(app.getHttpServer())
      .post('/api/v1/content/dm')
      .set('Authorization', `Bearer ${sender.accessToken}`)
      .send({
        recipientType: 'human',
        recipientUserId: recipient.user.id,
        content: 'Trigger websocket notification.',
      })
      .expect(201);

    const notificationMessage = await waitForMessage(
      receivedMessages,
      (message) => message.type === 'notification.created',
    );

    expect(notificationMessage.notification?.kind).toBe('dm.received');
    expect(notificationMessage.bell).toEqual({
      hasUnread: true,
      unreadCount: 1,
    });

    await request(app.getHttpServer())
      .post('/api/v1/notifications/read')
      .set('Authorization', `Bearer ${recipient.accessToken}`)
      .send({ markAll: true })
      .expect(201);

    const readMessage = await waitForMessage(
      receivedMessages,
      (message) => message.type === 'notifications.read',
    );

    expect(readMessage.bell).toEqual({
      hasUnread: false,
      unreadCount: 0,
    });

    socket.close();
  });

  async function waitForMessage(
    messages: SocketMessage[],
    predicate: (message: SocketMessage) => boolean,
    timeoutMs = 2_000,
  ) {
    const deadline = Date.now() + timeoutMs;

    while (Date.now() < deadline) {
      const message = messages.find(predicate);

      if (message) {
        return message;
      }

      await new Promise((resolve) => setTimeout(resolve, 25));
    }

    throw new Error('Timed out waiting for websocket message.');
  }
});
