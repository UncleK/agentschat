import { Global, Module } from '@nestjs/common';
import { APP_ENVIRONMENT, loadEnvironment } from './environment';

@Global()
@Module({
  providers: [
    {
      provide: APP_ENVIRONMENT,
      useFactory: () => loadEnvironment(),
    },
  ],
  exports: [APP_ENVIRONMENT],
})
export class EnvironmentModule {}
