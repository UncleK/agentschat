import {
  BadRequestException,
  Body,
  Controller,
  Get,
  HttpCode,
  Param,
  Post,
  Query,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { SubjectType } from '../../database/domain.enums';
import { CurrentHuman } from '../auth/current-human.decorator';
import { HumanAuthGuard } from '../auth/human-auth.guard';
import type { AuthenticatedHuman } from '../auth/auth.types';
import { CurrentFederatedAgent } from '../federation/current-federated-agent.decorator';
import { FederationAuthGuard } from '../federation/federation-auth.guard';
import type { AuthenticatedFederatedAgent } from '../federation/federation.types';
import { ContentService } from './content.service';

interface SendHumanDirectMessageBody {
  recipientType: SubjectType.Human | SubjectType.Agent;
  recipientUserId?: string | null;
  recipientAgentId?: string | null;
  contentType?: string | null;
  content?: string | null;
  caption?: string | null;
  assetId?: string | null;
  asset_id?: string | null;
  metadata?: Record<string, unknown>;
  actorType?: string | null;
  actorAgentId?: string | null;
  activeAgentId?: string | null;
}

interface MarkDirectMessageThreadReadBody {
  activeAgentId?: string | null;
}

interface SendDirectMessageThreadMessageBody {
  activeAgentId?: string | null;
  contentType?: string | null;
  content?: string | null;
  caption?: string | null;
  assetId?: string | null;
  asset_id?: string | null;
  metadata?: Record<string, unknown>;
}

interface SendDirectMessageThreadVoiceBody {
  activeAgentId?: string | null;
}

interface DirectMessageThreadResponse {
  activeAgentId: string;
  threads: Array<{
    threadId: string;
    counterpart: {
      type: SubjectType;
      id: string;
      displayName: string;
      handle: string | null;
      avatarUrl: string | null;
      avatarEmoji: string | null;
      isOnline: boolean;
      viewerFollowsAgent: boolean;
      agentFollowsViewer: boolean;
    };
    lastMessage: {
      eventId: string;
      actor: {
        type: SubjectType;
        id: string;
        displayName: string;
      };
      contentType: string;
      preview: string;
      occurredAt: string;
    };
    participants: Array<{
      type: SubjectType;
      id: string;
      displayName: string;
      handle: string | null;
      avatarUrl: string | null;
      avatarEmoji: string | null;
      isOnline: boolean;
      role: string;
    }>;
    threadUsage?: string;
    unreadCount: number;
  }>;
  nextCursor: string | null;
}

interface DirectMessageMessagesResponse {
  threadId: string;
  activeAgentId: string;
  messages: Array<{
    eventId: string;
    actor: {
      type: SubjectType;
      id: string;
      displayName: string;
    };
    contentType: string;
    content: string | null;
    asset: {
      id: string;
      kind: string;
      mimeType: string;
      byteSize: number | null;
      storageBucket: string;
      storageKey: string;
    } | null;
    metadata: Record<string, unknown>;
    occurredAt: string;
  }>;
  nextCursor: string | null;
}

interface DirectMessageReadResponse {
  threadId: string;
  unreadCount: number;
}

interface DirectMessageThreadMessageResponse {
  threadId: string;
  activeAgentId: string;
  message: {
    eventId: string;
    actor: {
      type: SubjectType;
      id: string;
      displayName: string;
    };
    contentType: string;
    content: string | null;
    asset: {
      id: string;
      kind: string;
      mimeType: string;
      byteSize: number | null;
      storageBucket: string;
      storageKey: string;
    } | null;
    metadata: Record<string, unknown>;
    occurredAt: string;
  };
}

interface CreateForumTopicBody {
  activeAgentId?: string | null;
  title?: string | null;
  tags?: unknown;
  contentType?: string | null;
  content?: string | null;
  caption?: string | null;
  assetId?: string | null;
  asset_id?: string | null;
  metadata?: Record<string, unknown>;
}

interface CreateForumReplyBody {
  activeAgentId?: string | null;
  parentEventId?: string | null;
  contentType?: string | null;
  content?: string | null;
  caption?: string | null;
  assetId?: string | null;
  asset_id?: string | null;
  metadata?: Record<string, unknown>;
}

interface ToggleForumReplyLikeBody {
  activeAgentId?: string | null;
}

@Controller('content')
export class ContentController {
  constructor(private readonly contentService: ContentService) {}

  @Post('dm')
  @UseGuards(HumanAuthGuard)
  sendHumanDirectMessage(
    @CurrentHuman() human: AuthenticatedHuman,
    @Body() body: SendHumanDirectMessageBody,
  ) {
    return this.contentService.sendHumanDirectMessage(human, body);
  }

  @Get('dm/threads')
  @UseGuards(HumanAuthGuard)
  getDirectMessageThreads(
    @CurrentHuman() human: AuthenticatedHuman,
    @Query('activeAgentId') activeAgentId?: string,
    @Query('cursor') cursor?: string,
    @Query('limit') limit?: string,
    @Query('threadUsage') threadUsage?: string,
  ): Promise<DirectMessageThreadResponse> {
    return this.contentService.getDirectMessageThreads(human, {
      activeAgentId,
      cursor,
      limit,
      threadUsage,
    });
  }

  @Get('self/dm/threads')
  @UseGuards(FederationAuthGuard)
  getFederatedDirectMessageThreads(
    @CurrentFederatedAgent() agent: AuthenticatedFederatedAgent,
    @Query('cursor') cursor?: string,
    @Query('limit') limit?: string,
    @Query('threadUsage') threadUsage?: string,
  ): Promise<DirectMessageThreadResponse> {
    return this.contentService.getAgentDirectMessageThreads(agent, {
      cursor,
      limit,
      threadUsage,
    });
  }

  @Get('dm/threads/:id/messages')
  @UseGuards(HumanAuthGuard)
  getDirectMessageThreadMessages(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('id') threadId: string,
    @Query('activeAgentId') activeAgentId?: string,
    @Query('cursor') cursor?: string,
    @Query('limit') limit?: string,
  ): Promise<DirectMessageMessagesResponse> {
    return this.contentService.getDirectMessageThreadMessages(human, threadId, {
      activeAgentId,
      cursor,
      limit,
    });
  }

  @Get('self/dm/threads/:id/messages')
  @UseGuards(FederationAuthGuard)
  getFederatedDirectMessageThreadMessages(
    @CurrentFederatedAgent() agent: AuthenticatedFederatedAgent,
    @Param('id') threadId: string,
    @Query('cursor') cursor?: string,
    @Query('limit') limit?: string,
  ): Promise<DirectMessageMessagesResponse> {
    return this.contentService.getAgentDirectMessageThreadMessages(
      agent,
      threadId,
      {
        cursor,
        limit,
      },
    );
  }

  @Post('dm/threads/:id/messages')
  @UseGuards(HumanAuthGuard)
  sendDirectMessageThreadMessage(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('id') threadId: string,
    @Body() body: SendDirectMessageThreadMessageBody,
  ): Promise<DirectMessageThreadMessageResponse> {
    return this.contentService.sendHumanDirectMessageToThread(
      human,
      threadId,
      body,
    );
  }

  @Post('dm/threads/:id/voice')
  @UseGuards(HumanAuthGuard)
  @UseInterceptors(FileInterceptor('file'))
  sendDirectMessageThreadVoice(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('id') threadId: string,
    @UploadedFile()
    file:
      | {
          originalname?: string;
          mimetype?: string;
          buffer: Buffer;
        }
      | undefined,
    @Body() body: SendDirectMessageThreadVoiceBody,
  ): Promise<DirectMessageThreadMessageResponse> {
    if (!file?.buffer || file.buffer.byteLength === 0) {
      throw new BadRequestException('file is required.');
    }

    return this.contentService.sendHumanVoiceDirectMessageToThread(
      human,
      threadId,
      {
        activeAgentId: body.activeAgentId,
        fileName: file.originalname,
        mimeType: file.mimetype,
        bytes: file.buffer,
      },
    );
  }

  @Post('dm/threads/:id/read')
  @HttpCode(200)
  @UseGuards(HumanAuthGuard)
  markDirectMessageThreadRead(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('id') threadId: string,
    @Body() body: MarkDirectMessageThreadReadBody,
  ): Promise<DirectMessageReadResponse> {
    return this.contentService.markDirectMessageThreadRead(human, threadId, {
      activeAgentId: body.activeAgentId,
    });
  }

  @Get('forum/topics')
  @UseGuards(HumanAuthGuard)
  listForumTopics(
    @CurrentHuman() human: AuthenticatedHuman,
    @Query('activeAgentId') activeAgentId?: string,
    @Query('query') query?: string,
    @Query('limit') limit?: string,
  ) {
    return this.contentService.listForumTopics(human, {
      activeAgentId,
      query,
      limit,
    });
  }

  @Get('public/forum/topics')
  listPublicForumTopics(
    @Query('query') query?: string,
    @Query('limit') limit?: string,
  ) {
    return this.contentService.listPublicForumTopics({
      query,
      limit,
    });
  }

  @Get('self/forum/topics')
  @UseGuards(FederationAuthGuard)
  listFederatedForumTopics(
    @CurrentFederatedAgent() agent: AuthenticatedFederatedAgent,
    @Query('query') query?: string,
    @Query('limit') limit?: string,
  ) {
    return this.contentService.listAgentForumTopics(agent, {
      query,
      limit,
    });
  }

  @Get('forum/topics/:id')
  @UseGuards(HumanAuthGuard)
  getForumTopic(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('id') threadId: string,
    @Query('activeAgentId') activeAgentId?: string,
  ) {
    return this.contentService.getForumTopic(human, threadId, {
      activeAgentId,
    });
  }

  @Get('public/forum/topics/:id')
  getPublicForumTopic(@Param('id') threadId: string) {
    return this.contentService.getPublicForumTopic(threadId);
  }

  @Get('self/forum/topics/:id')
  @UseGuards(FederationAuthGuard)
  getFederatedForumTopic(
    @CurrentFederatedAgent() agent: AuthenticatedFederatedAgent,
    @Param('id') threadId: string,
  ) {
    return this.contentService.getAgentForumTopic(agent, threadId);
  }

  @Post('forum/topics')
  @UseGuards(HumanAuthGuard)
  createForumTopic(
    @CurrentHuman() human: AuthenticatedHuman,
    @Body() body: CreateForumTopicBody,
  ) {
    return this.contentService.createHumanForumTopic(human, body);
  }

  @Post('forum/topics/:id/replies')
  @UseGuards(HumanAuthGuard)
  createForumReply(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('id') threadId: string,
    @Body() body: CreateForumReplyBody,
  ) {
    return this.contentService.createHumanForumReply(human, {
      ...body,
      threadId,
    });
  }

  @Post('forum/replies/:id/like')
  @UseGuards(HumanAuthGuard)
  toggleForumReplyLike(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('id') replyEventId: string,
    @Body() body: ToggleForumReplyLikeBody,
  ) {
    return this.contentService.toggleHumanForumReplyLike(
      human,
      replyEventId,
      body,
    );
  }
}
