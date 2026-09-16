# AgentsChat Re-audit v1.2 修复与实测记录

日期：2026-09-16。工作区：`E:\VP\agents_chat_release_candidate`。目标：`UncleK/agentschat`。

开始时 HEAD 和审查基准均为 `7314f18a60843cc72c7566a817e7264fbe12fe4e`；收尾通过 `git ls-remote origin refs/heads/main` 确认远端仍是该提交。开始时仅有用户提供的未跟踪审计包。修复在 `codex/reaudit-v1.2` 完成；代码提交见 `EXECUTION_RESULTS.json`。没有部署、生产迁移、生产凭证重放或真实私信读取。公开仓库未推送本轮修复和复现材料。

## 结论与之前遗漏的原因

RR-01～04 均重新核对源码并确认，不是仅照报告修改。旧验收覆盖了主要接口，却遗漏头像与邀请刷新这类其它实体写入路径、初始化凭证的完整生命周期、真实 Python 客户端协议，以及普通浏览器与可信终端的衔接。后端 fixture 能成功绑定，不能证明旧 adapter 也能绑定；历史 CI 绿色也不能证明未覆盖的并发交错安全。

本轮使用真实 PostgreSQL 16、MinIO、HTTP API、Python 子进程与浏览器。barrier 只控制调度，头像测试仍执行真实数据库和对象存储操作。保留 public 免预注册、未绑定参与、原 ID 后续绑定、bound 接入；没有修改 owner 枚举含义，没有自动公开历史内容。

## RR-01：头像发布与旧实体回写

**复核与先失败证据：** `rr01-before.json` 的 6 个 PostgreSQL/barrier 用例全部失败。另补过期上传、重复完成及邀请刷新交错；`rr01-expiry-before.json`、`rr01-invitation-before.json` 保留对应失败。邀请刷新旧实现实际出现连接外键列 NOT NULL 导致的 500/事务回滚，不将其描述成已成功覆盖归属。

**改动文件：** `server/src/modules/agents/agents.service.ts`、`server/test/audit/avatar-concurrency.e2e-spec.ts`。

对象读取、解码和写入保持在事务外；发布/清理 pending 时短事务锁定并重读 Agent，比较 bucket/key/expiry，只写当前 metadata 的头像子字段及 avatarUrl。成功、拒绝、过期、第二次上传、重复完成均覆盖。策略和 owner 保持当前值。并发合法绑定测试另验证既有私信保存、绑定后主人可读、陌生人不可读及 `isPublic=false`。

排查其它完整实体保存：邀请刷新已改为锁内重读及精确更新；claim 初始化同步修复；现有 profile 与主人策略写入已在锁内读取；createAgent 保存的是新实体，不作为旧实体回写误报。没有为这次任务重写其它模块。

**兼容/迁移：** 头像 API 保持；无 RR-01 数据迁移。旧/过期完成请求现在得到 409，不能清掉新 pending。**未覆盖边界：** 对象写入后 CAS 输掉可能留下未引用的已校验对象；没有新增存储垃圾回收，容量维护仍需既有运维策略。该对象不会成为 Agent 的公开头像指针。**回滚：** 可回退对应代码，但会重开已确认竞争；不应以此作为安全发布方案。

## RR-02：初始化消费、撤销与受控恢复

**先失败证据：** `rr02-before.json` 5 个 HTTP/PostgreSQL 用例全部失败；`rr02-rotation-before.json` 另证实已在 guard 认证、随后被撤销的旧 principal 仍可轮换。`client-recovery-redirect-before.json` 记录 Python 不能使用同 ID 新恢复邀请的问题。

**主要文件：** `server/migrations/1710000014000-BootstrapConsumption.ts`；federation 的 credentials/service/controller/types；agents service/controller；native `launcher.ts`、`state.ts`、`types.ts`、`cli.ts`、`worker.ts` 及对应 dist；Python `adapter/launch.py`；`bootstrap-lifecycle.e2e-spec.ts`、`adapter-process.e2e-spec.ts`、`native-recovery-client.mjs`。

初始化在 Agent 行锁下同时持久化连接和消费记录；消费记录在断开后保留。轮换重验当前 tokenHash 并撤销恢复窗口。首次请求前客户端持久保存独立随机恢复证明；同一 token、证明、请求参数及连接在五分钟内只能恢复同一初始 bearer。不同证明、轮换、断开、过期均不能重新夺回连接。原生客户端测试实际丢弃服务器提交后的响应，再由新进程读取保存的证明恢复。

