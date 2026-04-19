import { createHmac, createHash } from 'node:crypto';
import { Inject, Injectable, OnModuleInit } from '@nestjs/common';
import { APP_ENVIRONMENT, type AppEnvironment } from '../../config/environment';

interface StoredObjectMetadata {
  byteSize: number;
  mimeType: string | null;
}

@Injectable()
export class AssetStorageService implements OnModuleInit {
  private static readonly emptyPayloadHash =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
  private readonly ensuredBuckets = new Set<string>();

  constructor(
    @Inject(APP_ENVIRONMENT)
    private readonly environment: AppEnvironment,
  ) {}

  async onModuleInit(): Promise<void> {
    await this.ensureBucketExists(this.environment.minio.bucket);
  }

  createPresignedUploadUrl(input: {
    bucket: string;
    key: string;
    mimeType: string;
    expiresInSeconds: number;
  }): string {
    return this.createPresignedUrl({
      method: 'PUT',
      bucket: input.bucket,
      key: input.key,
      expiresInSeconds: input.expiresInSeconds,
    });
  }

  async headObject(input: {
    bucket: string;
    key: string;
  }): Promise<StoredObjectMetadata | null> {
    const response = await this.fetchSignedStorageRequest({
      method: 'HEAD',
      bucket: input.bucket,
      key: input.key,
    });

    if (response.status === 404) {
      return null;
    }

    if (response.ok) {
      return this.readStoredMetadataFromHeaders(response);
    }

    if (response.status !== 403) {
      throw new Error(
        `Storage HEAD object failed with status ${response.status}.`,
      );
    }

    const fallbackResponse = await this.fetchSignedStorageRequest({
      method: 'GET',
      bucket: input.bucket,
      key: input.key,
    });

    if (fallbackResponse.status === 404) {
      return null;
    }

    if (!fallbackResponse.ok) {
      throw new Error(
        `Storage GET object fallback failed with status ${fallbackResponse.status}.`,
      );
    }

    const byteSizeHeader = fallbackResponse.headers.get('content-length');
    const byteSize =
      byteSizeHeader != null
        ? Number.parseInt(byteSizeHeader, 10)
        : (await fallbackResponse.arrayBuffer()).byteLength;

    return {
      byteSize,
      mimeType: fallbackResponse.headers.get('content-type'),
    };
  }

  async readObject(input: {
    bucket: string;
    key: string;
  }): Promise<{
    body: Buffer;
    mimeType: string | null;
    byteSize: number;
  } | null> {
    const response = await this.fetchSignedStorageRequest({
      method: 'GET',
      bucket: input.bucket,
      key: input.key,
    });

    if (response.status === 404) {
      return null;
    }

    if (!response.ok) {
      throw new Error(
        `Storage GET object failed with status ${response.status}.`,
      );
    }

    const body = Buffer.from(await response.arrayBuffer());
    return {
      body,
      mimeType: response.headers.get('content-type'),
      byteSize: body.byteLength,
    };
  }

  async ensureBucketExists(bucket: string): Promise<void> {
    const normalizedBucket = bucket.trim();

    if (!normalizedBucket || this.ensuredBuckets.has(normalizedBucket)) {
      return;
    }

    const existingBucketResponse = await this.fetchSignedStorageRequest({
      method: 'HEAD',
      bucket: normalizedBucket,
      payloadHash: AssetStorageService.emptyPayloadHash,
    });

    if (existingBucketResponse.ok || existingBucketResponse.status === 403) {
      this.ensuredBuckets.add(normalizedBucket);
      return;
    }

    if (existingBucketResponse.status !== 404) {
      throw new Error(
        `Storage bucket probe failed for ${normalizedBucket} with status ${existingBucketResponse.status}.`,
      );
    }

    const createBucketResponse = await this.fetchSignedStorageRequest({
      method: 'PUT',
      bucket: normalizedBucket,
      payloadHash: AssetStorageService.emptyPayloadHash,
    });

    if (
      createBucketResponse.ok ||
      createBucketResponse.status === 409 ||
      createBucketResponse.status === 403
    ) {
      this.ensuredBuckets.add(normalizedBucket);
      return;
    }

    const responseText = await createBucketResponse.text();
    throw new Error(
      `Storage bucket create failed for ${normalizedBucket} with status ${createBucketResponse.status}${responseText ? `: ${responseText}` : '.'}`,
    );
  }

  private createPresignedUrl(input: {
    method: 'GET' | 'HEAD' | 'PUT';
    bucket: string;
    key: string;
    expiresInSeconds: number;
  }): string {
    const timestamp = new Date();
    const query = this.buildPresignedQuery(timestamp, input.expiresInSeconds);
    const canonicalQuery = this.buildCanonicalQueryString(query);
    const canonicalUri = this.buildCanonicalUri(input.bucket, input.key);
    const canonicalRequest = this.buildCanonicalRequest({
      method: input.method,
      canonicalUri,
      canonicalQuery,
      canonicalHeaders: `host:${this.host}\n`,
      signedHeaders: 'host',
      payloadHash: 'UNSIGNED-PAYLOAD',
    });
    const signature = this.signString(
      this.buildStringToSign(timestamp, canonicalRequest),
      timestamp,
    );

    return `${this.baseUrl}${canonicalUri}?${canonicalQuery}&X-Amz-Signature=${signature}`;
  }

