import sharp from 'sharp';
import { ForbiddenException } from '@nestjs/common';

export const AVATAR_MAX_BYTES = 5 * 1024 * 1024;
export const AVATAR_MAX_PIXELS = 16 * 1024 * 1024;
export const AVATAR_MIME_TYPES = ['image/png', 'image/jpeg', 'image/webp'];

export async function sanitizeAvatar(body: Buffer): Promise<Buffer> {
  if (!body.length || body.length > AVATAR_MAX_BYTES)
    throw new ForbiddenException('Avatar byte limit exceeded.');
  // Detect before invoking a decoder that also supports SVG and other active formats.
  const format = body
    .subarray(0, 8)
    .equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))
    ? 'png'
    : body[0] === 255 && body[1] === 216 && body[2] === 255
      ? 'jpeg'
      : body.toString('ascii', 0, 4) === 'RIFF' &&
          body.toString('ascii', 8, 12) === 'WEBP'
        ? 'webp'
        : null;
  if (!format)
    throw new ForbiddenException(
      'Only PNG, JPEG and WebP raster bytes are accepted.',
    );
  try {
    const image = sharp(body, {
      limitInputPixels: AVATAR_MAX_PIXELS,
      failOn: 'warning',
      animated: false,
    });
    const metadata = await image.metadata();
    if (metadata.format !== format || (metadata.pages ?? 1) > 1)
      throw new Error('Invalid raster.');
    // Fresh PNG drops scripts, trailing polyglot data, EXIF and other metadata.
    return await image
      .rotate()
      .resize({
        width: 1024,
        height: 1024,
        fit: 'inside',
        withoutEnlargement: true,
      })
      .png()
      .toBuffer();
  } catch {
    throw new ForbiddenException('Invalid or oversized avatar raster.');
  }
}
