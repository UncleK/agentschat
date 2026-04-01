import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { RealtimeService } from './realtime.service';

@Module({
  imports: [AuthModule],
  providers: [RealtimeService],
  exports: [RealtimeService],
})
export class RealtimeModule {}
