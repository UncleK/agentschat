import { config as loadDotEnv } from 'dotenv';
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';

const ENV_FILES = ['.env.local', '.env'];
const REQUIRED_ENV_VARS = [
  'DATABASE_URL',
  'REDIS_URL',
  'JWT_SECRET',
  'OPERATOR_TOKEN',
  'MINIO_ENDPOINT',
  'MINIO_ACCESS_KEY',
  'MINIO_SECRET_KEY',
] as const;

for (const envFile of ENV_FILES) {
  const envPath = resolve(process.cwd(), envFile);

  if (existsSync(envPath)) {
    loadDotEnv({ path: envPath, override: false });
  }
}

export const APP_ENVIRONMENT = Symbol('APP_ENVIRONMENT');
export type MailDeliveryMode = 'disabled' | 'log' | 'resend';

export interface AppEnvironment {
  readonly nodeEnv: string;
  readonly serviceName: string;
  readonly port: number;
  readonly apiPrefix: string;
  readonly auth: {
    readonly jwtSecret: string;
    readonly operatorToken: string;
    readonly emailVerificationCodeTtlSeconds: number;
    readonly passwordResetCodeTtlSeconds: number;
    readonly emailCodeCooldownSeconds: number;
  };
  readonly mail: {
    readonly deliveryMode: MailDeliveryMode;
    readonly fromAddress: string;
    readonly resendApiKey: string | null;
  };
  readonly database: {
    readonly url: string;
  };
  readonly redis: {
    readonly url: string;
  };
  readonly presence: {
    readonly staleAfterSeconds: number;
    readonly sweepIntervalSeconds: number;
  };
  readonly minio: {
    readonly endpoint: string;
    readonly port: number;
    readonly useSsl: boolean;
    readonly accessKey: string;
    readonly secretKey: string;
    readonly bucket: string;
  };
  readonly speech: {
    readonly agentCantSecret: string;
    readonly pythonBin: string;
    readonly modelSize: string;
    readonly device: string;
    readonly computeType: string;
    readonly timeoutMs: number;
    readonly maxUploadBytes: number;
    readonly maxDurationSeconds: number;
    readonly ffmpegBin: string;
    readonly modelDir: string | null;
  };
  readonly transport: {
    readonly appRealtime: {
      readonly transport: 'websocket';
      readonly path: string;
    };
    readonly federation: {
      readonly transport: 'http';
      readonly claimPath: string;
      readonly actionsPath: string;
      readonly pollingPath: string;
      readonly acksPath: string;
    };
  };
}

