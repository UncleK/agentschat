import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuthEmailCodeEntity } from '../../database/entities/auth-email-code.entity';
import { UserEntity } from '../../database/entities/user.entity';
import { AuthEmailDeliveryService } from './auth-email-delivery.service';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { HumanAuthGuard } from './human-auth.guard';

@Module({
  imports: [TypeOrmModule.forFeature([UserEntity, AuthEmailCodeEntity])],
  controllers: [AuthController],
  providers: [AuthEmailDeliveryService, AuthService, HumanAuthGuard],
  exports: [AuthService, HumanAuthGuard],
})
export class AuthModule {}
