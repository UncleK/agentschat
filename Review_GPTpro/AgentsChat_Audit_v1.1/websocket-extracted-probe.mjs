/**
 * OFFLINE ONLY: extracted-helper regression probe, NOT the project's test suite.
 * Source: UncleK/agentschat @ 1fe8354186009259c11df3a4cbb0adbd80325818
 * server/src/modules/realtime/realtime.service.ts: encodeFrame/decodeFrame.
 * TypeScript annotations and private/this syntax removed, logic preserved.
 * No network, no package installation, no writes to the repository.
 * Run: node websocket-extracted-probe.mjs
 * Exit 0 means all observations matched the audit baseline, NOT that code is safe.
 */
import assert from 'node:assert/strict';

function encodeFrame(payload, opcode) {
  const payloadBuffer = Buffer.isBuffer(payload) ? payload : Buffer.from(payload, 'utf8');
  let header;
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
function decodeFrame(chunk) {
  if (chunk.length < 2) return null;
  const opcode = chunk[0] & 0x0f;
  const masked = (chunk[1] & 0x80) === 0x80;
  let payloadLength = chunk[1] & 0x7f;
  let offset = 2;
  if (payloadLength === 126) {
    if (chunk.length < 4) return null;
    payloadLength = chunk.readUInt16BE(2);
    offset = 4;
  }
  let payload = chunk.subarray(offset + (masked ? 4 : 0), offset + (masked ? 4 : 0) + payloadLength);
  if (masked) {
    const mask = chunk.subarray(offset, offset + 4);
    const unmasked = Buffer.alloc(payload.length);
    for (let index = 0; index < payload.length; index += 1) {
      unmasked[index] = payload[index] ^ mask[index % 4];
    }
    payload = unmasked;
  }
  return { opcode, payload };
}
// Test fixture, not copied from the repository: build a valid masked client frame.
function clientFrame(text, opcode = 9) {
  const payload = Buffer.from(text);
  let header;
  if (payload.length < 126) header = Buffer.from([0x80 | opcode, 0x80 | payload.length]);
  else if (payload.length <= 65535) {
    header = Buffer.alloc(4);
    header[0] = 0x80 | opcode; header[1] = 0x80 | 126;
    header.writeUInt16BE(payload.length, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x80 | opcode; header[1] = 0x80 | 127;
    header.writeBigUInt64BE(BigInt(payload.length), 2);
  }
  const mask = Buffer.from([1, 2, 3, 4]);
  const masked = Buffer.from(payload.map((b, i) => b ^ mask[i % 4]));
  return Buffer.concat([header, mask, masked]);
}
// Mirrors the source's once-per-'data'-chunk handling: no buffered decoder/loop.
function pongsForChunks(chunks) {
  const pongs = [];
  for (const chunk of chunks) {
    const frame = decodeFrame(chunk);
    if (frame?.opcode === 9) pongs.push(frame.payload.toString());
  }
  return pongs;
}
const cases = [];
const control = pongsForChunks([clientFrame('abc')]);
assert.deepEqual(control, ['abc']);
cases.push({ id: 'WS-00', kind: 'control', observed: control, expected: ['abc'], defectObserved: false });

let encodingError;
try { encodeFrame(Buffer.alloc(65536), 1); } catch (error) { encodingError = { name: error.name, code: error.code }; }
assert.equal(encodingError?.code, 'ERR_OUT_OF_RANGE');
cases.push({ id: 'WS-01', description: 'Outbound payload 65536 bytes', expected: 'Supported extended frame or intentional bounded rejection, not incidental UInt16 exception', observed: encodingError, defectObserved: true });

const ping = clientFrame('abc');
const splitPongs = pongsForChunks([ping.subarray(0, 7), ping.subarray(7)]);
assert.deepEqual(splitPongs, ['a']);
cases.push({ id: 'WS-02', description: 'Valid ping split across two TCP chunks', expected: ['abc'], observed: splitPongs, defectObserved: true });

const coalesced = pongsForChunks([Buffer.concat([clientFrame('first'), clientFrame('second')])]);
assert.deepEqual(coalesced, ['first']);
cases.push({ id: 'WS-03', description: 'Two valid pings in one TCP chunk', expected: ['first', 'second'], observed: coalesced, defectObserved: true });

const largeDecoded = decodeFrame(clientFrame('x'.repeat(65536), 1));
assert.equal(largeDecoded.payload.length, 127);
cases.push({ id: 'WS-04', description: 'Valid masked 64-bit-length client frame', expectedPayloadBytes: 65536, observedPayloadBytes: largeDecoded.payload.length, defectObserved: true });

const unmasked = decodeFrame(Buffer.from([0x89, 0x01, 0x78]));
assert.equal(unmasked.payload.toString(), 'x');
cases.push({ id: 'WS-05', description: 'Unmasked client ping is accepted', expected: 'Protocol rejection/connection close', observed: { opcode: unmasked.opcode, payload: unmasked.payload.toString() }, defectObserved: true });

console.log(JSON.stringify({
  auditDate: '2026-09-16',
  sourceCommit: '1fe8354186009259c11df3a4cbb0adbd80325818',
  sourceFile: 'server/src/modules/realtime/realtime.service.ts',
  runtime: process.version,
  executionScope: 'Locally transcribed helper functions only; not original module or E2E tests; no network requests',
  baselineObservationsMatched: true,
  controlCases: 1,
  defectCases: cases.filter((entry) => entry.defectObserved).length,
  cases
}, null, 2));