export function loadEnvironment(
  env: NodeJS.ProcessEnv = process.env,
): AppEnvironment {
  const missing = REQUIRED_ENV_VARS.filter((key) => !env[key]?.trim());

  if (missing.length > 0) {
    throw new Error(
      `Missing required environment variables: ${missing.join(', ')}`,
    );
  }

  const nodeEnv = env.NODE_ENV ?? 'development';
  const apiPrefix = normalizeApiPrefix(env.API_PREFIX ?? 'api/v1');
  const defaultMailDeliveryMode: MailDeliveryMode =
    nodeEnv === 'production' ? 'disabled' : 'log';

  return {
    nodeEnv,
    serviceName: 'agents-chat-server',
    port: parseInteger(env.PORT, 'PORT', 3000),
    apiPrefix,
    auth: {
      jwtSecret: env.JWT_SECRET!,
      operatorToken: env.OPERATOR_TOKEN!,
      emailVerificationCodeTtlSeconds: parseInteger(
        env.AUTH_EMAIL_VERIFICATION_CODE_TTL_SECONDS,
        'AUTH_EMAIL_VERIFICATION_CODE_TTL_SECONDS',
        600,
      ),
      passwordResetCodeTtlSeconds: parseInteger(
        env.AUTH_PASSWORD_RESET_CODE_TTL_SECONDS,
        'AUTH_PASSWORD_RESET_CODE_TTL_SECONDS',
        900,
      ),
      emailCodeCooldownSeconds: parseInteger(
        env.AUTH_EMAIL_CODE_COOLDOWN_SECONDS,
        'AUTH_EMAIL_CODE_COOLDOWN_SECONDS',
        60,
      ),
    },
    mail: {
      deliveryMode: parseMailDeliveryMode(
        env.MAIL_DELIVERY_MODE,
        defaultMailDeliveryMode,
      ),
      fromAddress:
        normalizeOptionalString(env.MAIL_FROM_ADDRESS) ??
        'Agents Chat <no-reply@example.com>',
      resendApiKey: normalizeOptionalString(env.MAIL_RESEND_API_KEY),
    },
    database: {
      url: env.DATABASE_URL!,
    },
    redis: {
      url: env.REDIS_URL!,
    },
    presence: {
      staleAfterSeconds: parseInteger(
        env.AGENT_PRESENCE_STALE_AFTER_SECONDS,
        'AGENT_PRESENCE_STALE_AFTER_SECONDS',
        180,
      ),
      sweepIntervalSeconds: parseInteger(
        env.AGENT_PRESENCE_SWEEP_INTERVAL_SECONDS,
        'AGENT_PRESENCE_SWEEP_INTERVAL_SECONDS',
        30,
      ),
    },
    minio: {
      endpoint: env.MINIO_ENDPOINT!,
      port: parseInteger(env.MINIO_PORT, 'MINIO_PORT', 9000),
      useSsl: parseBoolean(env.MINIO_USE_SSL, false),
      accessKey: env.MINIO_ACCESS_KEY!,
      secretKey: env.MINIO_SECRET_KEY!,
      bucket: env.MINIO_BUCKET ?? 'agents-chat-local',
    },
    speech: {
      agentCantSecret:
        normalizeOptionalString(env.AGENT_CANT_SECRET) ??
        fallbackAgentCantSecret(nodeEnv),
      pythonBin:
        normalizeOptionalString(env.STT_PYTHON_BIN) ??
        (process.platform === 'win32' ? 'python' : 'python3'),
      modelSize: normalizeOptionalString(env.STT_MODEL_SIZE) ?? 'small',
      device: normalizeOptionalString(env.STT_DEVICE) ?? 'cpu',
      computeType: normalizeOptionalString(env.STT_COMPUTE_TYPE) ?? 'int8',
      timeoutMs: parseInteger(env.STT_TIMEOUT_MS, 'STT_TIMEOUT_MS', 90_000),
      maxUploadBytes: parseInteger(
        env.STT_MAX_UPLOAD_BYTES,
        'STT_MAX_UPLOAD_BYTES',
        10 * 1024 * 1024,
      ),
      maxDurationSeconds: parseInteger(
        env.STT_MAX_DURATION_SECONDS,
        'STT_MAX_DURATION_SECONDS',
        60,
      ),
      ffmpegBin: normalizeOptionalString(env.FFMPEG_BIN) ?? 'ffmpeg',
      modelDir: normalizeOptionalString(env.STT_MODEL_DIR),
    },
    transport: {
      appRealtime: {
        transport: 'websocket',
        path: '/ws',
      },
      federation: {
        transport: 'http',
        claimPath: `/${apiPrefix}/agents/claim`,
        actionsPath: `/${apiPrefix}/actions`,
        pollingPath: `/${apiPrefix}/deliveries/poll`,
        acksPath: `/${apiPrefix}/acks`,
      },
    },
  };
}

function normalizeApiPrefix(value: string): string {
  return value.replace(/^\/+/, '').replace(/\/+$/, '');
}

function parseInteger(
  value: string | undefined,
  key: string,
  fallback: number,
): number {
  if (value === undefined || value.trim() === '') {
    return fallback;
  }

  const parsed = Number.parseInt(value, 10);

  if (Number.isNaN(parsed)) {
    throw new Error(`Environment variable ${key} must be an integer.`);
  }

  return parsed;
}

function parseBoolean(value: string | undefined, fallback: boolean): boolean {
  if (value === undefined || value.trim() === '') {
    return fallback;
  }

  return value.toLowerCase() === 'true';
}

function parseMailDeliveryMode(
  value: string | undefined,
  fallback: MailDeliveryMode,
): MailDeliveryMode {
  const normalized = value?.trim().toLowerCase();

  if (!normalized) {
    return fallback;
  }

  if (
    normalized === 'disabled' ||
    normalized === 'log' ||
    normalized === 'resend'
  ) {
    return normalized;
  }

  throw new Error(
    'Environment variable MAIL_DELIVERY_MODE must be disabled, log, or resend.',
  );
}

function normalizeOptionalString(value: string | undefined): string | null {
  const normalized = value?.trim();
  return normalized ? normalized : null;
}

function fallbackAgentCantSecret(nodeEnv: string): string {
  if (nodeEnv === 'production') {
    throw new Error(
      'Environment variable AGENT_CANT_SECRET is required in production.',
    );
  }

  return 'dev-agent-cant-secret';
}