经登录账户授权断开后，可用 `POST /agents/:agentId/connection-invitation` 取得原 ID 的新一次性邀请；当前连接存在时拒绝。Python 实际进程已验证恢复与随后重启，错误网络响应不会触发新身份创建。正常 public/bound 重启直接使用保存的 bearer。长期 bearer 不写入 launcher。

**兼容/迁移：** 新表 `agent_bootstrap_consumptions`；已有连接或历史 last_seen 的 Agent 种入消费标记，原 ID/当前 bearer 不变。未使用的旧有效链接仍可首次接入一次；旧客户端没有恢复证明时无法自动重试丢响应，需要升级。新表全新安装迁移经过测试；未复制生产库验证大型存量回填时长。无任何生产 migration 执行。

**残余条件/回滚：** 未绑定身份丢失全部控制证明后不允许公共领取；五分钟之外不承诺仅凭 bootstrap 恢复。保留私有状态备份。回滚应用不应删除消费记录或执行该表的 down migration，否则撤销记录丢失；旧服务代码本身也不遵守新消费规则，不能作为安全降级运行。

## RR-03/04：真实 adapter 与浏览器—终端授权

**先失败证据：** 从基准提取的真实旧 Python adapter 对隔离后端执行绑定，得到 `control_authorization_required`、退出 1。新设备流程用例在未实现前返回 404，见 `rr03-04-before.json`。RR-04 是操作流程缺口，不虚构既有凭证泄露事件。

**主要文件：** `binding-device.controller.ts`、`binding-device.service.ts`、`agents.module.ts`、`agents.service.ts`；迁移 `1710000015000-BindingDevices.ts`；Python `launch.py`；native `trusted-management.ts` 与 dist；Web `/binding/authorize` 及 `/en/binding/authorize`、`binding-authorization.tsx`、`auth-navigation.ts`；skill/reference 文档与 plugin README；`binding-device.e2e-spec.ts` 和 browser/PTY 测试脚本。

原控制端创建绑定到 purpose/account/agent/request/expiry 的设备授权。浏览器正常登录并明确确认；CLI 展示账户和目标，操作者输入完整 `BIND accountId agentId` 后才提交。服务端在事务内重验已登录会话版本/有效期、原控制凭证、申请与授权，原子绑定、消费与写审计。浏览器链接只有查询码；没有要求 DevTools、完整 Cookie 或 human bearer。并发确认只成功一次，只有一条绑定审计。公开社交 `claim.confirm` 继续拒绝；Python 和 native 的管道输入在网络操作前拒绝。保留原生执行层工具隔离。

Python API 与上传请求新增拒绝重定向；本地两个 HTTP listener 的回归先证实旧实现会转发请求，修复后源返回 302、目标收到 0 请求。须使用 canonical URL，不能依靠跨站重定向。

**真实正向链路：** Python public 建立身份 → Python 自己发帖 → fixture 确认尚无 Human 账户 → 正常注册 → 浏览器表单登录/HttpOnly session → 浏览器批准时仍未绑定 → Windows ConPTY 内真实 Python 进程接受明确批准 → 同 ID、同历史、正确 owner、授权 consumed。`binding-browser.verify.js` 由真实 Playwright CLI 执行通过；证据为 `browser-cli-actual.json`、`browser-approved.png`。没有向浏览器注入合成 JWT；合成的是账户和内容，登录凭证由真实登录接口签发。

**兼容/迁移：** 增加 `binding_devices` 表；服务端、Python skill、native dist 和 Web 需要配套更新。旧社交确认不会重新开放。此授权页面现为中文，英文入口可访问但尚未完整本地化。终端 TTY 是一项入口限制；它不能替代操作系统隔离。第三方宿主若向社交模型提供同一 OS 账户下的任意进程/文件能力，仍须收紧宿主权限。

**未运行/回滚：** Linux `pty.fork` 驱动未在本机执行，真实正向验证使用 Windows ConPTY；原生插件浏览器正向链路未另跑，已运行其管道拒绝、控制授权与真实 SDK 工具隔离测试。新增表可保留，撤回 UI/CLI 时应明确暂缓该管理流程，不能恢复不安全社交授权或索取完整 human bearer。

## 实际命令与结果

隔离服务绑定 loopback：PostgreSQL `15432`、MinIO `19000`。每个 backend suite 用独立随机数据库；浏览器 fixture 用独立 `agents_chat_reaudit_*` 数据库。测试不用生产环境变量中的真实邮件、账户或凭证。

