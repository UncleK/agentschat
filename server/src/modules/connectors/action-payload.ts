import { z } from 'zod';
import contract from './connector-tools.json';
import { FederationActionRejectionError } from '../federation/federation.errors';

export function validateActionPayload(
  type: string,
  payload: Record<string, unknown>,
) {
  const schemas: Record<string, unknown> = contract.actionPayloadSchemas;
  if (type.startsWith('forum.debate.') && schemas[type]) {
    const result = z
      .fromJSONSchema(schemas[type] as Parameters<typeof z.fromJSONSchema>[0])
      .safeParse(payload);
    if (!result.success)
      throw new FederationActionRejectionError(
        'invalid_payload',
        'Correct the slow-debate fields listed in details.issues.',
        {
          issues: result.error.issues.map((issue) => ({
            field: issue.path.join('.'),
            message: issue.message,
          })),
          schema: schemas[type],
          retryable: false,
          nextAction:
            'Correct the rejected operation and submit it with a new idempotency key.',
        },
      );
  }
  if (type === 'forum.topic.create' || type === 'forum.reply.create') {
    const required = type === 'forum.topic.create' ? ['title'] : ['threadId'];
    const missing = required.filter(
      (field) =>
        typeof payload[field] !== 'string' || !String(payload[field]).trim(),
    );
    const hasContent = ['content', 'caption', 'assetId', 'asset_id'].some(
      (field) =>
        typeof payload[field] === 'string' && !!String(payload[field]).trim(),
    );
    if (missing.length || !hasContent)
      throw new FederationActionRejectionError(
        'invalid_payload',
        missing.length
          ? missing.join(', ') + ' is required.'
          : 'Provide content, caption, or an uploaded assetId. Use content for text, not body.',
        {
          requiredFields: missing,
          ...(!hasContent
            ? { requiredOneOf: ['content', 'caption', 'assetId'] }
            : {}),
          ...(Object.hasOwn(payload, 'body')
            ? { renameField: { body: 'content' } }
            : {}),
          retryable: false,
          nextAction:
            'Correct the rejected operation and submit it with a new idempotency key.',
        },
      );
  }
}
