import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { DataSource } from 'typeorm';
import { inTransaction } from '../../database/transaction-context';
import { NotificationsService } from './notifications.service';

@Injectable()
export class EventOutboxService implements OnModuleInit, OnModuleDestroy {
  private timer?: NodeJS.Timeout;
  private running?: Promise<void>;
  private stopped = false;
  constructor(
    private readonly database: DataSource,
    private readonly notifications: NotificationsService,
  ) {}
  onModuleInit(): void {
    this.timer = setInterval(
      () => this.poke(),
      process.env.NODE_ENV === 'test' ? 50 : 1000,
    );
    this.timer.unref();
    this.poke();
  }
  async onModuleDestroy(): Promise<void> {
    this.stopped = true;
    clearInterval(this.timer);
    await this.running;
  }
  poke(): void {
    if (this.stopped || this.running) return;
    this.running = this.sweep()
      .catch(() => undefined)
      .finally(() => {
        this.running = undefined;
      });
  }
  async sweep(): Promise<void> {
    const owner = randomUUID();
    const rows = await this.database.query<Array<{ event_id: string }>>(
      `WITH due AS (
      SELECT event_id FROM event_outbox WHERE completed_at IS NULL AND next_attempt_at <= now()
        AND (lease_expires_at IS NULL OR lease_expires_at <= now())
      ORDER BY created_at LIMIT 4 FOR UPDATE SKIP LOCKED
    ), claimed AS (UPDATE event_outbox o SET lease_owner=$1, lease_expires_at=now()+interval '30 seconds', attempts=attempts+1
      FROM due WHERE o.event_id=due.event_id RETURNING o.event_id) SELECT event_id FROM claimed`,
      [owner],
    );
    await Promise.all(
      rows.map(async (row) => {
        try {
          await inTransaction(this.database, async (manager) => {
            const held = await manager.query<Array<{ event_id: string }>>(
              'SELECT event_id FROM event_outbox WHERE event_id=$1 AND lease_owner=$2 AND completed_at IS NULL FOR UPDATE',
              [row.event_id, owner],
            );
            if (!held.length) return;
            await this.notifications.processEventById(row.event_id);
            await manager.query(
              'UPDATE event_outbox SET completed_at=now(), lease_owner=NULL, lease_expires_at=NULL, last_error=NULL WHERE event_id=$1 AND lease_owner=$2',
              [row.event_id, owner],
            );
          });
        } catch {
          await this.database.query(
            `UPDATE event_outbox SET lease_owner=NULL, lease_expires_at=NULL,
          next_attempt_at=now()+LEAST(attempts,60)*interval '1 second', last_error='fanout_failed'
          WHERE event_id=$1 AND lease_owner=$2`,
            [row.event_id, owner],
          );
        }
      }),
    );
  }
}
