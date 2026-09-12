# 目录整合记录 — 2026-09-12

唯一保留的工作目录为 `E:\VP\agents_chat_release_candidate`。本记录只说明源码目录、Git 历史与本地资料的整合，不代表 Web 重构或应用测试已完成。

## 基线选择

通过提交图、工作区状态和逐文件 Git blob 比较选择基线，没有使用目录修改时间判断新旧。

| 原目录 | 核实结果 | 处理 |
| --- | --- | --- |
| `agents_chat_release_candidate` | 审计起点为 `main` / `adc33e85`；已有首页改动由主任务先保存为 `e48da748` | 保留 |
| `agents_chat` | `main-legacy` / `d3e33cc1`，原工作区干净；与 main 共有祖先 `97881a0e`，分歧计数 86 / 2 | 保留历史与独有资料后移除 |
| `agents_chat_release_candidate_deploy_src` | 633 个受跟踪普通文件完整，43 个不同内容全部在已有 Git 历史中，独有 blob 为 0 | 移除旧部署副本 |
| `agents_chat_team_snapshot_20260405T131816Z` | `validation-snapshot` / `ed4458f`；主工作区及三个 worker 全部干净；主干缺少的文件仅八张 golden failure 图片 | 保存 bundle、图片和工具历史后移除 |
| `agents_chat_backups` | 发布前 patch、源码快照、ZIP 与六张图片，无 Git 仓库 | 完整归档后移除根目录 |

截图中的 `agents_chat备份` 在本次实际盘点时不存在。

部署副本与原 candidate 的 `.git` 文件曾指向同一个 linked worktree 管理目录。它不是独立工作树；共享 index 会影响普通 `git status` 的判断，因此另行重新计算了所有普通受跟踪文件的 blob 哈希。

## 保留的资料

本地归档位置为 `.local-archive/20260912/`，已通过本地 Git exclude 与项目 ignore 排除，不应提交或发布其中的本地配置。

| 归档分组 | 文件数 | 字节数 |
| --- | ---: | ---: |
| `release-backups` | 240 | 146862302 |
| `legacy-materials` | 72 | 53896977 |
| `legacy-local-config` | 5 | 1111 |
| `validation-snapshot/golden-failures` | 8 | 687305 |
| `legacy-ignored-materials` | 86 | 38662754 |
| `snapshot-tool-history` | 9 | 9732 |
| 验证快照 Git bundle | 1 | 1383186 |
| **总计** | **421** | **241503367** |

72 个旧分支独有文件包括 Stitch HTML/PNG、原始 emoji 图片、早期规格说明、旧项目规则和 Android/agentmoji 辅助文件。额外保存了历史 Agent 报告、临时设计 HTML/图片与字体源文件。旧服务端本地配置与当前配置不同，因此单独保留，没有覆盖当前配置。

每个复制文件均核对源文件与归档文件的字节数和 SHA-256；完整清单在 `archive-manifest.json`。快照 `repository.bundle` 记录完整历史，`git bundle verify` 已通过。

六个 `research/*` 参考仓库原地移动到保留目录的同名位置。移动前后 HEAD 一致，移动后各仓库的工作目录均位于 canonical 下，均使用自己的 `.git`，tracked 修改为 0。记录在 `research-moves.json` 和 `research-verification.json`。

## Git 独立化

原 candidate 的 `.git` 依赖 `E:/VP/agents_chat/.git/worktrees/agents_chat_release_candidate`，因此不能直接删除旧 `agents_chat`。

1. 将原 common Git 目录的对象、refs、配置和日志复制到归档区暂存目录，排除旧 worktree 注册信息与 fsmonitor 运行态。
2. 与主任务协调暂停 Git 写操作；源码文件编辑继续。
3. 最终同步 common Git 数据，再复制当前 linked worktree 的 HEAD、index、HEAD reflog 与当前 Git 状态文件。
4. 保存原 `.git` 指针，将暂存目录移动为 canonical 的独立 `.git` 目录。
5. 核对 HEAD、分支、全部 10 个 refs 和 index SHA-256；执行完整 `git fsck --full`。
6. 验证成功后恢复主任务 Git 操作，再清理旧目录。

切换时 HEAD 为 `e48da7485e06b7b786100dca811e5b0257318e34`，分支为 `codex/native-web-rebuild`，均未改变。index SHA-256 为 `C07FD5EE600F6046167D66169B3C449072551C7FE6BB094A8A8208B83A6DB674`，切换前后相同。`git fsck --full` 返回 0；`git rev-parse --git-common-dir` 返回 `.git`，`git worktree list` 只列出 canonical。

详细证据在 `git-migration-check.json`、`git-fsck.txt` 和 `original-worktree-git-pointer.txt`。旧分支仍保留在独立仓库中；没有把过期实现覆盖回当前代码，也没有在整合任务中提交或切换分支。

## 目录清理

清理仅针对上表四个明确的旧绝对路径。每个目标在执行前核对为 `E:\VP` 的直接子目录且不等于 canonical。删除遍历遇到 reparse/junction 时只解除链接，不进入链接目标；普通目录逐层删除。

四个旧根目录均已移除；最终复核（含隐藏目录）确认 `E:\VP` 下只剩 `agents_chat_release_candidate`。

| 已移除目录 | 普通文件 | 普通目录 | 仅解除的链接 |
| --- | ---: | ---: | ---: |
| `agents_chat_backups` | 240 | 82 | 0 |
| `agents_chat_release_candidate_deploy_src` | 259335 | 30720 | 0 |
| `agents_chat_team_snapshot_20260405T131816Z` | 1813 | 751 | 1 |
| `agents_chat` | 58625 | 9533 | 2070 |

合计移除 320013 个普通文件、41086 个普通目录；2071 个 reparse/junction 仅解除链接，没有进入目标。所有四项结果均无错误。

清理过程中曾为主任务安装与构建暂停原清理进程，收到恢复指令后继续同一进程，没有重复发起并行删除。新的 Web 依赖目录不在本次清理范围内。

最终 `git-common-dir` 仍为 `.git`，工作树列表仍只有 canonical，归档仍处于 Git ignore 范围。执行结果与最终核验分别位于 `directory-cleanup-results.json`、`directory-final-check.json`。
