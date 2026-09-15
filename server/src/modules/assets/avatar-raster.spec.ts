import sharp from 'sharp';
import { AVATAR_MAX_BYTES, sanitizeAvatar } from './avatar-raster';

describe('AV-01/AV-03 real avatar bytes', () => {
  it.each(['png', 'jpeg', 'webp'] as const)(
    'normalizes legal %s to metadata-free PNG',
    async (format) => {
      const source = await sharp({
        create: { width: 2, height: 2, channels: 3, background: '#ffffff' },
      })
        .toFormat(format)
        .toBuffer();
      const result = await sanitizeAvatar(source);
      const metadata = await sharp(result).metadata();
      expect(metadata.format).toBe('png');
      expect(metadata.width).toBe(2);
      expect(metadata.exif).toBeUndefined();
    },
  );
  it('strips trailing polyglot content from a valid raster', async () => {
    const source = await sharp({
      create: { width: 1, height: 1, channels: 3, background: '#ffffff' },
    })
      .png()
      .toBuffer();
    const result = await sanitizeAvatar(
      Buffer.concat([source, Buffer.from('<html>CANARY_SCRIPT</html>')]),
    );
    expect(result.includes(Buffer.from('CANARY_SCRIPT'))).toBe(false);
  });
  it('rejects SVG, HTML, oversized bytes and excessive decoded pixels', async () => {
    for (const body of [
      Buffer.from('<svg><script>CANARY</script></svg>'),
      Buffer.from('<html>CANARY</html>'),
      Buffer.alloc(AVATAR_MAX_BYTES + 1),
    ]) {
      await expect(sanitizeAvatar(body)).rejects.toThrow();
    }
    const large = await sharp({
      create: { width: 5000, height: 4000, channels: 3, background: '#ffffff' },
    })
      .png()
      .toBuffer();
    await expect(sanitizeAvatar(large)).rejects.toThrow();
  });
});
