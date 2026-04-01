import { INestApplication } from '@nestjs/common';
import request from 'supertest';

const onePixelPngBase64 =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO6p4yQAAAAASUVORK5CYII=';

export const onePixelPngBuffer = Buffer.from(onePixelPngBase64, 'base64');

export async function issueUpload(
  app: INestApplication,
  accessToken: string,
  input: {
    fileName: string;
    mimeType?: string;
    metadata?: Record<string, unknown>;
  },
) {
  const response = await request(app.getHttpServer())
    .post('/api/v1/assets/uploads')
    .set('Authorization', `Bearer ${accessToken}`)
    .send({
      fileName: input.fileName,
      mimeType: input.mimeType ?? 'image/png',
      metadata: input.metadata,
    })
    .expect(201);

  return response.body as {
    asset: {
      id: string;
      originalFileName: string;
      mimeType: string;
    };
    upload: {
      method: 'PUT';
      url: string;
      headers: {
        'Content-Type': string;
      };
    };
  };
}

export async function putIssuedUpload(upload: {
  url: string;
  headers: {
    'Content-Type': string;
  };
}): Promise<void> {
  const response = await fetch(upload.url, {
    method: 'PUT',
    headers: {
      'Content-Type': upload.headers['Content-Type'],
    },
    body: onePixelPngBuffer,
  });

  if (!response.ok) {
    throw new Error(`Failed to PUT test image to storage: ${response.status}`);
  }
}

export async function completeUpload(
  app: INestApplication,
  accessToken: string,
  assetId: string,
) {
  const response = await request(app.getHttpServer())
    .post(`/api/v1/assets/${assetId}/complete`)
    .set('Authorization', `Bearer ${accessToken}`)
    .expect(201);

  return response.body as {
    id: string;
    uploadStatus: string;
    moderationStatus: string;
    moderationReason: string | null;
    byteSize: number | null;
    mimeType: string;
  };
}

export async function createCompletedImageAsset(
  app: INestApplication,
  accessToken: string,
  fileName = 'approved-image.png',
) {
  const upload = await issueUpload(app, accessToken, {
    fileName,
  });

  await putIssuedUpload(upload.upload);

  const asset = await completeUpload(app, accessToken, upload.asset.id);

  return {
    upload,
    asset,
  };
}
