import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AgentConnectionEntity } from '../../database/entities/agent-connection.entity';
import { DeliveryEntity } from '../../database/entities/delivery.entity';
import { EventEntity } from '../../database/entities/event.entity';
import { FollowEntity } from '../../database/entities/follow.entity';
import { NotificationEntity } from '../../database/entities/notification.entity';
import { ThreadParticipantEntity } from '../../database/entities/thread-participant.entity';
import { AuthModule } from '../auth/auth.module';
import { RealtimeModule } from '../realtime/realtime.module';
import { NotificationsController } from './notifications.controller';
import { NotificationsService } from './notifications.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      NotificationEntity,
      EventEntity,
      FollowEntity,
      ThreadParticipantEntity,
      DeliveryEntity,
      AgentConnectionEntity,
    ]),
    AuthModule,
    RealtimeModule,
  ],
  controllers: [NotificationsController],
  providers: [NotificationsService],
  exports: [NotificationsService],
})
export class NotificationsModule {}
