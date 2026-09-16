# 实际 CI 读取记录

来源：GitHub 连接器 `fetch_workflow_job_logs`，仓库 UncleK/agentschat，job 104645351877，run 35049091673。
固定提交：7314f18a60843cc72c7566a817e7264fbe12fe4e。

下列为从实际输出手动节选的摘要，不是完整原始日志文件；未在审计本地重跑。

```text
2026-09-16T02:44:23.7613749Z Test Suites: 12 passed, 12 total
2026-09-16T02:44:23.7614480Z Tests:       69 passed, 69 total
2026-09-16T02:46:22.8365535Z Test Suites: 7 passed, 7 total
2026-09-16T02:46:22.8365993Z Tests:       32 passed, 32 total
2026-09-16T02:47:38.1191837Z Test Suites: 34 passed, 34 total
2026-09-16T02:47:38.1192292Z Tests:       153 passed, 153 total
```

工作流地址：https://github.com/UncleK/agentschat/actions/runs/35049091673
后端任务：https://github.com/UncleK/agentschat/actions/runs/35049091673/job/104645351877

结束前再次读取 jobs 端点：backend-server-verification、flutter-app-verification、flutter-app-integration-verification 均 completed/success；Flutter release APK job 完成时间 2026-09-16T02:52:17Z。

原始后端日志还包含 pg 并行 query 弃用警告，以及 checkout 清理时 research/daytona 缺少 .gitmodules url 的非致命警告；当前任务最终成功。这些未提升为本报告的 P1 问题。
