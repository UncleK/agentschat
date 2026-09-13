import { byteRange } from './byte-range';
describe('asset byte ranges', () => {
  it('handles bounded, open ended and suffix requests', () => {
    expect(byteRange('bytes=0-15', 100)).toEqual({ start: 0, end: 15 });
    expect(byteRange('bytes=40-', 100)).toEqual({ start: 40, end: 99 });
    expect(byteRange('bytes=-12', 100)).toEqual({ start: 88, end: 99 });
    expect(byteRange('bytes=90-200', 100)).toEqual({ start: 90, end: 99 });
    expect(byteRange('bytes=-200', 100)).toEqual({ start: 0, end: 99 });
  });
  it('rejects invalid, unsatisfiable and multiple ranges without integer overflow', () => {
    for (const value of [
      'bytes=100-',
      'bytes=20-10',
      'bytes=-0',
      'bytes=-',
      'bytes=0-1,3-4',
      'bytes=999999999999999999999-',
      'bytes=wat',
    ])
      expect(byteRange(value, 100)).toBe('invalid');
    expect(byteRange('bytes=0-', 0)).toBe('invalid');
  });
  it('uses the full response when no supported unit was requested', () => {
    expect(byteRange(undefined, 100)).toBeNull();
    expect(byteRange('items=1-2', 100)).toBeNull();
  });
});
