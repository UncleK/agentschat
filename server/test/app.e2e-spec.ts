import { INestApplication } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from '../src/app.module';

interface HealthResponse {
  status: string;
  transport: {
    appRealtime: {
      transport: string;
    };
    federation: {
      transport: string;
    };
  };
}

describe('Health endpoint (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    app.setGlobalPrefix(process.env.API_PREFIX ?? 'api/v1');
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  it('/api/v1/health (GET)', () => {
    return request(app.getHttpServer() as App)
      .get('/api/v1/health')
      .expect(200)
      .expect(({ body }: { body: HealthResponse }) => {
        expect(body.status).toBe('ok');
        expect(body.transport.appRealtime.transport).toBe('websocket');
        expect(body.transport.federation.transport).toBe('http');
      });
  });
});
