# Agents Chat Phase 1 Open Federation Platform

## TL;DR
> **Summary**: Build a Flutter mobile app and NestJS/PostgreSQL/Redis backend for Agents Chat phase 1 with open agent federation, unified event-driven content modeling, server-relayed interactions, and full UI coverage for Hall, Forum, Chat, Live Debate, and My Hub.
> **Deliverables**:
> - Flutter app implementing the Stitch-derived five-tab mobile experience
> - NestJS modular-monolith backend with unified Thread/Event model
> - Federation v1 contract using claim onboarding, unified `/actions`, webhook + polling fallback, batch ACKs, HMAC webhook auth, replay, idempotency, and image asset upload
> - Follow/notification/archive/moderation/audit foundations
> - Automated tests, conformance tests, and end-to-end verification for key product flows
> **Effort**: XL
> **Parallel**: YES - 2 waves
> **Critical Path**: 1 → 3 → 4 → 5 → 6 → 10/11/12 → F1-F4

## Context
### Original Request
- Build Agents Chat as a mobile app for iOS and Android where agents are the main actors, humans lightly participate, and open federation exists in phase 1.
- Use the Stitch project and local export folder `stitch_agents_chat/` as the UI source of truth.
- Design backend, server architecture, and open connection model.

### Interview Summary
- Federation phase 1 must be open: automatic onboarding, public visibility, HTTP + webhook with polling fallback, unified `/actions`, explicit ACKs, finite replay window, long-lived rotatable agent tokens.
- Every interaction is server-relayed; agents do not communicate directly.
- Ownership model must support both `human-owned` and `self-owned` agents; claim flow allows later human ownership without permitting human impersonation of agent-authored content.
- DM threads are private multi-participant threads keyed by remote agent identity; humans have explicit HUMAN identity badges and cannot masquerade as agents.
- Forum topics are agent-authored; human topic creation happens as a proposal to the human's own agent. Human users cannot reply directly to topic roots, but agents can.
- Live Debate is a strict two-agent, host-controlled state machine with lobby, live, paused, ended, archived states and spectator feed separated from formal debate turns.
- My Hub foregrounds owned-agent management, human auth, import/claim, and separate human-vs-agent safety policies.

### Metis Review (gaps addressed)
- Freeze phase-1 scope around one mobile app, one backend, one unified event model, and one federation contract; do not add team debates, in-app agent creation, or general agent orchestration.
- Make transport split explicit: WebSocket for app realtime, HTTP + webhook + polling fallback for external federation.
- Add federation conformance tests as a required deliverable, not optional polish.
- Include moderation, audit, operator-facing control surfaces, and dead-letter handling from the start because federation is fully open in phase 1.

## Work Objectives
### Core Objective
Deliver a production-shaped phase-1 implementation plan for an open-federation agent social network that matches the approved Stitch mobile UX and preserves the user's hard decisions on ownership, messaging, debates, notifications, and federation transport.

### Deliverables
- Flutter app scaffold with design system, app shell, and five core tabs
- Backend scaffold with modules for auth, agents, federation, content/events, forum, chat, debate, notifications, moderation, assets, and auditing
- Database schema and migrations for the unified entity model
- Federation v1 API and delivery pipeline
- Human auth, self-owned agent onboarding, human-owned import flow, and claim flow
- Debate archive/replay foundation
- Test suites for domain logic, federation conformance, and UI flows

### Definition of Done (verifiable conditions with commands)
- `flutter test` passes for app unit/widget tests
- `flutter test integration_test` passes for end-to-end mobile flows
- `pnpm --dir server test` passes for backend unit/integration tests
- `pnpm --dir server test -- --runInBand test/federation` passes for federation contract/conformance tests
- `docker compose -f server/docker-compose.yml up -d postgres redis minio` starts local infra successfully
- `pnpm --dir server start:dev` boots backend without schema/runtime errors
- `flutter run -d chrome` or configured simulator target launches the app shell with all five tabs wired to backend contracts or seeded fixtures

### Must Have
- Open federation in phase 1 with self-owned and human-owned agents
- Server-relayed messaging only
- Unified Thread/Event content model
- Explicit ACK/idempotency/replay semantics
- Human and agent safety controls separated in My Hub
- Debate archive and notification center foundations
- Image support via asset upload + moderation gate

### Must NOT Have
- No direct agent-to-agent transport outside the server relay
- No in-app new-agent creation beyond disabled placeholder UI
- No team or multi-agent debates beyond two debating seats
- No human impersonation of agent content
- No hidden risk assumptions about unknown agents; all moderation, dead-letter, and rate-limit paths must be implemented
- No separate, duplicated data models for DM, forum, and debate message content

## Verification Strategy
> ZERO HUMAN INTERVENTION — all verification is agent-executed.
- Test decision: tests-after with backend unit/integration tests, federation contract tests, Flutter widget tests, Flutter integration tests, and golden/screenshot checks for critical screens.
- QA policy: Every task includes backend verification plus UI/integration or transport-level scenarios as applicable.
- Evidence: `.sisyphus/evidence/task-{N}-{slug}.{ext}`

## Execution Strategy
### Parallel Execution Waves
> Target: 5-8 tasks per wave. <3 per wave (except final) = under-splitting.
> Extract shared dependencies as Wave-1 tasks for max parallelism.

Wave 1: bootstrap, schema, ownership/auth, federation transport, content/assets, design system/app shell
Wave 2: notifications/moderation, Agents Hall, Forum, Chat, Live Debate, My Hub

### Dependency Matrix (full, all tasks)
- 1 blocks 2-12
- 2 blocks 8-12
- 3 blocks 4-12
- 4 blocks 5,7-12
- 5 blocks 7-12
- 6 blocks 8-12
- 7 blocks 8-12
- 8 independent of 9-12 after 1-7
- 9 depends on 1,2,3,4,5,6,7
- 10 depends on 1,2,3,4,5,6,7
- 11 depends on 1,2,3,4,5,6,7
- 12 depends on 1,2,3,4,5,6,7
- F1-F4 depend on 1-12

### Agent Dispatch Summary (wave → task count → categories)
- Wave 1 → 6 tasks → unspecified-high, deep, visual-engineering
- Wave 2 → 6 tasks → unspecified-high, visual-engineering, deep
- Final Verification Wave → 4 tasks → oracle, unspecified-high, deep

## TODOs
> Implementation + Test = ONE task. Never separate.
> EVERY task MUST have: Agent Profile + Parallelization + QA Scenarios.

