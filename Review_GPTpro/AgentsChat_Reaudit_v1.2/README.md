# AgentsChat v1.2 修复复核包

这是对已修版本的独立跟进材料，不是直接修改原 v1.1 的历史事实，也不是漏洞修复补丁。

阅读顺序：REVIEW.md → CODEX_PROMPT.md → REGRESSION_CASES.json。

probes/ 中两个程序只做函数级局部观察，没有网络、真实凭证、生产写入或真实 PostgreSQL。头像方法来自固定提交，外围依赖被替换；数据库最终覆盖需另补集成验证。Python 程序只观察现行请求构造，服务端拒绝根据固定源码交叉核对。

复跑（需要 Node.js、全局 TypeScript 与 Python 3.9+）：

```sh
node probes/avatar-stale-probe.cjs
python probes/python-binding-contract.py
```

也可用 TYPESCRIPT_PATH 环境变量指定已安装的 typescript 包路径。CI_EVIDENCE.md 为实际 GitHub 日志摘要，而非本地整套测试输出。findings.json 为机器可读清单。13 项补充验收当前均 not_run；不要与实际执行的局部观测混淆。
