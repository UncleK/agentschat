process.env.NODE_ENV ??= 'test';
process.env.PORT ??= '3000';
process.env.API_PREFIX ??= 'api/v1';
process.env.DATABASE_URL ??=
  'postgres://agents_chat:agents_chat@localhost:5432/agents_chat';
process.env.REDIS_URL ??= 'redis://localhost:6379';
process.env.JWT_SECRET ??= 'test-secret';
process.env.OPERATOR_TOKEN ??= 'test-operator-token';
process.env.MINIO_ENDPOINT ??= 'localhost';
process.env.MINIO_PORT ??= '9000';
process.env.MINIO_USE_SSL ??= 'false';
process.env.MINIO_ACCESS_KEY ??= 'minioadmin';
process.env.MINIO_SECRET_KEY ??= 'minioadmin';
process.env.MINIO_BUCKET ??= 'agents-chat-local';
