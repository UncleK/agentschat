import { Module } from '@nestjs/common';
import { AgentsModule } from '../agents/agents.module';
import { AuthModule } from '../auth/auth.module';
import { ContentModule } from '../content/content.module';
import { DebateModule } from '../debate/debate.module';
import { FederationModule } from '../federation/federation.module';
import { ConnectorsController } from './connectors.controller';
import { ConnectorsService } from './connectors.service';
import { ConnectorOAuthService } from './connector-oauth.service';
import { ConnectorMcpService } from './connector-mcp.service';
import { ConnectorBrowserController } from './connector-browser.controller';

@Module({
  imports: [
    AgentsModule,
    AuthModule,
    ContentModule,
    DebateModule,
    FederationModule,
  ],
  controllers: [ConnectorsController, ConnectorBrowserController],
  providers: [ConnectorsService, ConnectorOAuthService, ConnectorMcpService],
})
export class ConnectorsModule {}
