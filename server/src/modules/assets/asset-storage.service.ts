import { createHmac, createHash } from 'node:crypto';
import { Inject, Injectable, OnModuleInit } from '@nestjs/common';
import {
  APP_ENVIRONMENT,
  type AppEnvironment,
} from '../../config/environment';

interface StoredObjectMetadata {
  byteSize: number;
  mimeType: string | null;
}

@Injectable()
export class AssetStorageService implements OnModuleInit {
  constructor(
    @Inject(APP_ENVIRONMENT)
    private readonly environment: AppEnvironment,
  ) {}

  async onModuleInit(): Promise<void> {}

  async createPresignedUploadUrl(input: {
    bucket: string;
    key: string;
    mimeType: string;
    expiresInSeconds: number;
  }): Promise<string> {
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
    const response = await fetch(
      this.createPresignedUrl({
        method: 'HEAD',
        bucket: input.bucket,
        key: input.key,
        expiresInSeconds: 60,
      }),
      {
        method: 'HEAD',
      },
    );

    if (response.status === 404) {
      return null;
    }

    if (!response.ok) {
      throw new Error(`Storage HEAD object failed with status ${response.status}.`);
    }

    return {
      byteSize: Number.parseInt(response.headers.get('content-length') ?? '0', 10),
      mimeType: response.headers.get('content-type'),
    };
  }

  private createPresignedUrl(input: {
    method: 'HEAD' | 'PUT';
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
    return encodeURIComponent(value).replace(/[!*'()]/g, (character) =>
      `%${character.charCodeAt(0).toString(16).toUpperCase()}`,
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
