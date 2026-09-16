import { EventEmitter } from 'node:events';
import { lookup } from 'node:dns/promises';
import { request, RequestOptions } from 'node:https';
import { ClientRequest, IncomingMessage } from 'node:http';
import { isPublicAddress, postWebhook } from './webhook-http';

jest.mock('node:dns/promises', () => ({ lookup: jest.fn() }));
jest.mock('node:https', () => ({ request: jest.fn() }));

describe('SS-01/SS-02/SS-03 pinned HTTPS transport (synthetic DNS/socket)', () => {
  beforeEach(() => jest.resetAllMocks());
  it.each([
    '127.0.0.1',
    '10.0.0.1',
    '172.16.0.1',
    '192.168.0.1',
    '169.254.1.1',
    '100.64.0.1',
    '0.0.0.0',
    '192.0.2.1',
    '224.0.0.1',
    '::1',
    '::ffff:127.0.0.1',
    'fc00::1',
    'fe80::1',
    '2001:db8::1',
    '64:ff9b::7f00:1',
  ])('blocks %s', (ip) => expect(isPublicAddress(ip)).toBe(false));
  it('rejects a DNS answer containing a private address before connecting', async () => {
    jest.mocked(lookup).mockResolvedValueOnce([
      { address: '8.8.8.8', family: 4 },
      { address: '127.0.0.1', family: 4 },
    ] as never);
    await expect(
      postWebhook(
        'https://synthetic.example/webhook',
        '{}',
        {},
        AbortSignal.timeout(1000),
      ),
    ).rejects.toThrow();
    expect(request).not.toHaveBeenCalled();
  });
  it.each([200, 302])(
    'pins the verified answer and does not follow HTTP %i',
    async (status) => {
      jest
        .mocked(lookup)
        .mockResolvedValueOnce([{ address: '8.8.8.8', family: 4 }] as never);
      let options: RequestOptions | undefined;
      let ended: string | undefined;
      jest
        .mocked(request)
        .mockImplementation(
          (
            url: string | URL,
            opts: RequestOptions,
            response?: (message: IncomingMessage) => void,
          ) => {
            expect(new URL(url).hostname).toBe('synthetic.example');
            options = opts;
            const req = new EventEmitter() as ClientRequest;
            req.end = (body: string) => {
              ended = body;
              response?.({
                statusCode: status,
                headers: { location: 'https://127.0.0.1' },
                destroy: jest.fn(),
              } as unknown as IncomingMessage);
              return req;
            };
            req.destroy = jest.fn();
            process.nextTick(() => {
              const socket = Object.assign(new EventEmitter(), {
                remoteAddress: '8.8.8.8',
              });
              req.emit('socket', socket);
              socket.emit('secureConnect');
            });
            return req;
          },
        );
      const result = await postWebhook(
        'https://synthetic.example/webhook',
        'synthetic-payload',
        {},
        AbortSignal.timeout(1000),
      );
      expect(result).toEqual({ ok: status === 200, status });
      expect(ended).toBe('synthetic-payload');
      expect(options?.agent).toBe(false);
      expect(options?.family).toBe(4);
      const callback = jest.fn();
      options?.lookup?.('synthetic.example', {}, callback);
      expect(callback).toHaveBeenCalledWith(null, '8.8.8.8', 4);
      expect(lookup).toHaveBeenCalledTimes(1);
      expect(request).toHaveBeenCalledTimes(1);
    },
  );
  it('does not send signed payload if the actual peer differs from the DNS answer', async () => {
    jest
      .mocked(lookup)
      .mockResolvedValueOnce([{ address: '8.8.8.8', family: 4 }] as never);
    const end = jest.fn();
    jest.mocked(request).mockImplementation(() => {
      const req = new EventEmitter() as ClientRequest;
      req.end = end;
      req.destroy = (error?: Error) => {
        req.emit('error', error);
        return req;
      };
      process.nextTick(() => {
        const socket = Object.assign(new EventEmitter(), {
          remoteAddress: '127.0.0.1',
        });
        req.emit('socket', socket);
        socket.emit('secureConnect');
      });
      return req;
    });
    await expect(
      postWebhook(
        'https://synthetic.example/',
        'canary',
        {},
        AbortSignal.timeout(1000),
      ),
    ).rejects.toThrow('peer differs');
    expect(end).not.toHaveBeenCalled();
  });
});
