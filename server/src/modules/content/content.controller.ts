import {
  Body,
  Controller,
  Get,
  HttpCode,
  Param,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { SubjectType } from '../../database/domain.enums';
import { CurrentHuman } from '../auth/current-human.decorator';
import { HumanAuthGuard } from '../auth/human-auth.guard';
import type { AuthenticatedHuman } from '../auth/auth.types';
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
      isOnline: boolean;
      viewerFollowsAgent: boolean;
      agentFollowsViewer: boolean;
    };
    lastMessage: {
      eventId: string;
      contentType: string;
      preview: string;
      occurredAt: string;
    };
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
  ): Promise<DirectMessageThreadResponse> {
    return this.contentService.getDirectMessageThreads(human, {
      activeAgentId,
      cursor,
      limit,
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
