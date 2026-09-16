import { Server } from 'node:http';
import { connect, Socket, AddressInfo } from 'node:net';
import { randomBytes } from 'node:crypto';
import {
  createTestApplication,
  TestApplicationContext,
} from '../support/test-app';
import { registerHuman } from '../federation/support/federation-test-support';
import { RealtimeService } from '../../src/modules/realtime/realtime.service';

describe('WS-00 through WS-05 live TCP framing', () => {
  let ctx: TestApplicationContext;
  let human: Awaited<ReturnType<typeof registerHuman>>;
  const sockets = new Set<Socket>();
  beforeAll(async () => {
    ctx = await createTestApplication();
    await ctx.app.listen(0, '127.0.0.1');
    human = await registerHuman(ctx.app, 'tcp-audit@example.test', 'TCP audit');
  });
  afterAll(async () => {
    for (const socket of sockets) socket.destroy();
    await ctx?.close();
  });
  const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
  async function raw() {
    const socket = connect(
      ((ctx.app.getHttpServer() as Server).address() as AddressInfo).port,
      '127.0.0.1',
    );
    sockets.add(socket);
    socket.setNoDelay(true);
    let buffer = Buffer.alloc(0);
    let upgraded = false;
    const frames: Array<{ opcode: number; body: Buffer }> = [];
    socket.on('data', (chunk) => {
      buffer = Buffer.concat([buffer, chunk]);
      if (!upgraded) {
        const end = buffer.indexOf('\r\n\r\n');
        if (end < 0) return;
        expect(buffer.toString('ascii', 0, end)).toContain(
          '101 Switching Protocols',
        );
        buffer = buffer.subarray(end + 4);
        upgraded = true;
      }
      while (buffer.length >= 2) {
        let size = buffer[1] & 127;
        let offset = 2;
        if (size === 126) {
          if (buffer.length < 4) return;
          size = buffer.readUInt16BE(2);
          offset = 4;
        }
        if (size === 127) {
          if (buffer.length < 10) return;
          size = Number(buffer.readBigUInt64BE(2));
          offset = 10;
        }
        if (buffer.length < offset + size) return;
        frames.push({
          opcode: buffer[0] & 15,
          body: buffer.subarray(offset, offset + size),
        });
        buffer = buffer.subarray(offset + size);
      }
    });
    await new Promise<void>((resolve) => socket.once('connect', resolve));
    socket.write(
      `GET /ws?access_token=${human.accessToken} HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: ${randomBytes(16).toString('base64')}\r\nSec-WebSocket-Version: 13\r\n\r\n`,
    );
    const wait = async (predicate: () => boolean) => {
      const deadline = Date.now() + 1500;
      while (!predicate() && Date.now() < deadline) await sleep(10);
      expect(predicate()).toBe(true);
    };
    await wait(() => upgraded);
    return { socket, frames, wait };
  }
  function frame(payload: Buffer, opcode = 9, masked = true, extended = false) {
    const mask = Buffer.from([1, 2, 3, 4]);
    const header = Buffer.alloc(extended ? 10 : 2);
    header[0] = 128 | opcode;
    header[1] = (masked ? 128 : 0) | (extended ? 127 : payload.length);
    if (extended) header.writeBigUInt64BE(BigInt(payload.length), 2);
    return Buffer.concat([
      header,
      ...(masked ? [mask] : []),
      masked
        ? Buffer.from(payload.map((byte, i) => byte ^ mask[i % 4]))
        : payload,
    ]);
  }
  it('WS-00 small masked ping works', async () => {
    const c = await raw();
    c.socket.write(frame(Buffer.from('ok')));
    await c.wait(() =>
      c.frames.some((f) => f.opcode === 10 && f.body.toString() === 'ok'),
    );
    c.socket.destroy();
  });
  it('WS-02 reassembles a byte-at-a-time masked ping', async () => {
    const c = await raw();
    for (const byte of frame(Buffer.from('split'))) {
      c.socket.write(Buffer.from([byte]));
      await sleep(5);
    }
    await c.wait(() =>
      c.frames.some((f) => f.opcode === 10 && f.body.toString() === 'split'),
    );
    c.socket.destroy();
  });
  it('WS-03 handles every frame in one TCP chunk', async () => {
    const c = await raw();
    c.socket.write(
      Buffer.concat([frame(Buffer.from('one')), frame(Buffer.from('two'))]),
    );
    await c.wait(() => c.frames.filter((f) => f.opcode === 10).length === 2);
    c.socket.destroy();
  });
  it('WS-01 encodes outbound data over 65535 bytes', async () => {
    const c = await raw();
    expect(() =>
      ctx.app.get(RealtimeService).emitToHuman(human.user.id, {
        type: 'audit.large',
        value: 'X'.repeat(70000),
      }),
    ).not.toThrow();
    await c.wait(() =>
      c.frames.some((f) => f.opcode === 1 && f.body.length > 70000),
    );
    c.socket.destroy();
  });
  it('WS-04 rejects an oversized 64-bit length frame with 1009', async () => {
    const c = await raw();
    c.socket.write(frame(Buffer.alloc(70000), 1, true, true));
    await c.wait(() =>
      c.frames.some((f) => f.opcode === 8 && f.body.readUInt16BE(0) === 1009),
    );
    c.socket.destroy();
  });
  it('WS-05 rejects unmasked client frames with 1002', async () => {
    const c = await raw();
    c.socket.write(frame(Buffer.from('unmasked'), 9, false));
    await c.wait(() =>
      c.frames.some((f) => f.opcode === 8 && f.body.readUInt16BE(0) === 1002),
    );
    c.socket.destroy();
  });
});
