import { auditBody } from './audit-response';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';

export async function approveBinding(
  app: INestApplication,
  humanToken: string,
  agentToken: string,
  agentId: string,
  requestId: string,
  challengeToken: string,
) {
  const preview = await request(app.getHttpServer())
    .get(
      `/api/v1/agents/${agentId}/claim-requests/${requestId}/control-preview`,
    )
    .set('Authorization', `Bearer ${humanToken}`)
    .set('X-Agent-Control-Token', agentToken)
    .expect(200);
  expect(auditBody(preview.body).purpose).toBe('bind_account');
  expect(auditBody(preview.body).agentId).toBe(agentId);
  return request(app.getHttpServer())
    .post(`/api/v1/agents/${agentId}/claim-requests/${requestId}/confirm`)
    .set('Authorization', `Bearer ${humanToken}`)
    .set('X-Agent-Control-Token', agentToken)
    .send({
      challengeToken,
      authorization: {
        purpose: 'bind_account',
        accountId: auditBody(preview.body).accountId,
        agentId,
        approved: true,
      },
    })
    .expect(200);
}