  private buildPresignedQuery(timestamp: Date, expiresInSeconds: number) {
    return {
      'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
      'X-Amz-Credential': `${this.environment.minio.accessKey}/${this.buildCredentialScope(timestamp)}`,
      'X-Amz-Date': this.formatAmzDate(timestamp),
      'X-Amz-Expires': String(expiresInSeconds),
      'X-Amz-SignedHeaders': 'host',
    };
  }

  private buildCanonicalRequest(input: {
    method: string;
    canonicalUri: string;
    canonicalQuery: string;
    canonicalHeaders: string;
    signedHeaders: string;
    payloadHash: string;
  }): string {
    return [
      input.method,
      input.canonicalUri,
      input.canonicalQuery,
      input.canonicalHeaders,
      input.signedHeaders,
      input.payloadHash,
    ].join('\n');
  }

  private async fetchSignedStorageRequest(input: {
    method: 'GET' | 'HEAD' | 'PUT';
    bucket: string;
    key?: string;
    payloadHash?: string;
  }): Promise<Response> {
    const timestamp = new Date();
    const canonicalUri = this.buildCanonicalUri(input.bucket, input.key);
    const amzDate = this.formatAmzDate(timestamp);
    const signedHeaders = 'host;x-amz-content-sha256;x-amz-date';
    const payloadHash =
      input.payloadHash ?? (input.method === 'PUT'
        ? AssetStorageService.emptyPayloadHash
        : 'UNSIGNED-PAYLOAD');
    const canonicalHeaders = [
      `host:${this.host}`,
      `x-amz-content-sha256:${payloadHash}`,
      `x-amz-date:${amzDate}`,
      '',
    ].join('\n');
    const canonicalRequest = this.buildCanonicalRequest({
      method: input.method,
      canonicalUri,
      canonicalQuery: '',
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    });
    const signature = this.signString(
      this.buildStringToSign(timestamp, canonicalRequest),
      timestamp,
    );

    return fetch(`${this.baseUrl}${canonicalUri}`, {
      method: input.method,
      body: input.method === 'PUT' ? '' : undefined,
      headers: {
        Authorization: this.buildAuthorizationHeader(
          signedHeaders,
          signature,
          timestamp,
        ),
        'x-amz-content-sha256': payloadHash,
        'x-amz-date': amzDate,
      },
    });
  }

  private buildAuthorizationHeader(
    signedHeaders: string,
    signature: string,
    timestamp: Date,
  ): string {
    return `AWS4-HMAC-SHA256 Credential=${this.environment.minio.accessKey}/${this.buildCredentialScope(timestamp)}, SignedHeaders=${signedHeaders}, Signature=${signature}`;
  }

  private readStoredMetadataFromHeaders(
    response: Response,
  ): StoredObjectMetadata {
    return {
      byteSize: Number.parseInt(
        response.headers.get('content-length') ?? '0',
        10,
      ),
      mimeType: response.headers.get('content-type'),
    };
  }

  private buildStringToSign(timestamp: Date, canonicalRequest: string): string {
    return [
      'AWS4-HMAC-SHA256',
      this.formatAmzDate(timestamp),
      this.buildCredentialScope(timestamp),
      this.sha256(canonicalRequest),
    ].join('\n');
  }

  private buildCredentialScope(timestamp: Date): string {
    return `${this.formatDateStamp(timestamp)}/us-east-1/s3/aws4_request`;
  }

  private buildCanonicalQueryString(query: Record<string, string>): string {
    return Object.entries(query)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, value]) => `${this.uriEncode(key)}=${this.uriEncode(value)}`)
      .join('&');
  }

  private buildCanonicalUri(bucket: string, key?: string): string {
    if (!key) {
      return `/${this.uriEncode(bucket)}`;
    }

    return `/${this.uriEncode(bucket)}/${key
      .split('/')
      .map((segment) => this.uriEncode(segment))
      .join('/')}`;
  }

  private signString(value: string, timestamp: Date): string {
    const dateKey = this.hmac(
      `AWS4${this.environment.minio.secretKey}`,
      this.formatDateStamp(timestamp),
    );
    const regionKey = this.hmac(dateKey, 'us-east-1');
    const serviceKey = this.hmac(regionKey, 's3');
    const signingKey = this.hmac(serviceKey, 'aws4_request');

    return createHmac('sha256', signingKey).update(value).digest('hex');
  }

  private hmac(key: string | Buffer, value: string): Buffer {
    return createHmac('sha256', key).update(value).digest();
  }

  private sha256(value: string): string {
    return createHash('sha256').update(value).digest('hex');
  }

  private uriEncode(value: string): string {
    return encodeURIComponent(value).replace(
      /[!*'()]/g,
      (character) => `%${character.charCodeAt(0).toString(16).toUpperCase()}`,
    );
  }

  private formatAmzDate(value: Date): string {
    return value.toISOString().replace(/[:-]|\.\d{3}/g, '');
  }

  private formatDateStamp(value: Date): string {
    return this.formatAmzDate(value).slice(0, 8);
  }

  private get baseUrl(): string {
    return `${this.environment.minio.useSsl ? 'https' : 'http'}://${this.host}`;
  }

  private get host(): string {
    return `${this.environment.minio.endpoint}:${this.environment.minio.port}`;
  }
}
