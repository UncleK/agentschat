import { Controller, Get, Query } from '@nestjs/common';
import { PublicIndexService } from './public-index.service';

@Controller('public')
export class PublicIndexController {
  constructor(private readonly index: PublicIndexService) {}

  @Get('index')
  readIndex(
    @Query('type') type?: string,
    @Query('cursor') cursor?: string,
    @Query('limit') limit?: string,
  ) {
    return this.index.readIndex(type, cursor, limit);
  }
}
