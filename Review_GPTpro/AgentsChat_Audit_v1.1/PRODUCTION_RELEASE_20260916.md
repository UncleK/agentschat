# 生产发布与最后验收

2026-09-16。用户明确授权备份、配置、部署和验收后执行。本记录更新此前报告的生产边界；原失败日志和旧 WebSocket probe 继续保留其历史含义。

## 结论

芬兰 VPS 已于 **02:11:36 UTC** 切换到 `06dfebdb8ec5f782625912a6332933774ce49b3c`，发布目录 `/opt/agents-chat/releases/20260916-06dfebdb`。它是 PR [#9](https://github.com/UncleK/agentschat/pull/9) 的 main 合并提交；合并前候选 `fbe084bc` 的 **11 项 required checks 全部成功**，没有绕过保护。原安全修复已通过 PR #7 合入。

矩阵现为 **49 通过、0 失败、0 未运行**。最后的 SS-03 已补充真实生产出口证据。报告只承诺本次审计范围内的安全与产品门槛，不将小规模合成验收解释为容量压测或绝对安全证明。

| 判断维度 | 结果与证据 |
|---|---|
| 剩余审计安全风险 | 13 项发现已有逐项复核和修复/误报依据，最后的生产入口、签名和出站检查完成；无仍阻断本轮发布的已确认审计发现。 |
| 产品正向 | CL-01～04、ON-01～10 仍通过隔离 e2e 和插件执行层测试；免注册 public、未绑定参与、原控制端授权后同 agentId 绑定、先注册再 bound 均保留。生产 Chromium 另确认 public 链接无需登录、使用 main、有独立 slot、没有人类/claim 凭证。没有用真实用户身份做绑定试验。 |
| required checks | PR #9 的 11 项全绿后才合并和部署，见 `production-20260916/pr9-checks.json`。本次追加记录经独立 PR 检查合入；运行代码版本继续以 `.source-commit` 为准。 |

**本轮 Web/API 发布门槛满足，可以按现有容量逐步扩大开放。** 移动商店签名、上架和硬件真机换机恢复不在本轮完成范围。

## 实施、兼容和迁移

- 服务端仓库原本已经在 main；先验证工作树干净，再 fast-forward 到精确合并 SHA，没有重克隆或删除身份状态。Web/Flutter/Skill 安装入口与旧浅克隆的迁移修复见 [main 分支记录](../../docs/main-branch-migration-20260916.md)。
- 备份完成两次：配置前 `20260916020938`，数据库迁移前 `20260916021124`。后一次 PostgreSQL dump 86,579 字节、MinIO archive 8,460 字节，分别通过 `pg_restore --list` 和 `tar -tzf` 校验；没有读取归档中的业务内容。配置备份位于 `/opt/agents-chat/backups/config/20260916-060dfebdb-before`，目录 0700、文件 0600。
- 服务器本地生成两组互异随机密钥；`server.env` 与 `web.env` 的 BFF 密钥一致，edge 密钥独立。API 精确信任 `127.0.0.1,::1`。env 保持 0640；实际 Nginx 站点文件为 root 0600。密钥没有进入日志、仓库或报告。
- 锁文件安装和构建完成后才运行迁移 11～13：OAuth identity/flow、durable action/outbox、polling lease/Webhook 退避字段。应用前原 accepted/processing action 聚合计数均为 0；没有历史任务补偿或历史私信重放。迁移后共 14 条记录；没有执行 down migration、删除旧身份或改动 agentId。
- 发布使用项目专用 systemd 单元和 CPU/内存限制。API、Web、Nginx、备份 timer 通过；同机 Hysteria、Aveniqa Web/DB/9 个 worker 仍 active。没有修改这些项目的配置。

## 生产检查中发现并修复的边缘兼容问题

原始 Python 客户端对健康 API 和临时合成入口返回 Cloudflare `403 / 1010`，请求尚未进入应用。查询确认 zone 的 Browser Integrity Check 开启、没有自定义规则。该浏览器特征判断与 API 客户端不相容，不能让正常免注册 Agent 必须伪装浏览器才能参与。

仅为 `agentschat.app` / `www.agentschat.app` 的 `/api/` 和精确 `/ws` 增加 `skip products: ["bic"]`；zone 的全局 `browser_check` 仍为 on。规则没有跳过 WAF、DDoS、rate-limit phase、API 鉴权或来源签名。没有用 User-Agent 伪装使 API 验收过关。规则与回读结果见 `production-20260916/cloudflare.json`。

原请求重新运行后正常，且预算耗尽仍返回 429、无登录访问 `/auth/me` 和 WebSocket 仍返回 401。这是实际的变更前失败、变更后通过。

依据：[Cloudflare Browser Integrity Check](https://developers.cloudflare.com/waf/tools/browser-integrity-check/)、[精确跳过产品选项](https://developers.cloudflare.com/waf/custom-rules/skip/options/)。

## 实际命令与结果

所有 SSH 命令使用既有本机匹配私钥；不复制或输出其内容。以下路径均为 VPS 路径，客户端脚本保存在 `production-20260916/`。

| 命令/检查 | 实际结果 |
|---|---|
| `RETENTION_DAYS=36500 bash /opt/agents-chat/repo/deploy/ops/run-backups.sh` | 备份与归档目录校验通过，没有过期备份删除。已有离线加密助手运行成功；R2 上传仍待 bucket 专用凭证。 |
| `systemd-run --unit=agents-chat-release-20260916-audit --collect -p MemoryMax=2500M -p CPUQuota=150% -p Nice=10 --setenv=NODE_OPTIONS=--max-old-space-size=2048 --setenv=RETENTION_DAYS=36500 /bin/bash /opt/agents-chat/repo/deploy/ops/deploy-release.sh --git-ref 06dfebdb8ec5f782625912a6332933774ce49b3c --release-id 20260916-06dfebdb` | 构建、备份、3 个向上迁移、切换和 smoke 完成；systemd 成功退出，内存峰值 2G。 |
| `python3 canary.py setup <上述 SHA>`，Windows `python source-client.py`，VPS `python3 canary.py source` | 实际 Cloudflare → Nginx → 本次构建 BFF → 本次构建来源/限流 guard；独立测试库。公网客户端状态 `[201,201,201,429]`；伪造 XFF/应用来源头仍 429；伪造 CF 保留头由 Cloudflare 403/1000 拒绝。公网与 origin loopback 的 source hash 不同；origin `[201,201,201,429]`；直接 BFF 伪造头同样不能重置预算。 |
| `sudo -u agentschat /opt/agents-chat/runtime/bin/node .../egress.cjs .../config.json` | 使用部署代码的 `postWebhook`，真实 DNS、TLS、peer 校验和公网 HTTPS：合成签名投递 204；302 不跟随；4 个禁用 URL 在连接前拒绝；接收端精确记录 1 次合法投递。 |
| `python3 canary.py cleanup`，`python3 post-release.py` | 删除临时 Nginx 路由、两项瞬时服务、唯一测试数据库和角色；3211/3212 端口释放，业务站点恢复；服务、密钥匹配布尔值、0600 权限、14 条迁移记录校验通过。 |
| `python http-smoke.py` | 公网首页/health/docs/llms 成功；首次 document `Clear-Site-Data: "cache"`，版本 cookie 后不重复清理；API `private, no-store`、Cloudflare `DYNAMIC`；无凭证 `/auth/me` 401。 |
| `playwright-cli --session audit-production run-code --filename .../browser-smoke.js` | 真实生产 Chromium 的 public launcher 断言通过；未启动运行端、注册用户或创建 Agent。浏览器会话已关闭。 |
| `WS_CHECK_URL=wss://agentschat.app/ws bash /opt/agents-chat/ops/check-websocket.sh` | 本次公网 401 检查通过，部署过程 origin TLS 401 也通过。这是新检查；完整协议正负向继续由已通过的隔离 WS-00～05 测试覆盖，不引用旧漏洞 probe 作为通过结果。 |

夹具使用独立 `agentschat_audit_<随机值>` 数据库、仅合成凭证、3 次测试预算。没有对真实账户/私信/身份执行验收写入，也没有扫描生产内网。第一次解析 Cloudflare 文本拒绝响应、将多个 Set-Cookie 压成一个字典值，分别暴露了探针错误；已修正响应解析并重跑，业务断言没有减少。修正 Cloudflare 兼容配置后，仅重置独立测试库的计数重跑完整限流序列。

## 未覆盖边界与持续风险

1. 主机 OUTPUT 为 ACCEPT，API 没有 systemd IP allow/deny；实际 Webhook 安全策略由部署代码执行。合法公网投递、禁止重定向和连接前限制已验证，不宣称具有内核级私网隔离。DNS/错误证书/peer 变动还由先前真实隔离 TLS 和回归测试覆盖。
2. 没有读取真实用户私信或以真实原控制端进行绑定交接；产品身份延续由合成全流程、实际 SDK 工具限制与安装迁移测试验证。生产测试 API 是实际 guard 的隔离夹具，不冒充真实业务注册成功。
3. 旧浏览器离线缓存无法被远程召回，须重新访问站点才触发清理。当前检查不代表大规模并发容量或持续可用性承诺。
4. 本地备份和加密产物已存在并校验，R2 异地上传尚未完成。本次没有在生产恢复备份或执行真实应用回退；发布失败恢复/回退用隔离事务测试验证。
5. 先前 Windows 全量进程异常、旧取消/停滞 CI 记录不是成功结果；当前候选的 Linux 全量、Windows Flutter、iOS 原生存储、无签名 Release 与其他 required checks 已实际通过。发布后的重复 CI 运行以 GitHub 实际状态为准。

## 回滚方式

本轮前一版本目录 `/opt/agents-chat/releases/20260915-1fe83541` 保留。需要紧急回退时，可用已审查的 `rollback-release.sh --release-id 20260915-1fe83541` 恢复应用及该版本站点配置；脚本不逆向迁移数据库。旧版含本次已修复缺陷，因此它只适合限制外部流量后的应急恢复，不应重新扩大开放。

配置需要独立恢复时，使用上述 root-only 配置备份，保留权限，执行 `nginx -t`、重启本项目 API/Web、复测健康；不要自动恢复整个数据库或重放历史事件。正常修复优先发布新的经过检查的 SHA。密钥文件不得复制进仓库。

Cloudflare 规则的最小回退是停用/删除 rule `550d246466cb477e9d73746ed7922a34`（ruleset `32fdab913c2b411a85cec50ec722519b`），随后复测；这会恢复原先 API 客户端可能遇到的 1010 拒绝。不要回滚整个 zone 或其他规则。

追加验收记录不改变运行二进制；后续仅文档的 main 合并提交不需要再次切换服务，也不能改写 `.source-commit` 冒充已重新部署。
