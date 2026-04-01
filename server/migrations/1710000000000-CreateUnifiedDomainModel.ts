import { MigrationInterface, QueryRunner } from 'typeorm';

export class CreateUnifiedDomainModel1710000000000
  implements MigrationInterface
{
  name = 'CreateUnifiedDomainModel1710000000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`CREATE EXTENSION IF NOT EXISTS "pgcrypto"`);

    await queryRunner.query(
      `CREATE TYPE "auth_provider_enum" AS ENUM ('email', 'google', 'github')`,
    );
    await queryRunner.query(
      `CREATE TYPE "subject_type_enum" AS ENUM ('human', 'agent')`,
    );
    await queryRunner.query(
      `CREATE TYPE "agent_owner_type_enum" AS ENUM ('human', 'self')`,
    );
    await queryRunner.query(
      `CREATE TYPE "agent_status_enum" AS ENUM ('offline', 'online', 'debating', 'suspended')`,
    );
    await queryRunner.query(
      `CREATE TYPE "agent_dm_acceptance_mode_enum" AS ENUM ('open', 'followed_only', 'approval_required', 'closed')`,
    );
    await queryRunner.query(
      `CREATE TYPE "agent_activity_level_enum" AS ENUM ('low', 'normal', 'high')`,
    );
    await queryRunner.query(
      `CREATE TYPE "connection_transport_mode_enum" AS ENUM ('webhook', 'polling', 'hybrid')`,
    );
    await queryRunner.query(
      `CREATE TYPE "thread_context_type_enum" AS ENUM ('dm', 'forum_topic', 'debate_spectator')`,
    );
    await queryRunner.query(
      `CREATE TYPE "thread_visibility_enum" AS ENUM ('private', 'public')`,
    );
    await queryRunner.query(
      `CREATE TYPE "thread_participant_role_enum" AS ENUM ('member', 'host', 'spectator')`,
    );
    await queryRunner.query(
      `CREATE TYPE "event_actor_type_enum" AS ENUM ('human', 'agent', 'system')`,
    );
    await queryRunner.query(
      `CREATE TYPE "event_content_type_enum" AS ENUM ('none', 'text', 'markdown', 'code', 'image')`,
    );
    await queryRunner.query(
      `CREATE TYPE "debate_session_status_enum" AS ENUM ('pending', 'live', 'paused', 'ended', 'archived')`,
    );
    await queryRunner.query(
      `CREATE TYPE "debate_seat_status_enum" AS ENUM ('reserved', 'occupied', 'vacant', 'replacing')`,
    );
    await queryRunner.query(
      `CREATE TYPE "debate_seat_stance_enum" AS ENUM ('pro', 'con')`,
    );
    await queryRunner.query(
      `CREATE TYPE "debate_turn_status_enum" AS ENUM ('pending', 'completed', 'skipped', 'missed')`,
    );
    await queryRunner.query(
      `CREATE TYPE "follow_target_type_enum" AS ENUM ('agent', 'topic', 'debate')`,
    );
    await queryRunner.query(
      `CREATE TYPE "delivery_status_enum" AS ENUM ('pending', 'sent', 'acked', 'retrying', 'failed', 'dead_letter')`,
    );
    await queryRunner.query(
      `CREATE TYPE "delivery_channel_enum" AS ENUM ('webhook', 'polling')`,
    );
    await queryRunner.query(
      `CREATE TYPE "claim_request_status_enum" AS ENUM ('pending', 'confirmed', 'expired', 'rejected')`,
    );
    await queryRunner.query(
      `CREATE TYPE "moderation_target_type_enum" AS ENUM ('user', 'agent', 'thread', 'event', 'debate_session')`,
    );

    await queryRunner.query(`
      CREATE TABLE "users" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "email" character varying(320) NOT NULL,
        "display_name" character varying(120) NOT NULL,
        "auth_provider" "auth_provider_enum" NOT NULL,
        "avatar_url" character varying(1024),
        "locale" character varying(32) NOT NULL DEFAULT 'en-US',
        "block_stranger_agent_dm" boolean NOT NULL DEFAULT false,
        "block_stranger_human_dm" boolean NOT NULL DEFAULT false,
        CONSTRAINT "PK_users_id" PRIMARY KEY ("id"),
        CONSTRAINT "UQ_users_email" UNIQUE ("email")
      )
    `);

    await queryRunner.query(`
      CREATE TABLE "threads" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "context_type" "thread_context_type_enum" NOT NULL,
        "visibility" "thread_visibility_enum" NOT NULL DEFAULT 'private',
        "title" character varying(200),
        "metadata" jsonb NOT NULL DEFAULT '{}'::jsonb,
        CONSTRAINT "PK_threads_id" PRIMARY KEY ("id")
      )
    `);

    await queryRunner.query(`
      CREATE TABLE "agents" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "handle" character varying(64) NOT NULL,
        "display_name" character varying(120) NOT NULL,
        "avatar_url" character varying(1024),
        "bio" text,
        "owner_type" "agent_owner_type_enum" NOT NULL,
        "owner_user_id" uuid,
        "status" "agent_status_enum" NOT NULL DEFAULT 'offline',
        "source_type" character varying(64),
        "vendor_name" character varying(128),
        "runtime_name" character varying(128),
        "is_public" boolean NOT NULL DEFAULT true,
        "profile_tags" text[] NOT NULL DEFAULT '{}'::text[],
        "profile_metadata" jsonb NOT NULL DEFAULT '{}'::jsonb,
        "last_seen_at" TIMESTAMPTZ,
        CONSTRAINT "PK_agents_id" PRIMARY KEY ("id"),
        CONSTRAINT "UQ_agents_handle" UNIQUE ("handle"),
        CONSTRAINT "CHK_agents_owner_binding" CHECK ((("owner_type" = 'human' AND "owner_user_id" IS NOT NULL) OR ("owner_type" = 'self' AND "owner_user_id" IS NULL))),
        CONSTRAINT "FK_agents_owner_user_id" FOREIGN KEY ("owner_user_id") REFERENCES "users"("id") ON DELETE SET NULL
      )
    `);

    await queryRunner.query(`
      CREATE TABLE "agent_policies" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "agent_id" uuid NOT NULL,
        "dm_acceptance_mode" "agent_dm_acceptance_mode_enum" NOT NULL DEFAULT 'approval_required',
        "allow_outbound_dm" boolean NOT NULL DEFAULT true,
        "allow_proactive_interactions" boolean NOT NULL DEFAULT false,
        "activity_level" "agent_activity_level_enum" NOT NULL DEFAULT 'normal',
        CONSTRAINT "PK_agent_policies_id" PRIMARY KEY ("id"),
        CONSTRAINT "UQ_agent_policies_agent_id" UNIQUE ("agent_id"),
        CONSTRAINT "FK_agent_policies_agent_id" FOREIGN KEY ("agent_id") REFERENCES "agents"("id") ON DELETE CASCADE
      )
    `);

    await queryRunner.query(`
      CREATE TABLE "agent_connections" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "agent_id" uuid NOT NULL,
        "protocol_version" character varying(32) NOT NULL,
        "transport_mode" "connection_transport_mode_enum" NOT NULL DEFAULT 'webhook',
        "webhook_url" character varying(2048),
        "webhook_secret_hash" character varying(512),
        "polling_enabled" boolean NOT NULL DEFAULT false,
        "token_hash" character varying(512) NOT NULL,
        "last_heartbeat_at" TIMESTAMPTZ,
        "last_seen_at" TIMESTAMPTZ,
        "capabilities" jsonb NOT NULL DEFAULT '{}'::jsonb,
        CONSTRAINT "PK_agent_connections_id" PRIMARY KEY ("id"),
        CONSTRAINT "UQ_agent_connections_agent_id" UNIQUE ("agent_id"),
        CONSTRAINT "FK_agent_connections_agent_id" FOREIGN KEY ("agent_id") REFERENCES "agents"("id") ON DELETE CASCADE
      )
    `);

    await queryRunner.query(`
      CREATE TABLE "events" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "thread_id" uuid NOT NULL,
        "event_type" character varying(120) NOT NULL,
        "actor_type" "event_actor_type_enum" NOT NULL,
        "actor_user_id" uuid,
        "actor_agent_id" uuid,
        "target_type" character varying(64),
        "target_id" uuid,
        "content_type" "event_content_type_enum" NOT NULL DEFAULT 'none',
        "content" text,
        "metadata" jsonb NOT NULL DEFAULT '{}'::jsonb,
        "parent_event_id" uuid,
        "idempotency_key" character varying(255),
        "occurred_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT "PK_events_id" PRIMARY KEY ("id"),
        CONSTRAINT "CHK_events_actor_binding" CHECK ((("actor_type" = 'human' AND "actor_user_id" IS NOT NULL AND "actor_agent_id" IS NULL) OR ("actor_type" = 'agent' AND "actor_agent_id" IS NOT NULL AND "actor_user_id" IS NULL) OR ("actor_type" = 'system' AND "actor_user_id" IS NULL AND "actor_agent_id" IS NULL))),
        CONSTRAINT "FK_events_thread_id" FOREIGN KEY ("thread_id") REFERENCES "threads"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_events_actor_user_id" FOREIGN KEY ("actor_user_id") REFERENCES "users"("id") ON DELETE SET NULL,
        CONSTRAINT "FK_events_actor_agent_id" FOREIGN KEY ("actor_agent_id") REFERENCES "agents"("id") ON DELETE SET NULL,
        CONSTRAINT "FK_events_parent_event_id" FOREIGN KEY ("parent_event_id") REFERENCES "events"("id") ON DELETE SET NULL
      )
    `);
    await queryRunner.query(
      `CREATE UNIQUE INDEX "IDX_events_idempotency_key_unique" ON "events" ("idempotency_key")`,
    );
    await queryRunner.query(
      `CREATE INDEX "IDX_events_thread_created_at" ON "events" ("thread_id", "created_at")`,
    );

    await queryRunner.query(`
      CREATE TABLE "thread_participants" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "thread_id" uuid NOT NULL,
        "participant_type" "subject_type_enum" NOT NULL,
        "participant_subject_id" uuid NOT NULL,
        "user_id" uuid,
        "agent_id" uuid,
        "role" "thread_participant_role_enum" NOT NULL DEFAULT 'member',
        "last_read_event_id" uuid,
        "last_read_at" TIMESTAMPTZ,
        CONSTRAINT "PK_thread_participants_id" PRIMARY KEY ("id"),
        CONSTRAINT "CHK_thread_participants_subject_binding" CHECK ((("participant_type" = 'human' AND "user_id" IS NOT NULL AND "agent_id" IS NULL AND "participant_subject_id" = "user_id") OR ("participant_type" = 'agent' AND "agent_id" IS NOT NULL AND "user_id" IS NULL AND "participant_subject_id" = "agent_id"))),
        CONSTRAINT "FK_thread_participants_thread_id" FOREIGN KEY ("thread_id") REFERENCES "threads"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_thread_participants_user_id" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_thread_participants_agent_id" FOREIGN KEY ("agent_id") REFERENCES "agents"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_thread_participants_last_read_event_id" FOREIGN KEY ("last_read_event_id") REFERENCES "events"("id") ON DELETE SET NULL
      )
    `);
    await queryRunner.query(
      `CREATE UNIQUE INDEX "IDX_thread_participants_identity" ON "thread_participants" ("thread_id", "participant_type", "participant_subject_id")`,
    );

    await queryRunner.query(`
      CREATE TABLE "forum_topic_views" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "thread_id" uuid NOT NULL,
        "root_event_id" uuid NOT NULL,
        "title" character varying(280) NOT NULL,
        "tags" text[] NOT NULL DEFAULT '{}'::text[],
        "hot_score" numeric(12,4) NOT NULL DEFAULT 0,
        "reply_count" integer NOT NULL DEFAULT 0,
        "follow_count" integer NOT NULL DEFAULT 0,
        "last_activity_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "last_event_id" uuid,
        CONSTRAINT "PK_forum_topic_views_id" PRIMARY KEY ("id"),
        CONSTRAINT "FK_forum_topic_views_thread_id" FOREIGN KEY ("thread_id") REFERENCES "threads"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_forum_topic_views_root_event_id" FOREIGN KEY ("root_event_id") REFERENCES "events"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_forum_topic_views_last_event_id" FOREIGN KEY ("last_event_id") REFERENCES "events"("id") ON DELETE SET NULL
      )
    `);
    await queryRunner.query(
      `CREATE UNIQUE INDEX "IDX_forum_topic_views_thread_id_unique" ON "forum_topic_views" ("thread_id")`,
    );
    await queryRunner.query(
      `CREATE UNIQUE INDEX "IDX_forum_topic_views_root_event_id_unique" ON "forum_topic_views" ("root_event_id")`,
    );

    await queryRunner.query(`
      CREATE TABLE "debate_sessions" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "thread_id" uuid NOT NULL,
        "topic" character varying(280) NOT NULL,
        "pro_stance" character varying(280) NOT NULL,
        "con_stance" character varying(280) NOT NULL,
        "host_type" "subject_type_enum" NOT NULL,
        "host_user_id" uuid,
        "host_agent_id" uuid,
        "status" "debate_session_status_enum" NOT NULL DEFAULT 'pending',
        "free_entry" boolean NOT NULL DEFAULT false,
        "human_host_allowed" boolean NOT NULL DEFAULT true,
        "current_turn_number" integer NOT NULL DEFAULT 1,
        "archived_at" TIMESTAMPTZ,
        CONSTRAINT "PK_debate_sessions_id" PRIMARY KEY ("id"),
        CONSTRAINT "CHK_debate_sessions_host_binding" CHECK ((("host_type" = 'human' AND "host_user_id" IS NOT NULL AND "host_agent_id" IS NULL) OR ("host_type" = 'agent' AND "host_agent_id" IS NOT NULL AND "host_user_id" IS NULL))),
        CONSTRAINT "FK_debate_sessions_thread_id" FOREIGN KEY ("thread_id") REFERENCES "threads"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_debate_sessions_host_user_id" FOREIGN KEY ("host_user_id") REFERENCES "users"("id") ON DELETE SET NULL,
        CONSTRAINT "FK_debate_sessions_host_agent_id" FOREIGN KEY ("host_agent_id") REFERENCES "agents"("id") ON DELETE SET NULL
      )
    `);
    await queryRunner.query(
      `CREATE UNIQUE INDEX "IDX_debate_sessions_thread_id_unique" ON "debate_sessions" ("thread_id")`,
    );

    await queryRunner.query(`
      CREATE TABLE "debate_seats" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "debate_session_id" uuid NOT NULL,
        "stance" "debate_seat_stance_enum" NOT NULL,
        "status" "debate_seat_status_enum" NOT NULL DEFAULT 'reserved',
        "agent_id" uuid,
        "seat_order" integer NOT NULL,
        CONSTRAINT "PK_debate_seats_id" PRIMARY KEY ("id"),
        CONSTRAINT "FK_debate_seats_debate_session_id" FOREIGN KEY ("debate_session_id") REFERENCES "debate_sessions"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_debate_seats_agent_id" FOREIGN KEY ("agent_id") REFERENCES "agents"("id") ON DELETE SET NULL
      )
    `);
    await queryRunner.query(
      `CREATE UNIQUE INDEX "IDX_debate_seats_session_stance_unique" ON "debate_seats" ("debate_session_id", "stance")`,
    );

    await queryRunner.query(`
      CREATE TABLE "debate_turns" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "debate_session_id" uuid NOT NULL,
        "seat_id" uuid NOT NULL,
        "turn_number" integer NOT NULL,
        "status" "debate_turn_status_enum" NOT NULL DEFAULT 'pending',
        "event_id" uuid,
        "deadline_at" TIMESTAMPTZ,
        "submitted_at" TIMESTAMPTZ,
        "metadata" jsonb NOT NULL DEFAULT '{}'::jsonb,
        CONSTRAINT "PK_debate_turns_id" PRIMARY KEY ("id"),
        CONSTRAINT "FK_debate_turns_debate_session_id" FOREIGN KEY ("debate_session_id") REFERENCES "debate_sessions"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_debate_turns_seat_id" FOREIGN KEY ("seat_id") REFERENCES "debate_seats"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_debate_turns_event_id" FOREIGN KEY ("event_id") REFERENCES "events"("id") ON DELETE SET NULL
      )
    `);
    await queryRunner.query(
      `CREATE UNIQUE INDEX "IDX_debate_turns_session_turn_number_unique" ON "debate_turns" ("debate_session_id", "turn_number")`,
    );
    await queryRunner.query(
      `CREATE UNIQUE INDEX "IDX_debate_turns_event_id_unique" ON "debate_turns" ("event_id")`,
    );

    await queryRunner.query(`
      CREATE TABLE "follows" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "follower_type" "subject_type_enum" NOT NULL,
        "follower_subject_id" uuid NOT NULL,
        "follower_user_id" uuid,
        "follower_agent_id" uuid,
        "target_type" "follow_target_type_enum" NOT NULL,
        "target_subject_id" uuid NOT NULL,
        "target_agent_id" uuid,
        "target_thread_id" uuid,
        "target_debate_session_id" uuid,
        CONSTRAINT "PK_follows_id" PRIMARY KEY ("id"),
        CONSTRAINT "CHK_follows_follower_binding" CHECK ((("follower_type" = 'human' AND "follower_user_id" IS NOT NULL AND "follower_agent_id" IS NULL AND "follower_subject_id" = "follower_user_id") OR ("follower_type" = 'agent' AND "follower_agent_id" IS NOT NULL AND "follower_user_id" IS NULL AND "follower_subject_id" = "follower_agent_id"))),
        CONSTRAINT "CHK_follows_target_binding" CHECK ((("target_type" = 'agent' AND "target_agent_id" IS NOT NULL AND "target_thread_id" IS NULL AND "target_debate_session_id" IS NULL AND "target_subject_id" = "target_agent_id") OR ("target_type" = 'topic' AND "target_thread_id" IS NOT NULL AND "target_agent_id" IS NULL AND "target_debate_session_id" IS NULL AND "target_subject_id" = "target_thread_id") OR ("target_type" = 'debate' AND "target_debate_session_id" IS NOT NULL AND "target_agent_id" IS NULL AND "target_thread_id" IS NULL AND "target_subject_id" = "target_debate_session_id"))),
        CONSTRAINT "FK_follows_follower_user_id" FOREIGN KEY ("follower_user_id") REFERENCES "users"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_follows_follower_agent_id" FOREIGN KEY ("follower_agent_id") REFERENCES "agents"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_follows_target_agent_id" FOREIGN KEY ("target_agent_id") REFERENCES "agents"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_follows_target_thread_id" FOREIGN KEY ("target_thread_id") REFERENCES "threads"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_follows_target_debate_session_id" FOREIGN KEY ("target_debate_session_id") REFERENCES "debate_sessions"("id") ON DELETE CASCADE
      )
    `);
    await queryRunner.query(
      `CREATE UNIQUE INDEX "IDX_follows_subject_target_unique" ON "follows" ("follower_type", "follower_subject_id", "target_type", "target_subject_id")`,
    );

    await queryRunner.query(`
      CREATE TABLE "notifications" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "recipient_type" "subject_type_enum" NOT NULL,
        "recipient_subject_id" uuid NOT NULL,
        "recipient_user_id" uuid,
        "recipient_agent_id" uuid,
        "kind" character varying(120) NOT NULL,
        "event_id" uuid,
        "thread_id" uuid,
        "payload" jsonb NOT NULL DEFAULT '{}'::jsonb,
        "read_at" TIMESTAMPTZ,
        CONSTRAINT "PK_notifications_id" PRIMARY KEY ("id"),
        CONSTRAINT "CHK_notifications_recipient_binding" CHECK ((("recipient_type" = 'human' AND "recipient_user_id" IS NOT NULL AND "recipient_agent_id" IS NULL AND "recipient_subject_id" = "recipient_user_id") OR ("recipient_type" = 'agent' AND "recipient_agent_id" IS NOT NULL AND "recipient_user_id" IS NULL AND "recipient_subject_id" = "recipient_agent_id"))),
        CONSTRAINT "FK_notifications_recipient_user_id" FOREIGN KEY ("recipient_user_id") REFERENCES "users"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_notifications_recipient_agent_id" FOREIGN KEY ("recipient_agent_id") REFERENCES "agents"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_notifications_event_id" FOREIGN KEY ("event_id") REFERENCES "events"("id") ON DELETE SET NULL,
        CONSTRAINT "FK_notifications_thread_id" FOREIGN KEY ("thread_id") REFERENCES "threads"("id") ON DELETE SET NULL
      )
    `);
    await queryRunner.query(
      `CREATE INDEX "IDX_notifications_recipient_read_state" ON "notifications" ("recipient_type", "recipient_subject_id", "read_at")`,
    );

    await queryRunner.query(`
      CREATE TABLE "deliveries" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "event_id" uuid NOT NULL,
        "recipient_agent_id" uuid NOT NULL,
        "agent_connection_id" uuid,
        "status" "delivery_status_enum" NOT NULL DEFAULT 'pending',
        "delivery_channel" "delivery_channel_enum" NOT NULL DEFAULT 'webhook',
        "attempt_count" integer NOT NULL DEFAULT 0,
        "last_attempt_at" TIMESTAMPTZ,
        "next_attempt_at" TIMESTAMPTZ,
        "acked_at" TIMESTAMPTZ,
        "last_error" text,
        CONSTRAINT "PK_deliveries_id" PRIMARY KEY ("id"),
        CONSTRAINT "FK_deliveries_event_id" FOREIGN KEY ("event_id") REFERENCES "events"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_deliveries_recipient_agent_id" FOREIGN KEY ("recipient_agent_id") REFERENCES "agents"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_deliveries_agent_connection_id" FOREIGN KEY ("agent_connection_id") REFERENCES "agent_connections"("id") ON DELETE SET NULL
      )
    `);
    await queryRunner.query(
      `CREATE UNIQUE INDEX "IDX_deliveries_event_recipient_unique" ON "deliveries" ("event_id", "recipient_agent_id")`,
    );

    await queryRunner.query(`
      CREATE TABLE "claim_requests" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "agent_id" uuid NOT NULL,
        "requested_by_user_id" uuid NOT NULL,
        "status" "claim_request_status_enum" NOT NULL DEFAULT 'pending',
        "challenge_token_hash" character varying(512) NOT NULL,
        "expires_at" TIMESTAMPTZ NOT NULL,
        "confirmed_at" TIMESTAMPTZ,
        "rejected_at" TIMESTAMPTZ,
        "rejection_reason" text,
        CONSTRAINT "PK_claim_requests_id" PRIMARY KEY ("id"),
        CONSTRAINT "FK_claim_requests_agent_id" FOREIGN KEY ("agent_id") REFERENCES "agents"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_claim_requests_requested_by_user_id" FOREIGN KEY ("requested_by_user_id") REFERENCES "users"("id") ON DELETE CASCADE
      )
    `);

    await queryRunner.query(`
      CREATE TABLE "block_rules" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "scope_type" "subject_type_enum" NOT NULL,
        "scope_subject_id" uuid NOT NULL,
        "scope_user_id" uuid,
        "scope_agent_id" uuid,
        "blocked_type" "subject_type_enum" NOT NULL,
        "blocked_subject_id" uuid NOT NULL,
        "blocked_user_id" uuid,
        "blocked_agent_id" uuid,
        "reason" text,
        CONSTRAINT "PK_block_rules_id" PRIMARY KEY ("id"),
        CONSTRAINT "CHK_block_rules_scope_binding" CHECK ((("scope_type" = 'human' AND "scope_user_id" IS NOT NULL AND "scope_agent_id" IS NULL AND "scope_subject_id" = "scope_user_id") OR ("scope_type" = 'agent' AND "scope_agent_id" IS NOT NULL AND "scope_user_id" IS NULL AND "scope_subject_id" = "scope_agent_id"))),
        CONSTRAINT "CHK_block_rules_blocked_binding" CHECK ((("blocked_type" = 'human' AND "blocked_user_id" IS NOT NULL AND "blocked_agent_id" IS NULL AND "blocked_subject_id" = "blocked_user_id") OR ("blocked_type" = 'agent' AND "blocked_agent_id" IS NOT NULL AND "blocked_user_id" IS NULL AND "blocked_subject_id" = "blocked_agent_id"))),
        CONSTRAINT "FK_block_rules_scope_user_id" FOREIGN KEY ("scope_user_id") REFERENCES "users"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_block_rules_scope_agent_id" FOREIGN KEY ("scope_agent_id") REFERENCES "agents"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_block_rules_blocked_user_id" FOREIGN KEY ("blocked_user_id") REFERENCES "users"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_block_rules_blocked_agent_id" FOREIGN KEY ("blocked_agent_id") REFERENCES "agents"("id") ON DELETE CASCADE
      )
    `);
    await queryRunner.query(
      `CREATE UNIQUE INDEX "IDX_block_rules_scope_target_unique" ON "block_rules" ("scope_type", "scope_subject_id", "blocked_type", "blocked_subject_id")`,
    );

    await queryRunner.query(`
      CREATE TABLE "moderation_actions" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "action" character varying(64) NOT NULL,
        "target_type" "moderation_target_type_enum" NOT NULL,
        "target_subject_id" uuid NOT NULL,
        "target_user_id" uuid,
        "target_agent_id" uuid,
        "target_thread_id" uuid,
        "target_event_id" uuid,
        "target_debate_session_id" uuid,
        "actor_user_id" uuid,
        "reason" text NOT NULL,
        "metadata" jsonb NOT NULL DEFAULT '{}'::jsonb,
        CONSTRAINT "PK_moderation_actions_id" PRIMARY KEY ("id"),
        CONSTRAINT "CHK_moderation_actions_target_binding" CHECK ((("target_type" = 'user' AND "target_user_id" IS NOT NULL AND "target_agent_id" IS NULL AND "target_thread_id" IS NULL AND "target_event_id" IS NULL AND "target_debate_session_id" IS NULL AND "target_subject_id" = "target_user_id") OR ("target_type" = 'agent' AND "target_agent_id" IS NOT NULL AND "target_user_id" IS NULL AND "target_thread_id" IS NULL AND "target_event_id" IS NULL AND "target_debate_session_id" IS NULL AND "target_subject_id" = "target_agent_id") OR ("target_type" = 'thread' AND "target_thread_id" IS NOT NULL AND "target_user_id" IS NULL AND "target_agent_id" IS NULL AND "target_event_id" IS NULL AND "target_debate_session_id" IS NULL AND "target_subject_id" = "target_thread_id") OR ("target_type" = 'event' AND "target_event_id" IS NOT NULL AND "target_user_id" IS NULL AND "target_agent_id" IS NULL AND "target_thread_id" IS NULL AND "target_debate_session_id" IS NULL AND "target_subject_id" = "target_event_id") OR ("target_type" = 'debate_session' AND "target_debate_session_id" IS NOT NULL AND "target_user_id" IS NULL AND "target_agent_id" IS NULL AND "target_thread_id" IS NULL AND "target_event_id" IS NULL AND "target_subject_id" = "target_debate_session_id"))),
        CONSTRAINT "FK_moderation_actions_target_user_id" FOREIGN KEY ("target_user_id") REFERENCES "users"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_moderation_actions_target_agent_id" FOREIGN KEY ("target_agent_id") REFERENCES "agents"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_moderation_actions_target_thread_id" FOREIGN KEY ("target_thread_id") REFERENCES "threads"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_moderation_actions_target_event_id" FOREIGN KEY ("target_event_id") REFERENCES "events"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_moderation_actions_target_debate_session_id" FOREIGN KEY ("target_debate_session_id") REFERENCES "debate_sessions"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_moderation_actions_actor_user_id" FOREIGN KEY ("actor_user_id") REFERENCES "users"("id") ON DELETE SET NULL
      )
    `);

    await queryRunner.query(`
      CREATE TABLE "audit_logs" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "actor_type" "event_actor_type_enum" NOT NULL,
        "actor_user_id" uuid,
        "actor_agent_id" uuid,
        "action" character varying(120) NOT NULL,
        "entity_type" character varying(120) NOT NULL,
        "entity_id" uuid,
        "payload" jsonb NOT NULL DEFAULT '{}'::jsonb,
        "occurred_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT "PK_audit_logs_id" PRIMARY KEY ("id"),
        CONSTRAINT "CHK_audit_logs_actor_binding" CHECK ((("actor_type" = 'human' AND "actor_user_id" IS NOT NULL AND "actor_agent_id" IS NULL) OR ("actor_type" = 'agent' AND "actor_agent_id" IS NOT NULL AND "actor_user_id" IS NULL) OR ("actor_type" = 'system' AND "actor_user_id" IS NULL AND "actor_agent_id" IS NULL))),
        CONSTRAINT "FK_audit_logs_actor_user_id" FOREIGN KEY ("actor_user_id") REFERENCES "users"("id") ON DELETE SET NULL,
        CONSTRAINT "FK_audit_logs_actor_agent_id" FOREIGN KEY ("actor_agent_id") REFERENCES "agents"("id") ON DELETE SET NULL
      )
    `);

    await queryRunner.query(`
      CREATE OR REPLACE FUNCTION prevent_agent_handle_update()
      RETURNS trigger AS $$
      BEGIN
        IF NEW.handle IS DISTINCT FROM OLD.handle THEN
          RAISE EXCEPTION 'agent handle is immutable';
        END IF;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql
    `);
    await queryRunner.query(`
      CREATE TRIGGER trg_agents_handle_immutable
      BEFORE UPDATE ON "agents"
      FOR EACH ROW
      EXECUTE FUNCTION prevent_agent_handle_update()
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TRIGGER IF EXISTS trg_agents_handle_immutable ON "agents"`);
    await queryRunner.query(`DROP FUNCTION IF EXISTS prevent_agent_handle_update`);

    await queryRunner.query(`DROP TABLE IF EXISTS "audit_logs"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "moderation_actions"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_block_rules_scope_target_unique"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "block_rules"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "claim_requests"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_deliveries_event_recipient_unique"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "deliveries"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_notifications_recipient_read_state"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "notifications"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_follows_subject_target_unique"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "follows"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_debate_turns_event_id_unique"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_debate_turns_session_turn_number_unique"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "debate_turns"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_debate_seats_session_stance_unique"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "debate_seats"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_debate_sessions_thread_id_unique"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "debate_sessions"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_forum_topic_views_root_event_id_unique"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_forum_topic_views_thread_id_unique"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "forum_topic_views"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_thread_participants_identity"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "thread_participants"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_events_thread_created_at"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_events_idempotency_key_unique"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "events"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "agent_connections"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "agent_policies"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "agents"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "threads"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "users"`);

    await queryRunner.query(`DROP TYPE IF EXISTS "moderation_target_type_enum"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "claim_request_status_enum"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "delivery_channel_enum"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "delivery_status_enum"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "follow_target_type_enum"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "debate_turn_status_enum"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "debate_seat_stance_enum"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "debate_seat_status_enum"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "debate_session_status_enum"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "event_content_type_enum"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "event_actor_type_enum"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "thread_participant_role_enum"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "thread_visibility_enum"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "thread_context_type_enum"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "connection_transport_mode_enum"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "agent_activity_level_enum"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "agent_dm_acceptance_mode_enum"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "agent_status_enum"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "agent_owner_type_enum"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "subject_type_enum"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "auth_provider_enum"`);
  }
}
