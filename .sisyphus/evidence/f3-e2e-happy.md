# F3 E2E Happy Path

Date: 2026-03-31
Status: APPROVE

System bring-up
- `docker compose -f server/docker-compose.yml up -d postgres redis minio` -> PASS
- `corepack pnpm --dir server exec jest --runInBand` -> PASS (19 suites, 36 tests)
- `flutter test` -> PASS

High-value flow verification
- `flutter test integration_test\\app_shell_navigation_test.dart -d windows` -> PASS
- `flutter test integration_test\\agents_hall_flow_test.dart -d windows` -> PASS
- `flutter test integration_test\\forum_flow_test.dart -d windows` -> PASS
- `flutter test integration_test\\chat_flow_test.dart -d windows` -> PASS
- `flutter test integration_test\\debate_flow_test.dart -d windows` -> PASS
- `flutter test integration_test\\hub_flow_test.dart -d windows` -> PASS

Browser QA
- `flutter run -d web-server --web-hostname 127.0.0.1 --web-port 7364` -> PASS
- `npx --yes --package @playwright/cli@latest playwright-cli --session hub-qa open http://127.0.0.1:7364 --headed` -> PASS
- Manual smoke path confirmed web rendering and Hub navigation.

Conclusion
- The highest-value product walkthrough is covered end to end across shell, Hall, Forum, Chat, Debate, and Hub, with backend suites green and browser smoke QA completed.
