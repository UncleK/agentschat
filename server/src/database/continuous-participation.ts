import { createHash } from 'node:crypto';
import type { AgentConnectionEntity } from './entities/agent-connection.entity';

export interface ContinuousParticipation {
  id: string;
  mode: 'webhook' | 'host_schedule';
  phase: 'needs_host_setup' | 'awaiting_confirmation' | 'enabled' | 'paused';
  intentHash: string;
  configurationHash: string;
  configuredAt: string;
  expiresAt: string;
  intervalSeconds: number;
  scheduleId: string | null;
  probeId: string;
  probeNonce: string | null;
  probeNotBefore: string;
  probeExpiresAt: string;
  probeSentAt: string | null;
  verifiedAt: string | null;
  lastReturnAt: string | null;
  lastRunId: string | null;
  lastWakeAt: string | null;
  unacknowledgedWakeups: number;
  reason: string | null;
}

export function participationConfiguration(
  connection: Pick<
    AgentConnectionEntity,
    'id' | 'tokenHash' | 'transportMode' | 'webhookUrl' | 'webhookSecretHash'
  >,
) {
  return createHash('sha256')
    .update(
      JSON.stringify([
        connection.id,
        connection.tokenHash,
        connection.transportMode,
        connection.webhookUrl,
        connection.webhookSecretHash,
      ]),
    )
    .digest('hex');
}

export function participationSummary(
  connection: AgentConnectionEntity,
  now = new Date(),
) {
  const plan = connection.continuousParticipation;
  if (!plan)
    return {
      state: 'not_configured' as const,
      enabled: false,
      mode: null,
      nextAction: 'configure',
    };
  const state =
    Date.parse(plan.expiresAt) <= now.getTime()
      ? 'expired'
      : plan.configurationHash !== participationConfiguration(connection)
        ? 'needs_reverification'
        : plan.phase === 'awaiting_confirmation' &&
            Date.parse(plan.probeExpiresAt) <= now.getTime()
          ? 'verification_expired'
          : plan.phase;
  return {
    state,
    enabled: state === 'enabled',
    mode: plan.mode,
    planId: plan.id,
    expiresAt: plan.expiresAt,
    intervalSeconds: plan.intervalSeconds,
    hostScheduleReported: Boolean(plan.scheduleId),
    verifiedAt: plan.verifiedAt,
    lastReturnAt: plan.lastReturnAt,
    reason: plan.reason,
    verification:
      plan.mode === 'webhook'
        ? 'signed_callback_and_runtime_confirmation'
        : 'delayed_authenticated_return',
    nextAction:
      state === 'enabled'
        ? 'continue_within_authorization'
        : state === 'needs_host_setup'
          ? 'create_authorized_host_schedule'
          : state === 'awaiting_confirmation'
            ? 'confirm_from_return_run'
            : 'configure_or_pause',
  };
}
