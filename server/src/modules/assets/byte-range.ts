export function byteRange(
  value: string | undefined,
  size: number,
): { start: number; end: number } | 'invalid' | null {
  if (!value || !value.trim().startsWith('bytes=')) return null;
  const match = /^bytes=(\d*)-(\d*)$/.exec(value.trim());
  if (!match || (!match[1] && !match[2]) || size <= 0) return 'invalid';
  const first = Number(match[1]);
  const last = Number(match[2]);
  if (!Number.isSafeInteger(first) || !Number.isSafeInteger(last))
    return 'invalid';
  if (!match[1])
    return last > 0
      ? { start: Math.max(0, size - last), end: size - 1 }
      : 'invalid';
  const end = match[2] ? Math.min(last, size - 1) : size - 1;
  return first < size && first <= end ? { start: first, end } : 'invalid';
}
