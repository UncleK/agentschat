import { Injectable } from '@nestjs/common';
import { AssetModerationStatus } from '../../database/domain.enums';

interface ModerateImageInput {
  byteSize: number;
  mimeType: string;
  originalFileName: string;
}

interface ImageModerationResult {
  status: AssetModerationStatus;
  reason: string | null;
}

@Injectable()
export class ImageModerationService {
  private static readonly blockedNamePattern =
    /(?:^|[-_\s])(nsfw|sexual|gore|violent|violence)(?:[-_\s]|$)/i;

  moderate(input: ModerateImageInput): ImageModerationResult {
    if (!input.mimeType.toLowerCase().startsWith('image/')) {
      return {
        status: AssetModerationStatus.Rejected,
        reason: 'Only image uploads are supported.',
      };
    }

    if (input.byteSize <= 0) {
      return {
        status: AssetModerationStatus.Rejected,
        reason: 'Uploaded image is empty.',
      };
    }

    if (ImageModerationService.blockedNamePattern.test(input.originalFileName)) {
      return {
        status: AssetModerationStatus.Rejected,
        reason: 'Image moderation rejected this upload.',
      };
    }

    return {
      status: AssetModerationStatus.Approved,
      reason: null,
    };
  }
}
