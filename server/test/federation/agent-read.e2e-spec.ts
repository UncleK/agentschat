import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { AgentDmAcceptanceMode } from '../../src/database/domain.enums';
import { FederationCredentialsService } from '../../src/modules/federation/federation-credentials.service';
import { PolicyService } from '../../src/modules/policy/policy.service';
import {
  TestApplicationContext,
  createTestApplication,
  typedValue,
} from '../support/test-app';
import {
  claimFederatedAgent,
  importSelfAgent,
  waitForActionStatus,
} from './support/federation-test-support';

interface AcceptedActionResponse {
  id: string;
}

interface CompletedActionResponse {
  id: string;
  status: string;
  eventId: string | null;
  threadId: string | null;
}

interface DirectoryResponse {
  actor: {
    type: string;
    id: string;
  };
  agents: Array<{
    id: string;
    handle: string;
    displayName: string;
    dmPolicy: {
      directMessageAllowed: boolean;
    };
  }>;
}

interface DirectMessageThreadsResponse {
  activeAgentId: string;
  threads: Array<{
    threadId: string;
    unreadCount: number;
    counterpart: {
      id: string;
      handle: string | null;
      displayName: string;
    };
    lastMessage: {
      contentType: string;
      preview: string;
    };
  }>;
}

interface DirectMessageMessagesResponse {
  activeAgentId: string;
  threadId: string;
  messages: Array<{
    actor: {
      type: string;
      id: string;
      displayName: string;
    };
    contentType: string;
    content: string | null;
  }>;
}

interface ForumTopicsResponse {
  activeAgentId: string;
  topics: Array<{
    threadId: string;
    title: string;
    replyCount: number;
  }>;
}

interface ForumTopicResponse {
  activeAgentId: string;
  topic: {
    threadId: string;
    title: string;
    replies: Array<{
      authorName: string;
      body: string;
    }>;
  };
}

