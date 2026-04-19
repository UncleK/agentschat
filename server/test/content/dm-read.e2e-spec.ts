import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { AgentDmAcceptanceMode } from '../../src/database/domain.enums';
import { PolicyService } from '../../src/modules/policy/policy.service';
import {
  TestApplicationContext,
  createTestApplication,
  typedValue,
} from '../support/test-app';
import { registerHuman } from '../federation/support/federation-test-support';

interface HumanOwnedAgent {
  id: string;
  handle: string;
  displayName: string;
}

interface DirectMessageResult {
  threadId: string;
  eventId: string;
}

interface DirectMessageThreadsPage {
  nextCursor: string | null;
  threads: Array<{
    threadId: string;
    unreadCount: number;
    threadUsage?: string;
    participants?: Array<{
      type: string;
      id: string;
      role: string;
    }>;
    lastMessage?: {
      actor?: {
        type: string;
        id: string;
        displayName: string;
      };
    };
  }>;
}

interface DirectMessageMessagesPage {
  nextCursor: string | null;
}

interface MarkReadResponse {
  threadId: string;
  unreadCount: number;
}

interface DirectMessageThreadPostResponse {
  threadId: string;
  activeAgentId: string;
  message: {
    actor: {
      type: string;
      id: string;
      displayName: string;
    };
    contentType: string;
    content: string | null;
  };
}

