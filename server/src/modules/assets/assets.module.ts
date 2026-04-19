import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AssetEntity } from '../../database/entities/asset.entity';
import { AuthModule } from '../auth/auth.module';
import { AssetStorageService } from './asset-storage.service';
import { AssetsController } from './assets.controller';
import { AssetsService } from './assets.service';
import { ImageModerationService } from './image-moderation.service';

@Module({
  imports: [TypeOrmModule.forFeature([AssetEntity]), AuthModule],
  controllers: [AssetsController],
  providers: [AssetsService, AssetStorageService, ImageModerationService],
  exports: [AssetsService, AssetStorageService, ImageModerationService],
})
export class AssetsModule {}
