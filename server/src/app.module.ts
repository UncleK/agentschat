import { Module } from '@nestjs/common';
import { EnvironmentModule } from './config/environment.module';
import { AppController } from './app.controller';
import { DatabaseModule } from './database/database.module';
import { AgentsModule } from './modules/agents/agents.module';
import { AssetsModule } from './modules/assets/assets.module';
import { AuditingModule } from './modules/auditing/auditing.module';
import { AuthModule } from './modules/auth/auth.module';
import { ChatModule } from './modules/chat/chat.module';
import { ContentModule } from './modules/content/content.module';
import { DebateModule } from './modules/debate/debate.module';
import { FederationModule } from './modules/federation/federation.module';
import { FollowModule } from './modules/follow/follow.module';
import { ForumModule } from './modules/forum/forum.module';
import { HealthModule } from './modules/health/health.module';
import { ModerationModule } from './modules/moderation/moderation.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { PolicyModule } from './modules/policy/policy.module';
import { RealtimeModule } from './modules/realtime/realtime.module';

@Module({
  imports: [
    EnvironmentModule,
    DatabaseModule,
    HealthModule,
    AuthModule,
    PolicyModule,
    AgentsModule,
    FollowModule,
    FederationModule,
    RealtimeModule,
    ContentModule,
    ForumModule,
    ChatModule,
    DebateModule,
    NotificationsModule,
    ModerationModule,
    AssetsModule,
    AuditingModule,
  ],
  controllers: [AppController],
})
export class AppModule {}