describe('DM read models (e2e)', () => {
  let app: INestApplication;
  let context: TestApplicationContext;
  let policyService: PolicyService;

  beforeAll(async () => {
    context = await createTestApplication();
    app = context.app;
    policyService = app.get(PolicyService);
  });

  afterAll(async () => {
    await context?.close();
  });

  it('lists active-agent-scoped thread summaries with remote member counterparts and cursor pagination', async () => {
    const owner = await registerHuman(
      app,
      'dm-reader-owner@example.com',
      'DM Reader Owner',
    );
    const remoteOwner = await registerHuman(
      app,
      'dm-reader-remote@example.com',
      'DM Reader Remote Owner',
    );
    const activeAlpha = await importHumanOwnedAgent(
      owner.accessToken,
      'dm-reader-alpha',
      'DM Reader Alpha',
    );
    const activeBeta = await importHumanOwnedAgent(
      owner.accessToken,
      'dm-reader-beta',
      'DM Reader Beta',
    );
    const remoteOne = await importHumanOwnedAgent(
      remoteOwner.accessToken,
      'dm-reader-remote-one',
      'DM Reader Remote One',
    );
    const remoteTwo = await importHumanOwnedAgent(
      remoteOwner.accessToken,
      'dm-reader-remote-two',
      'DM Reader Remote Two',
    );
    await policyService.upsertAgentSafetyPolicy(remoteOne.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });
    await policyService.upsertAgentSafetyPolicy(remoteTwo.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });

    await sendDirectMessage(owner.accessToken, {
      activeAgentId: activeAlpha.id,
      recipientType: 'agent',
      recipientAgentId: remoteOne.id,
      content: 'Alpha thread one.',
    });
    await pause();
    await sendDirectMessage(owner.accessToken, {
      activeAgentId: activeBeta.id,
      recipientType: 'agent',
      recipientAgentId: remoteOne.id,
      content: 'Beta isolated thread.',
    });
    await pause();
    const latestAlphaThread = await sendDirectMessage(owner.accessToken, {
      activeAgentId: activeAlpha.id,
      recipientType: 'agent',
      recipientAgentId: remoteTwo.id,
      content: 'Alpha thread two.',
    });

    const firstPage = await request(app.getHttpServer())
      .get('/api/v1/content/dm/threads')
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .query({
        activeAgentId: activeAlpha.id,
        limit: 1,
      })
      .expect(200);
    const firstPageBody = typedValue<DirectMessageThreadsPage>(firstPage.body);

    expect(firstPage.body).toMatchObject(
      typedValue<Record<string, unknown>>({
        activeAgentId: activeAlpha.id,
        threads: [
          {
            threadId: latestAlphaThread.threadId,
            threadUsage: 'network_dm',
            counterpart: {
              type: 'agent',
              id: remoteTwo.id,
              displayName: remoteTwo.displayName,
              handle: remoteTwo.handle,
              avatarUrl: null,
            },
            lastMessage: {
              eventId: latestAlphaThread.eventId,
              actor: {
                type: 'agent',
                id: activeAlpha.id,
                displayName: activeAlpha.displayName,
              },
              contentType: 'text',
              preview: 'Alpha thread two.',
              occurredAt: typedValue<unknown>(expect.any(String)),
            },
            unreadCount: 0,
          },
        ],
      }),
    );
    expect(firstPageBody.nextCursor).toEqual(expect.any(String));
    expect(firstPageBody.threads[0]?.participants).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          type: 'agent',
          id: activeAlpha.id,
          role: 'member',
        }),
        expect.objectContaining({
          type: 'agent',
          id: remoteTwo.id,
          role: 'member',
        }),
        expect.objectContaining({
          type: 'human',
          id: owner.user.id,
          role: 'spectator',
        }),
        expect.objectContaining({
          type: 'human',
          id: remoteOwner.user.id,
          role: 'spectator',
        }),
      ]),
    );

    const secondPage = await request(app.getHttpServer())
      .get('/api/v1/content/dm/threads')
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .query({
        activeAgentId: activeAlpha.id,
        limit: 1,
        cursor: firstPageBody.nextCursor,
      })
      .expect(200);
    expect(secondPage.body).toMatchObject(
      typedValue<Record<string, unknown>>({
        activeAgentId: activeAlpha.id,
        threads: [
          {
            threadUsage: 'network_dm',
            counterpart: {
              type: 'agent',
              id: remoteOne.id,
              displayName: remoteOne.displayName,
              handle: remoteOne.handle,
              avatarUrl: null,
            },
            lastMessage: {
              contentType: 'text',
              preview: 'Alpha thread one.',
              occurredAt: typedValue<unknown>(expect.any(String)),
            },
            unreadCount: 0,
          },
        ],
        nextCursor: null,
      }),
    );

    const betaThreads = await request(app.getHttpServer())
      .get('/api/v1/content/dm/threads')
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .query({
        activeAgentId: activeBeta.id,
      })
      .expect(200);
    const betaThreadsBody = typedValue<DirectMessageThreadsPage>(
      betaThreads.body,
    );

    expect(betaThreads.body).toMatchObject(
      typedValue<Record<string, unknown>>({
        activeAgentId: activeBeta.id,
        threads: [
          {
            threadUsage: 'network_dm',
            counterpart: {
              type: 'agent',
              id: remoteOne.id,
              displayName: remoteOne.displayName,
              handle: remoteOne.handle,
              avatarUrl: null,
            },
            lastMessage: {
              contentType: 'text',
              preview: 'Beta isolated thread.',
              occurredAt: typedValue<unknown>(expect.any(String)),
            },
            unreadCount: 0,
          },
        ],
        nextCursor: null,
      }),
    );
    expect(betaThreadsBody.threads).toHaveLength(1);

    await request(app.getHttpServer())
      .get('/api/v1/content/dm/threads')
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .query({
        activeAgentId: remoteOne.id,
      })
      .expect(403);
  });

  it('returns ascending messages with older-history cursors and rejects invalid ownership or membership scopes', async () => {
    const owner = await registerHuman(
      app,
      'dm-reader-messages-owner@example.com',
      'DM Messages Owner',
    );
    const remoteOwner = await registerHuman(
      app,
      'dm-reader-messages-remote@example.com',
      'DM Messages Remote Owner',
    );
    const activeAgent = await importHumanOwnedAgent(
      owner.accessToken,
      'dm-messages-active',
      'DM Messages Active',
    );
    const siblingAgent = await importHumanOwnedAgent(
      owner.accessToken,
      'dm-messages-sibling',
      'DM Messages Sibling',
    );
    const remoteAgent = await importHumanOwnedAgent(
      remoteOwner.accessToken,
      'dm-messages-remote',
      'DM Messages Remote',
    );
    const otherRemoteAgent = await importHumanOwnedAgent(
      remoteOwner.accessToken,
      'dm-messages-remote-other',
      'DM Messages Remote Other',
    );
    await policyService.upsertAgentSafetyPolicy(activeAgent.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });
    await policyService.upsertAgentSafetyPolicy(remoteAgent.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });
    await policyService.upsertAgentSafetyPolicy(otherRemoteAgent.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });

    const oldestMessage = await sendDirectMessage(owner.accessToken, {
      activeAgentId: activeAgent.id,
      recipientType: 'agent',
      recipientAgentId: remoteAgent.id,
      content: 'Oldest message.',
    });
    await pause();
    await sendDirectMessage(remoteOwner.accessToken, {
      activeAgentId: remoteAgent.id,
      recipientType: 'agent',
      recipientAgentId: activeAgent.id,
      content: 'Middle message.',
    });
    await pause();
    const newestMessage = await sendDirectMessage(owner.accessToken, {
      activeAgentId: activeAgent.id,
      recipientType: 'agent',
      recipientAgentId: remoteAgent.id,
      content: 'Newest message.',
    });
    const unrelatedThread = await sendDirectMessage(owner.accessToken, {
      activeAgentId: siblingAgent.id,
      recipientType: 'agent',
      recipientAgentId: otherRemoteAgent.id,
      content: 'Sibling-only thread.',
    });

    const firstPage = await request(app.getHttpServer())
      .get(`/api/v1/content/dm/threads/${oldestMessage.threadId}/messages`)
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .query({
        activeAgentId: activeAgent.id,
        limit: 2,
      })
      .expect(200);
    const firstPageBody = typedValue<DirectMessageMessagesPage>(firstPage.body);

    expect(firstPage.body).toMatchObject(
      typedValue<Record<string, unknown>>({
        threadId: oldestMessage.threadId,
        activeAgentId: activeAgent.id,
        messages: [
          {
            actor: {
              type: 'agent',
              id: remoteAgent.id,
              displayName: remoteAgent.displayName,
            },
            contentType: 'text',
            content: 'Middle message.',
            asset: null,
            occurredAt: typedValue<unknown>(expect.any(String)),
          },
          {
            eventId: newestMessage.eventId,
            actor: {
              type: 'agent',
              id: activeAgent.id,
              displayName: activeAgent.displayName,
            },
            contentType: 'text',
            content: 'Newest message.',
            asset: null,
            occurredAt: typedValue<unknown>(expect.any(String)),
          },
        ],
      }),
    );
    expect(firstPageBody.nextCursor).toEqual(expect.any(String));

    const olderPage = await request(app.getHttpServer())
      .get(`/api/v1/content/dm/threads/${oldestMessage.threadId}/messages`)
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .query({
        activeAgentId: activeAgent.id,
        limit: 2,
        cursor: firstPageBody.nextCursor,
      })
      .expect(200);

    expect(olderPage.body).toMatchObject(
      typedValue<Record<string, unknown>>({
        threadId: oldestMessage.threadId,
        activeAgentId: activeAgent.id,
        messages: [
          {
            eventId: oldestMessage.eventId,
            actor: {
              type: 'agent',
              id: activeAgent.id,
              displayName: activeAgent.displayName,
            },
            contentType: 'text',
            content: 'Oldest message.',
            asset: null,
            occurredAt: typedValue<unknown>(expect.any(String)),
          },
        ],
        nextCursor: null,
      }),
    );

    await request(app.getHttpServer())
      .get(`/api/v1/content/dm/threads/${oldestMessage.threadId}/messages`)
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .query({
        activeAgentId: remoteAgent.id,
      })
      .expect(403);

    await request(app.getHttpServer())
      .get(`/api/v1/content/dm/threads/${unrelatedThread.threadId}/messages`)
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .query({
        activeAgentId: activeAgent.id,
      })
      .expect(404);
  });

  it('computes unread counts from participant read markers and marks DM threads read idempotently', async () => {
    const owner = await registerHuman(
      app,
      'dm-read-state-owner@example.com',
      'DM Read State Owner',
    );
    const remoteOwner = await registerHuman(
      app,
      'dm-read-state-remote@example.com',
      'DM Read State Remote Owner',
    );
    const activeAgent = await importHumanOwnedAgent(
      owner.accessToken,
      'dm-read-state-active',
      'DM Read State Active',
    );
    const siblingAgent = await importHumanOwnedAgent(
      owner.accessToken,
      'dm-read-state-sibling',
      'DM Read State Sibling',
    );
    const remoteAgent = await importHumanOwnedAgent(
      remoteOwner.accessToken,
      'dm-read-state-remote',
      'DM Read State Remote',
    );
    const otherRemoteAgent = await importHumanOwnedAgent(
      remoteOwner.accessToken,
      'dm-read-state-remote-other',
      'DM Read State Remote Other',
    );
    await policyService.upsertAgentSafetyPolicy(activeAgent.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });
    await policyService.upsertAgentSafetyPolicy(remoteAgent.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });
    await policyService.upsertAgentSafetyPolicy(otherRemoteAgent.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });

    const targetThread = await sendDirectMessage(owner.accessToken, {
      activeAgentId: activeAgent.id,
      recipientType: 'agent',
      recipientAgentId: remoteAgent.id,
      content: 'Initial local message.',
    });
    await pause();
    await sendDirectMessage(remoteOwner.accessToken, {
      activeAgentId: remoteAgent.id,
      recipientType: 'agent',
      recipientAgentId: activeAgent.id,
      content: 'Unread remote reply.',
    });
    await pause();
    await sendDirectMessage(owner.accessToken, {
      activeAgentId: activeAgent.id,
      recipientType: 'agent',
      recipientAgentId: remoteAgent.id,
      content: 'Latest local follow-up.',
    });
    await pause();
    const unrelatedThread = await sendDirectMessage(owner.accessToken, {
      activeAgentId: siblingAgent.id,
      recipientType: 'agent',
      recipientAgentId: otherRemoteAgent.id,
      content: 'Sibling-only thread.',
    });

    const unreadThreads = await request(app.getHttpServer())
      .get('/api/v1/content/dm/threads')
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .query({
        activeAgentId: activeAgent.id,
      })
      .expect(200);
    expect(unreadThreads.body).toMatchObject(
      typedValue<Record<string, unknown>>({
        activeAgentId: activeAgent.id,
        threads: [
          {
            threadId: targetThread.threadId,
            threadUsage: 'network_dm',
            counterpart: {
              type: 'agent',
              id: remoteAgent.id,
              displayName: remoteAgent.displayName,
              handle: remoteAgent.handle,
              avatarUrl: null,
            },
            lastMessage: {
              contentType: 'text',
              preview: 'Latest local follow-up.',
              occurredAt: typedValue<unknown>(expect.any(String)),
            },
            unreadCount: 1,
          },
        ],
        nextCursor: null,
      }),
    );

    const firstRead = await request(app.getHttpServer())
      .post(`/api/v1/content/dm/threads/${targetThread.threadId}/read`)
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .send({
        activeAgentId: activeAgent.id,
      })
      .expect(200);
    const firstReadBody = typedValue<MarkReadResponse>(firstRead.body);

    expect(firstReadBody).toEqual({
      threadId: targetThread.threadId,
      unreadCount: 0,
    });

    const repeatedRead = await request(app.getHttpServer())
      .post(`/api/v1/content/dm/threads/${targetThread.threadId}/read`)
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .send({
        activeAgentId: activeAgent.id,
      })
      .expect(200);
    const repeatedReadBody = typedValue<MarkReadResponse>(repeatedRead.body);

    expect(repeatedReadBody).toEqual({
      threadId: targetThread.threadId,
      unreadCount: 0,
    });

    const readThreads = await request(app.getHttpServer())
      .get('/api/v1/content/dm/threads')
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .query({
        activeAgentId: activeAgent.id,
      })
      .expect(200);
    expect(readThreads.body).toMatchObject(
      typedValue<Record<string, unknown>>({
        activeAgentId: activeAgent.id,
        threads: [
          {
            threadId: targetThread.threadId,
            unreadCount: 0,
          },
        ],
        nextCursor: null,
      }),
    );

    await request(app.getHttpServer())
      .post(`/api/v1/content/dm/threads/${targetThread.threadId}/read`)
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .send({
        activeAgentId: remoteAgent.id,
      })
      .expect(403);

    await request(app.getHttpServer())
      .post(`/api/v1/content/dm/threads/${unrelatedThread.threadId}/read`)
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .send({
        activeAgentId: activeAgent.id,
      })
      .expect(404);
  });

  it('lets the thread owner post a human-authored message into an existing active-agent DM thread', async () => {
    const owner = await registerHuman(
      app,
      'dm-thread-human-post-owner@example.com',
      'DM Human Post Owner',
    );
    const remoteOwner = await registerHuman(
      app,
      'dm-thread-human-post-remote@example.com',
      'DM Human Post Remote',
    );
    const activeAgent = await importHumanOwnedAgent(
      owner.accessToken,
      'dm-human-post-active',
      'DM Human Post Active',
    );
    const remoteAgent = await importHumanOwnedAgent(
      remoteOwner.accessToken,
      'dm-human-post-remote',
      'DM Human Post Remote',
    );
    await policyService.upsertAgentSafetyPolicy(activeAgent.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });
    await policyService.upsertAgentSafetyPolicy(remoteAgent.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });

    const initialThread = await sendDirectMessage(owner.accessToken, {
      activeAgentId: activeAgent.id,
      recipientType: 'agent',
      recipientAgentId: remoteAgent.id,
      content: 'Initial agent-authored opener.',
    });

    const postResponse = await request(app.getHttpServer())
      .post(`/api/v1/content/dm/threads/${initialThread.threadId}/messages`)
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .send({
        activeAgentId: activeAgent.id,
        contentType: 'text',
        content: 'Human clarification inside the existing thread.',
      })
      .expect(201);
    const postBody = typedValue<DirectMessageThreadPostResponse>(
      postResponse.body,
    );

    expect(postBody).toMatchObject({
      threadId: initialThread.threadId,
      activeAgentId: activeAgent.id,
      message: {
        actor: {
          type: 'human',
          id: typedValue<unknown>(expect.any(String)),
          displayName: 'DM Human Post Owner',
        },
        contentType: 'text',
        content: 'Human clarification inside the existing thread.',
      },
    });

    const messages = await request(app.getHttpServer())
      .get(`/api/v1/content/dm/threads/${initialThread.threadId}/messages`)
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .query({
        activeAgentId: activeAgent.id,
      })
      .expect(200);

    expect(messages.body).toMatchObject(
      typedValue<Record<string, unknown>>({
        threadId: initialThread.threadId,
        activeAgentId: activeAgent.id,
        messages: [
          {
            actor: {
              type: 'agent',
              id: activeAgent.id,
              displayName: activeAgent.displayName,
            },
            contentType: 'text',
            content: 'Initial agent-authored opener.',
          },
          {
            actor: {
              type: 'human',
              id: typedValue<unknown>(expect.any(String)),
              displayName: 'DM Human Post Owner',
            },
            contentType: 'text',
            content: 'Human clarification inside the existing thread.',
          },
        ],
      }),
    );
  });

  it('forbids external DM creation without an active agent and still allows owner-to-owned-agent command chat', async () => {
    const owner = await registerHuman(
      app,
      'dm-command-chat-owner@example.com',
      'DM Command Owner',
    );
    const remoteOwner = await registerHuman(
      app,
      'dm-command-chat-remote@example.com',
      'DM Command Remote',
    );
    const ownedAgent = await importHumanOwnedAgent(
      owner.accessToken,
      'dm-command-owned',
      'DM Command Owned',
    );
    const remoteAgent = await importHumanOwnedAgent(
      remoteOwner.accessToken,
      'dm-command-remote',
      'DM Command Remote',
    );

    await policyService.upsertAgentSafetyPolicy(ownedAgent.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });
    await policyService.upsertAgentSafetyPolicy(remoteAgent.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });

    await request(app.getHttpServer())
      .post('/api/v1/content/dm')
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .send({
        recipientType: 'agent',
        recipientAgentId: remoteAgent.id,
        contentType: 'text',
        content: 'This should be rejected without an active agent.',
      })
      .expect(403);

    await request(app.getHttpServer())
      .post('/api/v1/content/dm')
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .send({
        recipientType: 'human',
        recipientUserId: remoteOwner.user.id,
        contentType: 'text',
        content: 'This external human DM should also be rejected.',
      })
      .expect(403);

    const commandChatResponse = await request(app.getHttpServer())
      .post('/api/v1/content/dm')
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .send({
        recipientType: 'agent',
        recipientAgentId: ownedAgent.id,
        contentType: 'text',
        content: 'Owner-to-owned-agent command chat works.',
      })
      .expect(201);
    const commandChatBody = typedValue<DirectMessageResult>(
      commandChatResponse.body,
    );

    await request(app.getHttpServer())
      .get('/api/v1/content/dm/threads')
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .query({
        activeAgentId: ownedAgent.id,
      })
      .expect(200)
      .expect(({ body }: { body: DirectMessageThreadsPage }) => {
        expect(body.threads).toHaveLength(1);
        expect(body.threads[0]?.threadId).toBe(commandChatBody.threadId);
        expect(body.threads[0]?.threadUsage).toBe('owned_agent_command');
      });

    const messages = await request(app.getHttpServer())
      .get(`/api/v1/content/dm/threads/${commandChatBody.threadId}/messages`)
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .query({
        activeAgentId: ownedAgent.id,
      })
      .expect(200);

    expect(messages.body).toMatchObject(
      typedValue<Record<string, unknown>>({
        threadId: commandChatBody.threadId,
        activeAgentId: ownedAgent.id,
        messages: [
          {
            actor: {
              type: 'human',
              id: typedValue<unknown>(expect.any(String)),
              displayName: 'DM Command Owner',
            },
            contentType: 'text',
            content: 'Owner-to-owned-agent command chat works.',
          },
        ],
      }),
    );
  });

  async function importHumanOwnedAgent(
    accessToken: string,
    handle: string,
    displayName: string,
  ): Promise<HumanOwnedAgent> {
    const response = await request(app.getHttpServer())
      .post('/api/v1/agents/import/human')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        handle,
        displayName,
      })
      .expect(201);

    return typedValue<HumanOwnedAgent>(response.body);
  }

  async function sendDirectMessage(
    accessToken: string,
    body: {
      activeAgentId: string;
      recipientType: 'agent';
      recipientAgentId: string;
      content: string;
    },
  ): Promise<DirectMessageResult> {
    const response = await request(app.getHttpServer())
      .post('/api/v1/content/dm')
      .set('Authorization', `Bearer ${accessToken}`)
      .send(body)
      .expect(201);

    return typedValue<DirectMessageResult>(response.body);
  }

  async function pause(milliseconds = 15) {
    await new Promise((resolve) => setTimeout(resolve, milliseconds));
  }
});
