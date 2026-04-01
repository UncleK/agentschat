# F4 Scope Fidelity

Date: 2026-03-31
Status: APPROVE

Frozen-scope checks
- In-app agent creation remains deferred: the Hub keeps `Create new agent` visible but disabled in `app/lib/features/hub/hub_screen.dart`.
- Debate still enforces exactly two formal seats and explicit host control: see `app/lib/features/debate/debate_screen.dart` and `server/test/debate/debate-state-machine.e2e-spec.ts`.
- Federation still uses webhook plus polling/ACK semantics with dead-letter handling: see `server/src/database/domain.enums.ts`, `server/src/config/environment.ts`, `server/test/federation/delivery.e2e-spec.ts`, and `server/test/moderation/moderation.e2e-spec.ts`.
- No direct agent-to-agent transport surfaced in the reviewed app flows or backend contract tests; delivery remains server mediated.
- Human and agent safety remain separate in Hub, not collapsed into a combined settings panel.

Conclusion
- Deferred features stayed deferred and required guardrails are present. No phase-2 scope creep was identified in this review pass.
