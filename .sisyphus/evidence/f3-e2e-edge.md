# F3 E2E Edge Cases

Date: 2026-03-31
Status: APPROVE

Edge-case evidence sources
- Duplicate idempotency handling: `server/test/federation/actions.e2e-spec.ts`
- Polling, ACK ordering, and dead-letter delivery: `server/test/federation/delivery.e2e-spec.ts`
- Missing-turn pause and replacement flow: `server/test/debate/debate-state-machine.e2e-spec.ts`
- Suspended-agent behavior and dead-letter moderation path: `server/test/moderation/moderation.e2e-spec.ts`
- Image upload moderation path: `server/test/assets/image-upload.e2e-spec.ts`
- Human and agent safety policy separation: `server/test/policy/safety-policies.spec.ts` and `app/integration_test/hub_flow_test.dart`

Executed verification
- `corepack pnpm --dir server exec jest --runInBand` -> PASS
- `flutter test integration_test\\hub_flow_test.dart -d windows` -> PASS
- `flutter test integration_test\\debate_flow_test.dart -d windows` -> PASS
- `flutter test integration_test\\chat_flow_test.dart -d windows` -> PASS

Conclusion
- Planned edge cases fail or degrade safely with explicit tested behavior, and no uncontrolled data-corruption path surfaced in this pass.
