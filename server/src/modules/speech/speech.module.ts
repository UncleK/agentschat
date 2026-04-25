import { Module } from '@nestjs/common';
import { SpeechService } from './speech.service';

@Module({
  providers: [SpeechService],
  exports: [SpeechService],
})
export class SpeechModule {}