- [x] 1. Bootstrap workspace, tooling, and local infrastructure

  **What to do**: Create the repo layout from `项目规格说明书.md:297-328` using `app/` for Flutter and `server/` for NestJS. Add Docker Compose for PostgreSQL + Redis + local S3-compatible object storage (MinIO), environment examples, package scripts, Flutter flavors/config, base linting/formatting, and a health-check path. Commit to `Flutter + NestJS + PostgreSQL + Redis + MinIO`, keep mobile-app realtime and external-federation transport separated, and wire the minimum scripts so later tasks can run tests locally and in CI.
  **Must NOT do**: Do not implement feature logic, WebSocket debate/chat behavior, or any page-specific UI in this task.

  **Recommended Agent Profile**:
  - Category: `unspecified-high` — Reason: cross-stack bootstrap touching Flutter, Node, Docker, and repository conventions.
  - Skills: `[]` — Reason: native framework bootstrap and infra wiring are sufficient.
  - Omitted: `[using-git-worktrees, libtv-skill]` — Reason: workspace is not a git repo yet; media-generation tooling is unrelated.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: 2-12 | Blocked By: none

  **References**:
  - Product/stack: `项目规格说明书.md:19-33`
  - Suggested repo layout: `项目规格说明书.md:297-328`
  - Decision source: `.sisyphus/plans/agents-chat-platform.md` — sections `Context`, `Work Objectives`, and `Appendix A`

  **Acceptance Criteria** (agent-executable only):
  - [ ] `docker compose -f server/docker-compose.yml up -d postgres redis minio` starts all local infrastructure services successfully.
  - [ ] `pnpm --dir server test` executes the empty/foundation backend test suite without missing-script errors.
  - [ ] `flutter test` executes the empty/foundation Flutter test suite without missing-config errors.
  - [ ] `curl -sf http://localhost:3000/api/v1/health` returns HTTP 200 once the backend is running.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Fresh developer environment boots successfully
    Tool: Bash
    Steps: Run `docker compose -f server/docker-compose.yml up -d postgres redis minio`; run `pnpm --dir server install`; run `pnpm --dir server start:dev`; run `flutter pub get` inside `app`; run `flutter test`
    Expected: Postgres, Redis, and MinIO are healthy, server starts on configured port, Flutter dependencies resolve, and no bootstrap/test command fails because of missing config
    Evidence: .sisyphus/evidence/task-1-bootstrap.txt

  Scenario: Missing environment values fail clearly
    Tool: Bash
    Steps: Start backend with missing required env vars (for example remove database URL and JWT secret from local env file); run `pnpm --dir server start:dev`
    Expected: Backend exits with a clear configuration error message naming the missing variables; it does not hang or boot partially
    Evidence: .sisyphus/evidence/task-1-bootstrap-error.txt
  ```

  **Commit**: YES | Message: `chore(infra): bootstrap flutter app and nest backend` | Files: `app/**`, `server/**`, root config files

- [x] 2. Implement Flutter design system and five-tab app shell

  **What to do**: Create the shared Flutter theme, typography, spacing, bottom-tab shell, route structure, and reusable primitives needed by all screens. Derive the design tokens from Stitch and local exports: dark mode only, Electric Blue primary, tertiary purple accent, Space Grotesk headline, Inter body, layered surface cards, glass panels, and rounded geometry. Add explicit widget keys for all future QA flows (for example `tab-hall`, `tab-forum`, `tab-chat`, `tab-live`, `tab-hub`).
  **Must NOT do**: Do not implement full business logic for Hall/Forum/Chat/Debate/My; keep this task focused on shell, theme, reusable components, and placeholders.

  **Recommended Agent Profile**:
  - Category: `visual-engineering` — Reason: tokenizing the Stitch-derived UI system and preserving its cyber/digital-ether visual identity.
  - Skills: `[]` — Reason: standard Flutter UI work with explicit design references.
  - Omitted: `[libtv-skill]` — Reason: unrelated to UI implementation.

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 8-12 | Blocked By: 1

  **References**:
  - Design system: `项目规格说明书.md:270-280`
  - Local UI exports: `stitch_agents_chat/agents_hall_fixed_nav/code.html`, `stitch_agents_chat/agents_forum_fixed_nav/code.html`, `stitch_agents_chat/agents_chat_refined_header/code.html`, `stitch_agents_chat/live_debate_initiate_action/code.html`, `stitch_agents_chat/my_hub_security_refined/code.html`
  - Theme and surface decisions: `.sisyphus/plans/agents-chat-platform.md` — sections `Context` and `Appendix A`

  **Acceptance Criteria** (agent-executable only):
  - [ ] `flutter test test/core/theme/theme_test.dart` passes and validates the design tokens.
  - [ ] `flutter test test/app_shell_test.dart` passes and validates five-tab navigation plus required widget keys.
  - [ ] `flutter test --update-goldens test/goldens/app_shell_golden_test.dart` generates/updates deterministic shell goldens.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Five-tab shell matches planned navigation structure
    Tool: Flutter integration_test
    Steps: Launch app; tap keys `tab-hall`, `tab-forum`, `tab-chat`, `tab-live`, `tab-hub`; verify each surface placeholder renders and active tab state updates
    Expected: Only one tab is active at a time; each screen uses dark theme, correct accent colors, and the fixed bottom navigation shell
    Evidence: .sisyphus/evidence/task-2-app-shell.txt

  Scenario: Theme tokens stay consistent across surfaces
    Tool: Flutter widget/golden test
    Steps: Render shared primitives `GlassPanel`, `PrimaryGradientButton`, `SurfaceCard`, `StatusChip`; compare to approved goldens under dark theme
    Expected: Typography, radius, colors, and surface layering match the Stitch reference system; no light-theme regressions exist
    Evidence: .sisyphus/evidence/task-2-theme-goldens.png
  ```

  **Commit**: YES | Message: `feat(app): add digital ether theme and app shell` | Files: `app/lib/core/theme/**`, `app/lib/app_shell.dart`, `app/test/**`, `app/integration_test/**`

- [x] 3. Implement the backend schema and unified domain model

  **What to do**: Create NestJS modules/entities/migrations using **TypeORM** for `User`, `Agent`, `AgentPolicy`, `AgentConnection`, `Thread`, `ThreadParticipant`, `Event`, `ForumTopicView`, `DebateSession`, `DebateSeat`, `DebateTurn`, `Follow`, `Notification`, `Delivery`, `ClaimRequest`, `BlockRule`, `ModerationAction`, and `AuditLog`. Enforce immutable `Agent.handle`, explicit `owner_type = human | self`, per-recipient delivery, and the unified `Thread + Event` content model. Use projections rather than separate forum/chat/debate message tables.
  **Must NOT do**: Do not implement transport controllers or page-specific service behavior yet; this task is schema/domain-first.

  **Recommended Agent Profile**:
  - Category: `deep` — Reason: this task locks the domain model used by every later backend and UI feature.
  - Skills: `[]` — Reason: standard TypeORM/Prisma-style schema work and domain modeling.
  - Omitted: `[libtv-skill]` — Reason: unrelated to backend schema design.

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 4-12 | Blocked By: 1

  **References**:
  - Proposed core entities: `.sisyphus/plans/agents-chat-platform.md` — section `Appendix B — Core Entity Model`
  - Borrowable data model to refine, not copy: `项目规格说明书.md:252-267`
  - Domain recommendation source: `.sisyphus/plans/agents-chat-platform.md` — sections `Context` and `Appendix B`

  **Acceptance Criteria** (agent-executable only):
  - [ ] `pnpm --dir server test -- --runInBand test/domain/domain-model.spec.ts` passes for ownership, handle immutability, and entity relationships.
  - [ ] `pnpm --dir server migration:run` completes against local PostgreSQL.
  - [ ] `pnpm --dir server test -- --runInBand test/domain/thread-event-model.spec.ts` proves DM/forum/debate content share the unified Thread/Event model.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Unified model persists all core content surfaces correctly
    Tool: Bash
    Steps: Run migrations; seed one human-owned agent, one self-owned agent, one DM thread, one forum topic thread, one debate session with two seats; execute domain tests that create events for each surface
    Expected: All records persist without duplicate message tables; forum and debate projections resolve from Thread/Event data; immutable handle update attempts fail
    Evidence: .sisyphus/evidence/task-3-domain.txt

  Scenario: Invalid ownership and duplicate handle constraints are rejected
    Tool: Bash
    Steps: Attempt to create two agents with the same handle; attempt to create a `human` owner_type agent without `owner_user_id`; run the relevant integration tests
    Expected: Duplicate handle and invalid ownership writes fail with explicit constraint or validation errors
    Evidence: .sisyphus/evidence/task-3-domain-error.txt
  ```

  **Commit**: YES | Message: `feat(server): add unified domain schema and migrations` | Files: `server/src/entities/**`, `server/src/modules/**/entities/**`, `server/migrations/**`, `server/test/domain/**`

- [x] 4. Implement human auth, ownership, claim, and safety policy services

  **What to do**: Build email/password auth plus Google/GitHub login for humans; support `human-owned` and `self-owned` agents; implement My-page owner-mediated import semantics, later claim flow with challenge confirmation, separate `Human Safety` and `Agent Safety` policy models, block rules, and the rule that humans can never impersonate agent-authored content. Preserve the latest ownership decision: every agent has an owner, but owner type may be `human` or `self`.
  **Must NOT do**: Do not implement federation delivery or UI surfaces here; focus on auth, ownership semantics, policy storage, and claim workflow APIs/services.

  **Recommended Agent Profile**:
  - Category: `unspecified-high` — Reason: combines auth, ownership, policy logic, and claim semantics.
  - Skills: `[]` — Reason: standard backend auth and domain-service implementation.
  - Omitted: `[libtv-skill]` — Reason: unrelated.

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 5-12 | Blocked By: 1,3

  **References**:
  - Claim flow: `.sisyphus/plans/agents-chat-platform.md` — section `Appendix D — Federation v1 Contract`
  - Ownership and policy decisions: `.sisyphus/plans/agents-chat-platform.md` — sections `Interview Summary`, `Must Have`, and `Appendix A`
  - Human auth requirement: `项目规格说明书.md:142-145`

  **Acceptance Criteria** (agent-executable only):
  - [ ] `pnpm --dir server test -- --runInBand test/auth/auth.e2e-spec.ts` passes for email and OAuth human auth flows.
  - [ ] `pnpm --dir server test -- --runInBand test/ownership/claim-flow.e2e-spec.ts` passes for self-owned → human-owned claim confirmation.
  - [ ] `pnpm --dir server test -- --runInBand test/policy/safety-policies.spec.ts` passes for separate human-vs-agent DM policies and block rules.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Self-owned agent is later claimed by a logged-in human
    Tool: Bash
    Steps: Seed self-owned agent `@public-philosopher`; create logged-in human user; create claim request; inject valid `claim.confirm` action from the agent; query ownership and My Hub API projection
    Expected: Claim moves `pending -> confirmed`, agent owner_type becomes `human`, and the agent appears in the human-owned agent list
    Evidence: .sisyphus/evidence/task-4-claim.txt

  Scenario: Human cannot impersonate an agent and stranger DM rules are enforced
    Tool: Bash
    Steps: Attempt to create agent-authored content through a human-authenticated endpoint; attempt stranger human-to-agent DM without follow/request approval; run policy tests
    Expected: Agent impersonation is rejected; stranger DM creation is denied; errors are explicit and auditable
    Evidence: .sisyphus/evidence/task-4-policy-error.txt
  ```

  **Commit**: YES | Message: `feat(server): add auth ownership and claim policies` | Files: `server/src/modules/auth/**`, `server/src/modules/agents/**`, `server/src/modules/claims/**`, `server/src/modules/policies/**`, `server/test/auth/**`, `server/test/ownership/**`

- [x] 5. Implement federation transport, action processing, and delivery reliability

  **What to do**: Build the federation v1 transport described in the API draft: `POST /api/v1/agents/claim`, unified `POST /api/v1/actions`, `GET /api/v1/actions/{id}`, webhook delivery with HMAC signatures, cursor-based long polling, batch `POST /api/v1/acks`, token rotation, per-recipient local ordering, finite replay window, and dead-letter handling. Enforce `Idempotency-Key`, explicit ACK semantics, accepted-then-async action processing, and standard error shapes.
  **Must NOT do**: Do not fold app WebSocket realtime into this task; external federation transport and mobile-app realtime must remain separate concerns.

  **Recommended Agent Profile**:
  - Category: `deep` — Reason: this is the highest-risk protocol task in the plan and the backbone of open federation.
  - Skills: `[]` — Reason: protocol implementation can proceed from the approved draft.
  - Omitted: `[libtv-skill]` — Reason: unrelated.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: 7-12 | Blocked By: 1,3,4

  **References**:
  - Federation API draft: `.sisyphus/plans/agents-chat-platform.md` — sections `Appendix C — State Models` and `Appendix D — Federation v1 Contract`
  - Communication comparison and chosen transport: `.sisyphus/plans/agents-chat-platform.md` — sections `Context` and `Verification Strategy`
  - Spec relay principle: `项目规格说明书.md:185-193`

  **Acceptance Criteria** (agent-executable only):
  - [ ] `pnpm --dir server test -- --runInBand test/federation/claim.e2e-spec.ts` passes.
  - [ ] `pnpm --dir server test -- --runInBand test/federation/actions.e2e-spec.ts` passes.
  - [ ] `pnpm --dir server test -- --runInBand test/federation/delivery.e2e-spec.ts` passes for webhook, polling, ack, replay, retry, and dead-letter paths.
  - [ ] `pnpm --dir server test -- --runInBand test/federation/conformance.spec.ts` passes using fixture payloads for required event and action types.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: External agent claims successfully and consumes deliveries with ACKs
    Tool: Bash
    Steps: POST `/api/v1/agents/claim` with a valid claim token and webhook config; POST `/api/v1/actions` with `dm.send`; receive `dm.received` by webhook or polling; POST `/api/v1/acks` for the returned delivery
    Expected: Claim returns credentials and delivery config; action returns `accepted`; event is delivered once; ACK changes delivery state to `acked`
    Evidence: .sisyphus/evidence/task-5-federation-happy.json

  Scenario: Duplicate action and missed ACK are handled safely
    Tool: Bash
    Steps: Send the same `POST /api/v1/actions` twice with the same `Idempotency-Key`; suppress ACK for a delivered event until retries exhaust; inspect delivery history
    Expected: Only one logical action is processed; delivery progresses through `sent -> retrying -> failed/dead_letter` per retry policy; no duplicate content is created
    Evidence: .sisyphus/evidence/task-5-federation-error.json
  ```

  **Commit**: YES | Message: `feat(server): implement federation transport and delivery` | Files: `server/src/modules/federation/**`, `server/src/modules/delivery/**`, `server/test/federation/**`

- [x] 6. Implement unified content/event services and image asset ingestion

  **What to do**: Implement shared content services for `dm.send`, `forum.topic.create`, `forum.reply.create`, `debate.turn.submit`, and `debate.spectator.post` on top of `Thread + Event`. Add asset upload flow with `POST /api/v1/assets/uploads`, S3-compatible object-storage handoff (MinIO locally, production-compatible S3/OSS abstraction), `POST /api/v1/assets/{asset_id}/complete`, immediate image moderation, and `asset_id + caption` payload handling. Support `text`, `markdown`, `code`, and `image` content types from day one.
  **Must NOT do**: Do not build page-specific UI here; keep the task on backend content/action semantics and reusable content rendering contracts.

  **Recommended Agent Profile**:
  - Category: `unspecified-high` — Reason: combines backend content actions, event projections, and image ingestion/moderation.
  - Skills: `[]` — Reason: standard service/controller/testing work with explicit protocol decisions.
  - Omitted: `[libtv-skill]` — Reason: unrelated.

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 8-12 | Blocked By: 1,3,5

  **References**:
  - Content-type and upload decisions: `.sisyphus/plans/agents-chat-platform.md` — section `Appendix D — Federation v1 Contract`
  - Forum/topic rules: `.sisyphus/plans/agents-chat-platform.md` — section `Appendix A — Product Rules`
  - Chat/DM rules: `.sisyphus/plans/agents-chat-platform.md` — section `Appendix A — Product Rules`

  **Acceptance Criteria** (agent-executable only):
  - [ ] `pnpm --dir server test -- --runInBand test/content/content-actions.e2e-spec.ts` passes for DM, forum topic, forum reply, debate turn, and spectator post creation.
  - [ ] `pnpm --dir server test -- --runInBand test/assets/image-upload.e2e-spec.ts` passes for upload issue, complete, moderation accept, and moderation reject cases.
  - [ ] `pnpm --dir server test -- --runInBand test/content/content-types.spec.ts` passes for `text`, `markdown`, `code`, and `image` payload handling.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Image-backed content flows through moderation and becomes visible once approved
    Tool: Bash
    Steps: Request upload asset; upload an allowed PNG/JPG; complete the asset; submit `forum.reply.create` referencing `asset_id` and `caption`; fetch topic detail projection
    Expected: Asset completes successfully, moderation marks it allowed, and the reply appears with `content_type=image` plus caption metadata
    Evidence: .sisyphus/evidence/task-6-image-happy.json

  Scenario: Rejected image never enters the public content flow
    Tool: Bash
    Steps: Upload a fixture that the moderation stub marks as disallowed; call asset complete; attempt `dm.send` referencing that `asset_id`
    Expected: Asset is rejected; action query eventually returns `rejected` with standard error shape; no event/content row is created for the message
    Evidence: .sisyphus/evidence/task-6-image-error.json
  ```

  **Commit**: YES | Message: `feat(server): add unified content actions and asset ingestion` | Files: `server/src/modules/content/**`, `server/src/modules/assets/**`, `server/test/content/**`, `server/test/assets/**`

- [x] 7. Implement follow, notifications, app realtime fanout, moderation, and operator controls

  **What to do**: Build the cross-surface systems for follow/unfollow, notification creation and read-state, unified bell-blue behavior, app-side WebSocket realtime fanout for human clients, debate archive projection, moderation actions (rate-limit, mute, suspend, delete/hide), block rules, and operator-facing dead-letter/review endpoints. Ensure both humans and agents can follow `agent`, `topic`, and `debate` targets, that notifications feed both human UI and agent delivery pipelines, and that app realtime remains a separate channel from external federation transport.
  **Must NOT do**: Do not implement the visual surfaces themselves in this task; focus on backend services, projections, and control APIs.

  **Recommended Agent Profile**:
  - Category: `unspecified-high` — Reason: cross-cutting logic touching every major surface plus ops guardrails.
  - Skills: `[]` — Reason: no specialized external skill required.
  - Omitted: `[libtv-skill]` — Reason: unrelated.

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: 8-12 | Blocked By: 3,5,6

  **References**:
  - Follow/notification/archive decisions: `.sisyphus/plans/agents-chat-platform.md` — sections `Interview Summary`, `Must Have`, and `Appendix A`
  - Risk/moderation decisions: `.sisyphus/plans/agents-chat-platform.md` — sections `Must NOT Have`, `Context`, and `Appendix B`
  - Spec optional ideas to preserve: `项目规格说明书.md:198-243`

  **Acceptance Criteria** (agent-executable only):
  - [ ] `pnpm --dir server test -- --runInBand test/notifications/notifications.e2e-spec.ts` passes for human and agent recipients.
  - [ ] `pnpm --dir server test -- --runInBand test/follow/follow.e2e-spec.ts` passes for agent/topic/debate follow targets.
  - [ ] `pnpm --dir server test -- --runInBand test/moderation/moderation.e2e-spec.ts` passes for rate-limit, mute, suspend, and dead-letter operator actions.
  - [ ] `pnpm --dir server test -- --runInBand test/realtime/realtime-fanout.e2e-spec.ts` passes for human-client WebSocket updates driven by notifications/chat/debate changes.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Followed topic reply creates unread notification and blue bell state
    Tool: Bash
    Steps: Human user follows topic `thr_forum_1`; create a new reply on that topic; fetch notification center projection and bell status endpoint
    Expected: An unread notification exists for the user, and bell state reports unread notifications present
    Evidence: .sisyphus/evidence/task-7-notify-happy.json

  Scenario: Suspended agent disappears from active interaction surfaces but history remains
    Tool: Bash
    Steps: Suspend agent `agt_bad_1`; fetch Hall projection, active debate participant list, and historical topic/reply detail for old content from that agent
    Expected: Agent no longer appears in active Hall/interactions or eligible live participant sets; historical authored content remains accessible with suspension context preserved
    Evidence: .sisyphus/evidence/task-7-moderation-error.json

  Scenario: Human app receives realtime notification fanout without using federation transport
    Tool: Bash
    Steps: Connect a human-authenticated WebSocket client; create a followed-topic reply and a DM request; observe subscribed events on the app realtime channel
    Expected: Human client receives unread notification/bell-state updates and relevant thread updates over WebSocket while external agent delivery still uses webhook/polling paths
    Evidence: .sisyphus/evidence/task-7-realtime.txt
  ```

  **Commit**: YES | Message: `feat(server): add follows notifications realtime and moderation controls` | Files: `server/src/modules/follows/**`, `server/src/modules/notifications/**`, `server/src/modules/realtime/**`, `server/src/modules/moderation/**`, `server/src/modules/archive/**`, `server/test/notifications/**`, `server/test/realtime/**`

- [x] 8. Implement Agents Hall and Agent Detail surfaces

  **What to do**: Implement the Hall waterfall/grid, card states, search, bell state, and bottom-sheet Agent Detail using the Stitch exports. Enforce the exact UX rules: sort `debating > online > offline`; `Message` becomes `Request` when direct DM is not allowed; `Join` enters debate as spectator; offline agents remain viewable/requestable but not joinable; public source/vendor/runtime metadata is shown without risk-badge treatment.
  **Must NOT do**: Do not shortcut with static mock layouts that ignore backend sorting, CTA rules, or bell behavior.

  **Recommended Agent Profile**:
  - Category: `visual-engineering` — Reason: high-fidelity mobile UI with meaningful stateful CTA changes.
  - Skills: `[]` — Reason: standard Flutter surface implementation.
  - Omitted: `[libtv-skill]` — Reason: unrelated.

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: none | Blocked By: 2,6,7

  **References**:
  - Hall UX rules: `.sisyphus/plans/agents-chat-platform.md` — section `Appendix A — Product Rules`
  - Local UI exports: `stitch_agents_chat/agents_hall_fixed_nav/code.html`, `stitch_agents_chat/agent_detail_with_close_button/code.html`
  - Spec Hall summary: `项目规格说明书.md:81-94`

  **Acceptance Criteria** (agent-executable only):
  - [ ] `flutter test test/features/agents_hall/agents_hall_view_model_test.dart` passes for sort, CTA, and bell-state mapping.
  - [ ] `flutter test integration_test/agents_hall_flow_test.dart` passes for browse/search/detail/join/request flows.
  - [ ] `flutter test --update-goldens test/goldens/agents_hall_golden_test.dart` matches the approved visual references.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Hall sorts debating, online, then offline with correct CTAs
    Tool: Flutter integration_test
    Steps: Seed agents `agt-debating-1`, `agt-online-1`, `agt-offline-1`; open Hall via key `tab-hall`; assert card order using keys `agent-card-agt-debating-1`, `agent-card-agt-online-1`, `agent-card-agt-offline-1`; tap CTA keys `agent-cta-message-*` and `agent-cta-join-*`
    Expected: Debate card renders first with active `Join`; online card renders second; offline card renders last with no active join; restricted DM cards show `Request`
    Evidence: .sisyphus/evidence/task-8-hall.txt

  Scenario: Search and bottom-sheet detail preserve hall context
    Tool: Flutter integration_test
    Steps: Tap key `hall-search-button`; search `xenon`; tap card `agent-card-agt-xenon-01`; inspect bottom-sheet `agent-detail-sheet`; dismiss sheet
    Expected: Search finds all matching public agents, detail opens as bottom sheet, and dismissing it returns to the original Hall scroll/search context
    Evidence: .sisyphus/evidence/task-8-hall-detail.txt
  ```

  **Commit**: YES | Message: `feat(app): implement agents hall and detail sheet` | Files: `app/lib/features/agents_hall/**`, `app/test/features/agents_hall/**`, `app/integration_test/agents_hall_flow_test.dart`

- [x] 9. Implement Forum list, Topic Detail, and proposal-to-agent flow

  **What to do**: Implement the hot-ranked forum list, topic cards, follow control/count beside replies, Topic Detail, and the `Propose New Topic` modal as a human-to-own-agent proposal flow rather than direct human publishing. Enforce the approved rules: agents may reply to topic roots, humans may only reply to existing replies, reply depth is one level, anonymous users may read but not interact, and followed-topic replies feed the unified notification center.
  **Must NOT do**: Do not let signed-in humans publish root topics directly or reply to root topics directly.

  **Recommended Agent Profile**:
  - Category: `visual-engineering` — Reason: forum UI plus permission-sensitive interaction states and proposal modal behavior.
  - Skills: `[]` — Reason: standard Flutter + backend integration.
  - Omitted: `[libtv-skill]` — Reason: unrelated.

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: none | Blocked By: 2,6,7

  **References**:
  - Forum rules: `.sisyphus/plans/agents-chat-platform.md` — section `Appendix A — Product Rules`
  - Local UI exports: `stitch_agents_chat/agents_forum_fixed_nav/code.html`, `stitch_agents_chat/topic_detail_refined_human_badges/code.html`, `stitch_agents_chat/propose_new_topic_fixed_close_button/code.html`
  - Spec Forum summary: `项目规格说明书.md:95-106`

  **Acceptance Criteria** (agent-executable only):
  - [ ] `flutter test test/features/forum/forum_logic_test.dart` passes for hot sorting, follow count display, and root-reply permission logic.
  - [ ] `flutter test integration_test/forum_flow_test.dart` passes for anonymous reading, signed-in reply behavior, and proposal submission to own agent.
  - [ ] `flutter test --update-goldens test/goldens/forum_golden_test.dart` matches the approved forum visual states.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Signed-in human can propose a topic but cannot directly publish or reply to root
    Tool: Flutter integration_test
    Steps: Sign in human test user; open key `tab-forum`; tap key `forum-propose-topic-button`; fill modal keys `proposal-title-input`, `proposal-body-input`, `proposal-tags-input`; submit; open a topic detail and attempt root reply via key `topic-root-reply-button`
    Expected: Proposal is submitted to the user's agent queue, not published directly by the human; root reply action is hidden or blocked for the human user
    Evidence: .sisyphus/evidence/task-9-forum-human.txt

  Scenario: Agent root reply remains allowed while anonymous users remain read-only
    Tool: Bash + Flutter integration_test
    Steps: Seed an agent-authored root reply action; open Topic Detail anonymously; inspect replies and interaction controls
    Expected: Agent root reply renders normally; anonymous user sees full content and follow counts but no interactive reply/follow/proposal controls
    Evidence: .sisyphus/evidence/task-9-forum-anon.txt
  ```

  **Commit**: YES | Message: `feat(app): implement forum topics and proposal flow` | Files: `app/lib/features/forum/**`, `app/test/features/forum/**`, `app/integration_test/forum_flow_test.dart`

- [x] 10. Implement Chat list and DM detail with four-role private threads

  **What to do**: Implement the conversation list keyed by remote agent identity and the DM detail thread with explicit four-role rendering: remote agent, remote human admin, local agent, local human. Preserve visual identity rules from Stitch: humans carry explicit HUMAN badge/icon, left side is remote actors, right side is local actors, search is current-thread-only, share means share the agent/conversation entry point, not message contents. Enforce follow-plus-request initiation for human→agent DMs and preserve existing threads when stranger DM is later disabled.
  **Must NOT do**: Do not expose DM contents publicly, do not key the list by latest human speaker, and do not let humans masquerade as agents.

  **Recommended Agent Profile**:
  - Category: `visual-engineering` — Reason: dense stateful conversation UI with identity-heavy rendering rules.
  - Skills: `[]` — Reason: standard Flutter + backend integration.
  - Omitted: `[libtv-skill]` — Reason: unrelated.

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: none | Blocked By: 2,4,6,7

  **References**:
  - Chat rules: `.sisyphus/plans/agents-chat-platform.md` — section `Appendix A — Product Rules`
  - Local UI exports: `stitch_agents_chat/agents_chat_refined_header/code.html`, `stitch_agents_chat/multi_party_chat_removed_first_bracket/code.html`
  - Spec Chat summary: `项目规格说明书.md:107-118`

  **Acceptance Criteria** (agent-executable only):
  - [ ] `flutter test test/features/chat/chat_logic_test.dart` passes for list identity, DM permission mapping, and menu behaviors.
  - [ ] `flutter test integration_test/chat_flow_test.dart` passes for four-role rendering, DM request flow, and thread search/share behavior.
  - [ ] `flutter test --update-goldens test/goldens/chat_golden_test.dart` matches the approved chat visuals.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Four-role DM thread renders correctly and remains private
    Tool: Flutter integration_test
    Steps: Sign in a human with one owned agent; open key `tab-chat`; tap `conversation-card-agt-xenon-remote`; verify message bubbles with keys `msg-remote-agent-1`, `msg-remote-human-1`, `msg-local-agent-1`, `msg-local-human-1`
    Expected: Remote messages render on the left, local on the right, human messages show explicit HUMAN badge/icon, and no share action exposes message contents
    Evidence: .sisyphus/evidence/task-10-chat.txt

  Scenario: Human stranger-DM restrictions preserve old threads but block new ones
    Tool: Bash + Flutter integration_test
    Steps: Seed an existing DM thread; disable stranger-agent DMs in My Hub policy; attempt to start a new DM from Hall and reopen the existing thread
    Expected: Existing thread remains readable, new thread creation is blocked or downgraded to request flow, and CTA text updates accordingly
    Evidence: .sisyphus/evidence/task-10-chat-policy.txt
  ```

  **Commit**: YES | Message: `feat(app): implement private chat threads and dm rules` | Files: `app/lib/features/chat/**`, `app/test/features/chat/**`, `app/integration_test/chat_flow_test.dart`

- [x] 11. Implement Live Debate, Initiate Debate, spectator feed, and archive/replay

  **What to do**: Implement the pending/live/paused/ended/archived debate lifecycle across the initiate modal, live debate surface, host controls, spectator feed, and archive view. Preserve strict two-seat debate rules, explicit pro/con stances, required host, strict alternating turns, host-controlled start/pause/resume/end, free-entry replacement semantics (only for missing/disconnected debater replacement), and debate archive after end. Keep spectator feed separate from formal debate turns.
  **Must NOT do**: Do not permit more than two active debating agents, do not allow the debating agents to post into spectator feed while debating, and do not let human hosts author agent turns.

  **Recommended Agent Profile**:
  - Category: `unspecified-high` — Reason: combines the most complex UI and state-machine-driven backend interactions in the product.
  - Skills: `[]` — Reason: standard implementation with approved state model.
  - Omitted: `[libtv-skill]` — Reason: unrelated.

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: none | Blocked By: 2,5,6,7

  **References**:
  - Debate rules and state machine: `.sisyphus/plans/agents-chat-platform.md` — sections `Appendix A — Product Rules` and `Appendix C — State Models`
  - Local UI exports: `stitch_agents_chat/live_debate_initiate_action/code.html`, `stitch_agents_chat/live_debate_refined_human_labels/code.html`, `stitch_agents_chat/initiate_debate_refined_host_circle/code.html`
  - Spec debate summary: `项目规格说明书.md:119-133`

  **Acceptance Criteria** (agent-executable only):
  - [ ] `pnpm --dir server test -- --runInBand test/debate/debate-state-machine.e2e-spec.ts` passes.
  - [ ] `flutter test test/features/debate/debate_view_model_test.dart` passes for host controls, seat replacement, and spectator permissions.
  - [ ] `flutter test integration_test/debate_flow_test.dart` passes for lobby → live → paused → resumed → ended → archived.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Host-driven debate lifecycle behaves correctly
    Tool: Flutter integration_test
    Steps: Open key `tab-live`; tap `initiate-debate-button`; fill `debate-topic-input`, `pro-stance-input`, `con-stance-input`; select two candidates and host; create pending debate; use keys `debate-start-button`, `debate-pause-button`, `debate-resume-button`, `debate-end-button`
    Expected: Debate moves through pending, live, paused, resumed, ended, then appears in archive/replay list automatically
    Evidence: .sisyphus/evidence/task-11-debate-lifecycle.txt

  Scenario: Missing turn triggers pause and free-entry replacement flow
    Tool: Bash + Flutter integration_test
    Steps: Seed a live debate; withhold `debate.turn.submit` from the expected agent until deadline; if free entry is enabled, submit replacement candidate; resume via host control
    Expected: Turn becomes `missed`, debate enters `paused`, replacement seat enters `replacing` then `occupied`, and resumed debate preserves the original seat stance
    Evidence: .sisyphus/evidence/task-11-debate-replacement.txt
  ```

  **Commit**: YES | Message: `feat(app): implement live debate lifecycle and archive` | Files: `app/lib/features/debate/**`, `server/src/modules/debate/**`, `app/test/features/debate/**`, `server/test/debate/**`

- [x] 12. Implement My Hub, import flow, claim UI, and human/agent safety management

  **What to do**: Implement My Hub with owned-agent carousel, human auth block, followed/following sections, add-agent sheet, import-via-link flow, claim flow entry, separate Human Safety and Agent Safety controls, and disabled `Create new agent` placeholder. Support email/Google/GitHub sign-in, owner-mediated import where a human sends a read-only command to their own agent, immediate post-claim appearance in the carousel, and per-agent safety configuration.
  **Must NOT do**: Do not allow direct in-app agent creation, do not collapse human and agent safety into one combined settings panel, and do not bypass ownership/claim rules.

  **Recommended Agent Profile**:
  - Category: `visual-engineering` — Reason: account, ownership, import, and safety UX all converge in one high-density settings surface.
  - Skills: `[]` — Reason: standard Flutter + auth/backend integration.
  - Omitted: `[libtv-skill]` — Reason: unrelated.

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: none | Blocked By: 2,4,5,7

  **References**:
  - My Hub rules: `.sisyphus/plans/agents-chat-platform.md` — section `Appendix A — Product Rules`
  - Local UI exports: `stitch_agents_chat/my_hub_security_refined/code.html`, `stitch_agents_chat/add_agent_selection/code.html`, `stitch_agents_chat/import_agent_via_link_modal/code.html`, `stitch_agents_chat/human_authentication_focused_modal/code.html`, `stitch_agents_chat/human_registration_focused_modal/code.html`, `stitch_agents_chat/refined_external_provider_selection_clean_logo/code.html`, `stitch_agents_chat/simplified_new_agent_form/code.html`
  - Spec My Hub summary: `项目规格说明书.md:134-145`

  **Acceptance Criteria** (agent-executable only):
  - [ ] `flutter test test/features/hub/hub_logic_test.dart` passes for owned-agent carousel, auth-state rendering, claim-entry availability, and separate safety policies.
  - [ ] `flutter test integration_test/hub_flow_test.dart` passes for sign-in, import command display, claim flow, and per-agent safety editing.
  - [ ] `flutter test --update-goldens test/goldens/hub_golden_test.dart` matches the approved Hub visual states.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Human imports an owned agent and sees it immediately in My Hub
    Tool: Flutter integration_test
    Steps: Open key `tab-hub`; sign in test human; tap `add-agent-button`; choose `import-agent-option`; copy from `import-command-field`; simulate agent claim using that token; refresh hub
    Expected: The imported agent appears in the carousel with the correct connection/presence state and owner-bound settings available
    Evidence: .sisyphus/evidence/task-12-hub-import.txt

  Scenario: Human and agent safety controls remain separate and effective
    Tool: Flutter integration_test + Bash
    Steps: Open keys `human-safety-section` and `agent-safety-section-agt-xenon-7`; disable stranger-human DM for human and allow stranger-agent DM for the owned agent; trigger both a human-originated and agent-originated DM attempt from fixtures
    Expected: Human policy blocks the human-side DM case while the agent-specific policy still allows the owned agent's configured behavior; UI reflects distinct settings scopes
    Evidence: .sisyphus/evidence/task-12-hub-safety.txt
  ```

  **Commit**: YES | Message: `feat(app): implement my hub import claim and safety flows` | Files: `app/lib/features/hub/**`, `app/test/features/hub/**`, `app/integration_test/hub_flow_test.dart`, related server auth/claim endpoints

## Final Verification Wave (MANDATORY — after ALL implementation tasks)
> 4 review agents run in PARALLEL. ALL must APPROVE. Present consolidated results to user and get explicit "okay" before completing.
> **Do NOT auto-proceed after verification. Wait for user's explicit approval before marking work complete.**
> **Never mark F1-F4 as checked before getting user's okay.** Rejection or user feedback -> fix -> re-run -> present again -> wait for okay.
- [ ] F1. Plan Compliance Audit — oracle

  **What to do**: Compare implemented behavior against every task, dependency, and guardrail in this plan.
  **QA Scenarios**:
  ```
  Scenario: Full implementation matches plan commitments
    Tool: oracle
    Steps: Review repository changes against Tasks 1-12, Appendix A-D, and all Must Have / Must NOT Have items; verify that each planned deliverable exists and no forbidden scope was added
    Expected: Oracle approves with no missing core deliverables, no unplanned transport/model divergence, and no scope violations
    Evidence: .sisyphus/evidence/f1-plan-compliance.md
  ```
- [ ] F2. Code Quality Review — unspecified-high

  **What to do**: Review code quality, cohesion, naming, duplication, and maintainability across app and server.
  **QA Scenarios**:
  ```
  Scenario: Repository quality clears final review
    Tool: unspecified-high
    Steps: Inspect app and server modules, test layout, naming consistency, migration hygiene, and duplication across Hall/Forum/Chat/Debate/My implementations; confirm logs/errors are structured and actionable
    Expected: Reviewer approves with no critical maintainability, layering, or correctness concerns
    Evidence: .sisyphus/evidence/f2-code-quality.md
  ```
- [ ] F3. Real Manual QA — unspecified-high (+ playwright if UI)

  **What to do**: Execute the highest-value end-to-end user and agent journeys on the running system.
  **QA Scenarios**:
  ```
  Scenario: End-to-end happy-path product walkthrough succeeds
    Tool: unspecified-high
    Steps: Start local infra and app/server; walk through sign-in, import or claim an agent, browse Hall, follow an agent/topic, open a DM, create a topic proposal, start a debate, post in spectator feed, and verify notification center updates
    Expected: All major journeys succeed without manual data patching or broken navigation/state mismatches
    Evidence: .sisyphus/evidence/f3-e2e-happy.md

  Scenario: End-to-end edge cases fail safely
    Tool: unspecified-high
    Steps: Exercise blocked stranger DM, duplicate `Idempotency-Key`, debate missing-turn pause, rejected image upload, and suspended-agent visibility behavior
    Expected: Each edge case fails or degrades exactly as planned, with explicit user-facing/system-facing feedback and no data corruption
    Evidence: .sisyphus/evidence/f3-e2e-edge.md
  ```
- [ ] F4. Scope Fidelity Check — deep

  **What to do**: Ensure the delivered system still matches the agreed phase-1 scope freeze and did not quietly absorb deferred features.
  **QA Scenarios**:
  ```
  Scenario: Deferred features remain deferred
    Tool: deep
    Steps: Inspect the implementation for signs of in-app agent creation, multi-agent debates, direct agent-to-agent transport, or missing moderation/dead-letter support; compare against deferred-scope statements in this plan
    Expected: Reviewer confirms deferred features were not partially or inconsistently implemented and all required guardrails exist
    Evidence: .sisyphus/evidence/f4-scope-fidelity.md
  ```

## Commit Strategy
- Create one atomic commit per vertical slice after tests pass.
- Prefer commits in this order: infrastructure → schema/domain → federation → assets/content → notifications/moderation → each surface implementation.
- Suggested message families:
  - `chore(infra): bootstrap app and server workspace`
  - `feat(server): add unified event and federation foundations`
  - `feat(app): implement agents hall surface`
  - `feat(app): implement debate lifecycle and spectator feed`

## Success Criteria
- A fresh engineer can implement the system without making product or protocol choices not already decided here.
- All five mobile surfaces behave according to the approved Stitch designs and documented interaction rules.
- Federation v1 supports self-owned and human-owned agents, claim onboarding, polling fallback, per-event ACK, and finite replay.
- Human safety restrictions and agent autonomy coexist without identity confusion or privilege leakage.
- Debate, forum, chat, and notifications all share one coherent event-driven backend model.

## Appendix A — Product Rules
- **Ownership**: Agents are either `human-owned` or `self-owned`. Humans never impersonate agent-authored content.
- **Hall**: Sort debating > online > offline. `Join` enters spectator view by default. DM CTA becomes `Message` or `Request` depending on permission. Offline agents remain viewable and requestable but not joinable.
- **Forum**: Topics are agent-authored. Human topic creation is a proposal to the human's own agent. Humans cannot reply to topic roots directly; agents can. Reply depth is one level. Anonymous users may read but not interact.
- **Chat**: DM detail is one private multi-participant thread with four possible speaking roles. List items key off remote agent identity. Thread search is current-thread-only. Share shares the agent/conversation entry point, not DM contents.
- **Debate**: Exactly two active debating agents. Host is required. Debate lifecycle is pending → live → paused → ended → archived. Formal turns alternate strictly. Spectator feed is separate from formal turns. Free entry only allows seat replacement for absent/disconnected debaters.
- **My Hub**: Owned-agent carousel first. Separate Human Safety and Agent Safety sections. Import is enabled, create-new-agent is visible but disabled. Human auth supports email, Google, GitHub.
- **Notifications**: Bell-blue means unread notifications exist. Human and agent notifications share one conceptual notification model.

## Appendix B — Core Entity Model
- `User`: human identity, auth provider, locale, stranger-DM safety settings.
- `Agent`: immutable `handle`, mutable public profile, `owner_type` (`human|self`), source/vendor/runtime, presence and public status.
- `AgentPolicy`: per-agent DM acceptance, outbound DM, proactive interaction, activity-level policy.
- `AgentConnection`: protocol version, transport mode, webhook/polling settings, token hash, heartbeat/last-seen, capability manifest.
- `Thread`: canonical content container for `dm`, `forum_topic`, and `debate_spectator` contexts.
- `ThreadParticipant`: membership and read-state for humans/agents within a thread.
- `Event`: canonical content/mutation record with actor, target, content type, metadata, and idempotency key.
- `ForumTopicView`: projection over Thread/Event for hot score, counts, and last activity.
- `DebateSession`, `DebateSeat`, `DebateTurn`: debate state machine and seat/turn tracking.
- `Follow`, `Notification`, `Delivery`, `ClaimRequest`, `BlockRule`, `ModerationAction`, `AuditLog`: cross-cutting follow, notify, federation delivery, ownership claim, policy blocking, moderation, and auditing entities.

## Appendix C — State Models
- `Agent.status`: `offline | online | debating | suspended`
- `ClaimRequest.status`: `pending | confirmed | expired | rejected`
- `Delivery.status`: `pending | sent | acked | retrying | failed | dead_letter`
- `DebateSession.status`: `pending | live | paused | ended | archived`
- `DebateSeat.status`: `reserved | occupied | vacant | replacing`
- `DebateTurn.status`: `pending | completed | skipped | missed`
- `pending -> live` requires host present, both seats occupied, and explicit start by host; if host is an agent, platform emits `debate.ready_to_start` and the host agent must send `debate.start`.
- `paused -> live` requires host manual resume and a recoverable turn state.
- `ended -> archived` is automatic.

## Appendix D — Federation v1 Contract
- **Transport split**: app realtime uses WebSocket; external federation uses HTTP + webhook + polling fallback.
- **Auth**: long-lived rotatable agent bearer tokens; webhook HMAC signature headers.
- **Core endpoints**:
  - `POST /api/v1/agents/claim`
  - `POST /api/v1/actions`
  - `GET /api/v1/actions/{id}`
  - `GET /api/v1/deliveries/poll?cursor=&limit=&wait_seconds=`
  - `POST /api/v1/acks`
  - `POST /api/v1/agents/token/rotate`
- **Mutation behavior**: action requests are async-first and require `Idempotency-Key`.
- **Delivery guarantees**: per-recipient local ordering, explicit ACK, finite replay window, dead-letter support.
- **Required action types**: `agent.profile.update`, `agent.follow`, `agent.unfollow`, `dm.send`, `forum.topic.create`, `forum.reply.create`, `debate.create`, `debate.start`, `debate.pause`, `debate.resume`, `debate.end`, `debate.turn.submit`, `debate.spectator.post`, `claim.confirm`.
- **Representative event types**: `dm.received`, `forum.topic.replied`, `forum.reply.replied`, `debate.ready_to_start`, `debate.started`, `debate.paused`, `debate.resumed`, `debate.ended`, `debate.turn.assigned`, `debate.turn.missed`, `debate.seat.replacement_needed`, `notification.created`, `claim.challenge_issued`, `claim.confirmed`, `ownership.transferred`, `agent.suspended`, `agent.rate_limited`, `delivery.retrying`, `delivery.dead_letter`.
- **Payload decisions**:
  - `dm.send`: supports implicit thread creation/reuse with `target_type + target_id`
  - `forum.topic.create`: requires `title + content + tags`
  - `forum.reply.create`: requires `topic_id`, optional `parent_reply_id`
  - `debate.create`: requires `topic`, `pro_stance`, `con_stance`, two debater candidates, `host`, `free_entry`, `human_host`
  - `debate.turn.submit`: only the expected seat may submit, once per turn by default
  - `agent.profile.update`: mutable `display_name`, `avatar`, `bio`, `tags`; immutable `handle`
  - `debate.spectator.post`: minimum `debate_id + content`
- **Content model**: phase 1 supports `text`, `markdown`, `code`, and `image`.
- **Assets**: use pre-upload asset flow, then reference `asset_id + caption`; images are scanned before entering public/private content flows.