describe('Federated agent read models (e2e)', () => {
  let app: INestApplication;
  let context: TestApplicationContext;
  let federationCredentialsService: FederationCredentialsService;
  let policyService: PolicyService;

  beforeAll(async () => {
    context = await createTestApplication();
    app = context.app;
    federationCredentialsService = app.get(FederationCredentialsService);
    policyService = app.get(PolicyService);
  });

  afterAll(async () => {
    await context?.close();
  });

  it('lets a claimed agent read the directory, its DM history, and forum topics without human auth', async () => {
    const author = await importSelfAgent(
      app,
      'agent-read-author',
      'Agent Read Author',
    );
    const peer = await importSelfAgent(
      app,
      'agent-read-peer',
      'Agent Read Peer',
    );

    await policyService.upsertAgentSafetyPolicy(peer.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });

    const authorClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      author.id,
      {
        pollingEnabled: true,
      },
    );
    const peerClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      peer.id,
      {
        pollingEnabled: true,
      },
    );

    const directMessage = await submitAction(
      authorClaim.accessToken,
      'agent-read-dm',
      {
        type: 'dm.send',
        payload: {
          targetType: 'agent',
          targetId: peer.id,
          contentType: 'text',
          content: 'Federated hello.',
        },
      },
    );
    const topic = await submitAction(
      authorClaim.accessToken,
      'agent-read-topic',
      {
        type: 'forum.topic.create',
        payload: {
          title: 'Skill-facing topic',
          tags: ['skill', 'federation'],
          contentType: 'markdown',
          content: 'Opening forum topic for skill clients.',
        },
      },
    );
    await submitAction(peerClaim.accessToken, 'agent-read-reply', {
      type: 'forum.reply.create',
      payload: {
        threadId: topic.threadId,
        parentEventId: topic.eventId,
        contentType: 'text',
        content: 'Federated reply.',
      },
    });

    const directoryResponse = await request(app.getHttpServer())
      .get('/api/v1/agents/directory/self')
      .set('Authorization', `Bearer ${authorClaim.accessToken}`)
      .expect(200);
    const directoryBody = typedValue<DirectoryResponse>(directoryResponse.body);

    expect(directoryBody.actor).toEqual({
      type: 'agent',
      id: author.id,
    });
    const peerDirectoryEntry = directoryBody.agents.find(
      (entry) => entry.id === peer.id,
    );

    expect(peerDirectoryEntry).toBeDefined();
    if (!peerDirectoryEntry) {
      throw new Error('Expected peer directory entry to exist.');
    }

    expect(peerDirectoryEntry.handle).toBe('agent-read-peer');
    expect(peerDirectoryEntry.displayName).toBe('Agent Read Peer');
    expect(peerDirectoryEntry.dmPolicy.directMessageAllowed).toBe(true);

    const dmThreadsResponse = await request(app.getHttpServer())
      .get('/api/v1/content/self/dm/threads')
      .set('Authorization', `Bearer ${peerClaim.accessToken}`)
      .expect(200);
    const dmThreadsBody = typedValue<DirectMessageThreadsResponse>(
      dmThreadsResponse.body,
    );

    expect(dmThreadsBody).toMatchObject({
      activeAgentId: peer.id,
      threads: [
        {
          threadId: directMessage.threadId,
          unreadCount: 1,
          counterpart: {
            id: author.id,
            handle: 'agent-read-author',
            displayName: 'Agent Read Author',
          },
          lastMessage: {
            contentType: 'text',
            preview: 'Federated hello.',
          },
        },
      ],
    });

    const dmMessagesResponse = await request(app.getHttpServer())
      .get(`/api/v1/content/self/dm/threads/${directMessage.threadId}/messages`)
      .set('Authorization', `Bearer ${peerClaim.accessToken}`)
      .expect(200);
    const dmMessagesBody = typedValue<DirectMessageMessagesResponse>(
      dmMessagesResponse.body,
    );

    expect(dmMessagesBody).toMatchObject({
      activeAgentId: peer.id,
      threadId: directMessage.threadId,
      messages: [
        {
          actor: {
            type: 'agent',
            id: author.id,
            displayName: 'Agent Read Author',
          },
          contentType: 'text',
          content: 'Federated hello.',
        },
      ],
    });

    const forumTopicsResponse = await request(app.getHttpServer())
      .get('/api/v1/content/self/forum/topics')
      .set('Authorization', `Bearer ${peerClaim.accessToken}`)
      .expect(200);
    const forumTopicsBody = typedValue<ForumTopicsResponse>(
      forumTopicsResponse.body,
    );

    expect(forumTopicsBody).toMatchObject({
      activeAgentId: peer.id,
      topics: [
        {
          threadId: topic.threadId,
          title: 'Skill-facing topic',
          replyCount: 1,
        },
      ],
    });

    const forumTopicResponse = await request(app.getHttpServer())
      .get(`/api/v1/content/self/forum/topics/${topic.threadId}`)
      .set('Authorization', `Bearer ${peerClaim.accessToken}`)
      .expect(200);
    const forumTopicBody = typedValue<ForumTopicResponse>(
      forumTopicResponse.body,
    );

    expect(forumTopicBody).toMatchObject({
      activeAgentId: peer.id,
      topic: {
        threadId: topic.threadId,
        title: 'Skill-facing topic',
        replies: [
          {
            authorName: 'Agent Read Peer',
            body: 'Federated reply.',
          },
        ],
      },
    });
  });

  async function submitAction(
    accessToken: string,
    idempotencyKey: string,
    body: Record<string, unknown>,
  ): Promise<CompletedActionResponse> {
    const response = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${accessToken}`)
      .set('Idempotency-Key', idempotencyKey)
      .send(body)
      .expect(202);
    const acceptedAction = typedValue<AcceptedActionResponse>(response.body);
    const completedAction = typedValue<CompletedActionResponse>(
      await waitForActionStatus(app, accessToken, acceptedAction.id),
    );

    expect(completedAction.status).toBe('succeeded');

    return completedAction;
  }
});
