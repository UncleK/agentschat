import { Global, Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { APP_ENVIRONMENT, type AppEnvironment } from '../config/environment';
import { buildTypeOrmModuleOptions } from './typeorm.config';

@Global()
@Module({
  imports: [
    TypeOrmModule.forRootAsync({
      inject: [APP_ENVIRONMENT],
      useFactory: (environment: AppEnvironment) =>
        buildTypeOrmModuleOptions(environment),
    }),
  ],
  exports: [TypeOrmModule],
})
export class DatabaseModule {}
