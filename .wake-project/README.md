# .wake-project 数据字典

> 本文件由 wake-project 程序自动生成，内容随 schema 版本固化，在所有项目中一致。
> 请勿手工修改（scan 会用程序内置版本覆盖）。
> 当前 schema_version: 9

## 目录用途

`.wake-project/` 保存本项目的结构化元数据，供 agent 快速理解项目而无需重新扫描。
所有 JSON 文件均为 UTF-8 pretty print，写入采用"临时文件 + rename"原子替换。

## 文件总览

| 文件 | 维护方 | 内容 |
|---|---|---|
| project.json | 程序（init/scan） | 项目最小身份信息 |
| scan.json | 程序（scan） | 扫描得到的高确定性事实 |
| tech-stack.json | 程序（scan） | 完整依赖/技术栈清单（体积大，独立于 scan.json） |
| logs/scan.jsonl | 程序（scan 追加） | 扫描历史日志，每行一条 JSON，只追加不覆盖 |

约定：字段缺值时保留为 `null` / 空数组 / 空字符串，结构稳定不变；每个文件都有 `schema_version`。

## ID 溯源规则

每个文件自包含归属标识，可独立溯源：

- `project_id`：唯一生成处是 **project.json**，其余文件全部是透传/引用
- `scan_id`：唯一生成处是 **scan.json**（每次 scan 新建），其余文件全部是引用
- LLM 产物（base-llm.json，由外部脚本生成）在 `_meta` 中引用两者，声明语义基于哪次扫描

## project.json

- `schema_version`：结构版本
- `project_id`：UUID v7（时间有序），创建 project.json 时生成一次，之后稳定不变
- `display_name`：项目目录名
- `root_path`：项目根的 canonical 绝对路径
- `created_at` / `updated_at`：RFC 3339 时间戳；`updated_at` 每次 scan 时刷新

## scan.json

由 `wake-project scan` 生成，全部为确定性事实（程序+规则，无 LLM 推断）。

- `project_id`：项目 ID（透传自 project.json）
- `scan_id`：本次扫描 ID（UUID v7，每次 scan 新建；scan.json 是唯一生成处）
- `scanned_at`：本次扫描时间
- `duration_ms`：本次扫描耗时（毫秒）
- `is_git_repo`：是否拥有**自己的** `.git`（父目录仓库不算；worktree/子模块的 `.git` 文件算）。
  无独立 .git 的目录 init/scan 直接跳过，不生成任何文件
- `git.root`：git 仓库根（可能不同于项目根，见 `git.path_prefix`）
- `git.branch`：当前分支（detached HEAD 时为 null）
- `git.head`：HEAD 短哈希
- `git.path_prefix`：项目根相对 git 根的路径（内嵌项目场景；一致时为空字符串）
- `git.remotes[]`：`{name, url, host, owner, repo}`；host/owner/repo 解析自 url，解析不出为 null
- `git.has_commit_hooks`：是否存在 git commit 钩子（pre-commit 等）
- `git.has_upstream`：当前分支是否配置了 upstream（false 时 ahead/behind 为 null）
- `git.is_detached_head`：HEAD 是否处于 detached 状态（true 时 branch 为 null）
- `git.dirty_file_count`：工作区已修改/暂存文件数（不含 untracked）
- `git.has_untracked`：是否存在未跟踪文件
- `git.ahead_count`：领先 upstream 的 commit 数（无 upstream 时为 null）
- `git.behind_count`：落后 upstream 的 commit 数（无 upstream 时为 null）
- `git.latest_tag`：最近可达的 git tag（无 tag 时为 null）
- `git.submodules[]`：git 子模块 `{path, url, head}`
  - `path`：子模块相对路径；`url`：.gitmodules 中声明的远程地址
  - `head`：子模块当前锁定的短哈希（未初始化时为 null）
- `detected_languages[]`：`{language, files}` 按扩展名统计**编程语言**，按文件数降序
  - 不含 Markdown、Shell、TOML、YAML、JSON、HTML、CSS 等非编程语言