```powershell
$env:DATABASE_URL='postgres://agents_chat:agents_chat@127.0.0.1:15432/agents_chat'
$env:MINIO_PORT='19000'
pnpm --dir server test:e2e --runTestsByPath test/audit/avatar-concurrency.e2e-spec.ts --json --outputFile=../Review_GPTpro/AgentsChat_Reaudit_v1.2/rr01-before.json
pnpm --dir server test:e2e --runTestsByPath test/audit/bootstrap-lifecycle.e2e-spec.ts --json --outputFile=../Review_GPTpro/AgentsChat_Reaudit_v1.2/rr02-before.json
pnpm --dir server test:e2e --runTestsByPath test/audit/binding-device.e2e-spec.ts --json --outputFile=../Review_GPTpro/AgentsChat_Reaudit_v1.2/rr03-04-before.json
pnpm --dir server test:unit --json --outputFile=../Review_GPTpro/AgentsChat_Reaudit_v1.2/unit-after.json
pnpm --dir server test:integration --json --outputFile=../Review_GPTpro/AgentsChat_Reaudit_v1.2/integration-after.json
pnpm --dir server test:e2e --json --outputFile=../Review_GPTpro/AgentsChat_Reaudit_v1.2/e2e-final.json
pnpm --dir server lint
pnpm --dir server typecheck
pnpm --dir server build
npm --prefix plugins/agentschatapp run build
npm --prefix plugins/agentschatapp test
npm --prefix web run typecheck
npm --prefix web test
npm --prefix web run build
python skills/agents-chat-v1/adapter/installer_repo_test.py --shell powershell -v
```

前 3 个命令在对应修复前执行，结果是上述失败；不是在最终代码上期待失败。单元 69、集成 32、native 16、Web 49、PowerShell installer 3 项通过。后端 lint/typecheck/build、native build、Web typecheck/build 通过。最终完整 e2e 以 `EXECUTION_RESULTS.json` 和 `e2e-final.json` 为准；历史 `e2e-after.json` 为较早完整 173 项通过。

最终全量曾有一次进程异常退出 `3221226505`，未写出 JSON，不算通过。关闭本轮浏览器验收服务后单独重跑；异常记录保留在 `EXECUTION_RESULTS.json`，没有将原因未经验证地归为代码或内存问题。pg 已有并行 query 弃用警告也不隐藏。

真实联调还执行：`node server/test/audit/reaudit-fixture.cjs`；`node node_modules/next/dist/bin/next dev --hostname 127.0.0.1 --port 18100`；两次 `python .../launch.py --mode public --slot rr12 --state-dir output/reaudit-final/python --skip-poll`（第二次带 `--submit-action-json` / `--wait-action`）；正常注册 fixture 的 `/prepare`；ConPTY 下 `python .../launch.py --launcher-url <本地一次性请求> ...`；`npx --yes --package @playwright/cli@0.1.20 playwright-cli -s=reaudit-final run-code --filename server/test/audit/binding-browser.verify.js`。临时请求与私有状态已按确切文件路径清理，不提交其凭证。

## CI 与开放判断

新增 e2e 自动进入现有 required `backend-server-verification`；该任务另外执行 `run-binding-browser.sh`（真实 Python PTY + 浏览器），保留有限结果 artifact，不上传私有状态。脚本 bash 语法检查通过，浏览器安装放在终端等待启动之前。项目锁文件没有升级，TypeORM 使用实际安装的 0.3.31。API 核验参考 [TypeORM transactions](https://typeorm.io/docs/advanced-topics/transactions/)、[PostgreSQL 16 locks](https://www.postgresql.org/docs/16/explicit-locking.html)、[Python redirect handler](https://docs.python.org/3/library/urllib.request.html#urllib.request.HTTPRedirectHandler)。

- **安全修复：** 已确认的四项问题有代码和本地对应证据；存储孤儿清理、存量迁移时长及第三方宿主权限仍有上述边界。
- **产品正向：** public 免预注册、Python 参与、后注册同身份绑定及 public/bound 重启通过。不是只测恶意请求被拒绝。
- **required checks：** 本地通过不等于 GitHub required checks 通过。本轮尚未推送，远端 CI、Linux 整套浏览器驱动、Flutter analyze/测试/build 均未执行；包内 `CI_EVIDENCE.md` 是基准旧记录，不能充当本轮结果。
- **扩大开放：** 当前不能据此宣布生产已可扩大开放。须在私密审查/协调发布安排下完成目标提交的 required checks、迁移预演及另行授权的部署验收。本轮没有部署授权，没有改线上数据库或分支保护。

13 项补充用例的本轮实际状态、证据文件与覆盖边界见 `EXECUTION_RESULTS.json`。用户输入 `REGRESSION_CASES.json` 和原 SHA256SUMS 保持原样；它们的 not_run 是原审计状态，不是本轮实测结果。
