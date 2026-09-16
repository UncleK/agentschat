# 给 Codex：AgentsChat v1.2 修复复核跟进

目标仓库 UncleK/agentschat。审查基准 `7314f18a60843cc72c7566a817e7264fbe12fe4e`。先阅读本包 REVIEW.md、findings.json 与 REGRESSION_CASES.json，对比你实际工作区 HEAD；若代码已经变化，逐项重新验证，不能盲目重复修改。

## 不可改变的产品规则

必须保留 public 免人类预注册接入，未绑定 Agent 正常按策略参与；人类后来注册后绑定原有 Agent ID 并保留全部既有身份/历史/权限语义。bound 仍是另一条正常入口。不能关闭 public、强制先注册、全改只读、清空历史或创建替代身份来修问题。

## 执行顺序

1. RR-01：先用真实 PostgreSQL 与可控 barrier 复现头像完成/拒绝分支的旧实体回写。特别覆盖并发 emergency-stop、合法绑定及第二次上传。对象 I/O 可在事务外，发布指针应在短事务内锁定/重读/CAS，只更新头像字段，保留最新策略和 owner。排查其它长 await 后完整 save(AgentEntity) 的路径。报告中的局部 mock 只证实旧 save 参数，不能替代你的数据库测试。
2. RR-02：区分 bootstrap claimToken、账户绑定 challenge、当前 fed bearer。实现初始化授权的持久一次性消费、并发初始化保护、连接轮换/断开与撤销语义。明确丢响应后的安全幂等恢复。正常持有者重启仍复用既有身份，不需要预注册。测试旧 token 在首次接入/轮换/主动断开后均不能夺回连接。
3. RR-03：升级 skills/agents-chat-v1/adapter/launch.py 的可信管理绑定路线与发布文档。服务器已正确拒绝社交 claim.confirm，不得回滚此防护。执行真实 Python adapter 到测试后端的 public→参与→后来注册→同身份绑定，而非仅用 backend fixture。
4. RR-04：补普通用户浏览器/设备式一次性授权与终端明确批准的衔接。限定 purpose/account/agent/request/expiry；不让用户从 DevTools 取完整 Cookie，不把长期 human bearer 放入 launcher、日志或 Agent 聊天，也不让公共消息、模型工具或 stdin 管道冒充原控制端授权。

## 交付和验证

保持当前已修的白名单、图片重编码、SSRF 地址固定、持久 action/outbox、来源限流、标准 WS、安全存储和分支门禁。为确认问题先补失败用例，再最小范围修复。新增测试纳入 required CI；记录修改前后结果、实际命令、commit、未执行项与残余条件。对比 13 项补充验收，但不要把“提出了测试”写成“通过了测试”。新增授权流程需至少一个真实浏览器/CLI 连通案例，非合成 token 的单元模拟。

仅在隔离环境使用合成账户和资源；不在生产重放旧凭证或改归属。此提示词不是部署授权，不可自动发布、改生产数据库或公开发布可利用细节。保留有意义断言，不通过删除/skip 断言或放松安全策略使 CI 变绿。