- `manifests[]`：顶层存在的知名 manifest 文件名
- `key_files[]` / `key_dirs[]`：顶层关键文件 / 目录
- `manifests_detail[]`：全部已解析 manifest（含 workspace 成员）：`{path, kind, name, version}`
- `package_managers[]`：包管理器，由 `packageManager` 字段与 lockfile 判定
- `timeline.first_commit_at` / `last_commit_at`：按项目路径限定的 commit 作者时间
  - 内嵌项目不会拿到整个大仓库的历史；fork 时首个 commit 可能来自上游仓库
- `timeline.shallow_clone`：浅克隆标记（true 时 first_commit_at 不可信）
- `timeline.last_file_modified_at`：工作区文件 mtime 最大值（忽略目录除外）
- `timeline.last_core_file_modified_at`：核心文件最后修改时间
  - 基于 `git ls-files`（已跟踪文件），排除根目录直接文件、点目录（如 `.wake-project/`）
  - 极大概率反映项目核心代码的最新变动
- `timeline.local_arrival_at`：项目拉取到本地的**近似**时间
  - 来源见 `local_arrival_source`；`local_arrival_approximate` 恒为 true，勿当精确值
- `totals`：物理规模**估算**（仅供参考）：`{file_count, size_bytes, scope}`
  - `scope` 恒为 `excluding_ignored_dirs`：与语言统计同一遍历口径，不含 .git/node_modules/.venv 等
  - 如需含依赖目录的原始占用请自行用 `du`
- `ignored_dirs[]`：本次扫描实际生效的目录忽略集（审计用，随项目配置文件而变化）
- `manifest_parse_errors[]`：存在但解析失败的 manifest 文件相对路径（如 `packages/broken/package.json`）
- `nested_repos[]`：含独立 `.git` 的子目录相对路径（扫描时跳过，不纳入语言/文件统计）
- `has_ci_config`：是否检测到 CI 配置文件（`.github/workflows/`、`.gitlab-ci.yml`、`Jenkinsfile` 等）
- `warnings[]`：扫描质量警告 `{code, severity, message}`
  - `code`：稳定的 snake_case 短代码（如 `manifest_parse_failed`、`shallow_clone`）
  - `severity` ∈ `info` / `warning`
  - 无警告时为 `[]`
- `scan_completeness`：扫描完整性评估 `{level, reasons}`
  - `level` ∈ `full` / `partial`
  - `reasons`：partial 时的稳定原因字符串（如 `manifest_parse_errors`、`shallow_clone`）

## tech-stack.json

- `project_id` / `scan_id`：归属标识，与 scan.json 同一次扫描
- `tech_stack[]`：`{name, category, version, dev, source}`
  - `name`：规则映射后的通用名（如 Next.js）；未命中规则则为原始依赖名
  - `category` ∈ `framework` / `library` / `tool` / `runtime`
  - `version`：manifest 中声明的版本约束原文；`dev`：是否为开发依赖
  - `source`：声明该依赖的 manifest 相对路径

## logs/scan.jsonl（扫描历史日志）

每次 scan 追加一行 JSON（append-only，不会被覆盖），字段：

- `ts`：扫描时间；`result`：`ok` 或 `skipped_not_git`（目录失去独立 .git 后被跳过，仅在日志已存在时追加）；`duration_ms`：耗时（毫秒）
- `project_id` / `scan_id`：归属标识（skip 条目无 scan_id，为 null）
- `branch` / `head`：当时的 git 状态
- `languages` / `deps`：当次扫描的各项计数
- `files`：当次扫描的文件数估算（口径同 scan.json 的 totals）
- `warning_count`：当次扫描的警告数（= scan.json.warnings.length）
- `completeness`：`full` 或 `partial`（= scan.json.scan_completeness.level）

scan.json 永远只是"最新一次"的快照；历史变化（一天多次扫描、耗时趋势）以本日志为准。

## 阅读注意事项

1. scan.json / tech-stack.json 是**声明层事实**：依赖被声明 ≠ 运行时使用。
2. 语义归类（项目是什么、服务边界、项目间关系）由外部 LLM 分析产物 base-llm.json 承担。
3. 程序生成的文件（含本文件）可被 init/scan 安全重建；base-llm.json 由外部脚本生成，程序不触碰。
