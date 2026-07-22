# activity-llm.json v2 字段说明

> schema_version: 2

## 元数据字段（程序层生成）

| 字段 | 类型 | 来源 | 作用 |
|------|------|------|------|
| `schema_version` | number | 程序 | 结构版本号，当前为 2。消费者据此判断字段布局 |
| `project_id` | string | 程序 | 项目唯一标识（uuid），来自 scan.json |
| `based_on` | object | 程序 | 本分析基于的扫描快照：project_id + scan_id + HEAD sha |
| `analyzed_at` | string (ISO8601) | 程序 | 本文件生成时间戳 |
| `total_commits` | number | 程序 | 相对 baseline 的独有 commit 总数（已过滤 auto-app-wp） |
| `span` | object 或 null | 程序 | commit 时间范围：`{first_at, last_at}`。无 commit 时为 null |
| `previous_analyzed_at` | string 或 无 | 程序 | 上次扫描时间（仅当存在旧 activity-llm.json 时有此字段） |

## 上游同步字段（程序层生成，仅 fork 项目）

| 字段 | 类型 | 作用 |
|------|------|------|
| `upstream_sync.remote` | string | 固定为 "upstream" |
| `upstream_sync.upstream_default_branch` | string 或 null | upstream 的默认分支名 |
| `upstream_sync.ahead_count` | number | 本地 HEAD 领先 upstream 多少 commit |
| `upstream_sync.behind_count` | number | 本地 HEAD 落后 upstream 多少 commit（基于 fetch 结果） |
| `upstream_sync.upstream_latest` | object | upstream 最新 commit 的 sha/at/message |
| `upstream_sync.note` | string | "behind 基于最近一次 fetch 的 ref，非实时" |

## Commit 明细字段（程序层生成）

| 字段 | 类型 | 作用 |
|------|------|------|
| `our_commits[]` | array | 独有 commit 数组，每条包含 sha/at/author/message/files_changed/scope |

## LLM 归纳字段（LLM 生成 + 程序归一化）

### 全局

| 字段 | 类型 | 作用 |
|------|------|------|
| `one_liner` | string | 整组改动的一句话总结。概括方向与重心 |
| `theme_count` | number | 主题数量（2-5） |
| `delta_summary` | string 或 无 | 与上次扫描相比的变化小结。仅当有新 commit 或工作区有改动时出现 |

### 每个主题一组扁平字段（theme_N, N=1~5）

| 字段 | 类型 | 作用 |
|------|------|------|
| `theme_N` | string | 第 N 个主题的名称（如 "本地化裁剪及修复"） |
| `theme_N_commits` | number | 该主题包含的 commit 数量 |
| `theme_N_shas` | array[string] | 该主题的代表性 SHA 列表。程序层从 LLM 的逗号分隔字符串归一为数组 |
| `theme_N_summary` | string | 该主题改动的语义归纳，不是 commit message 的罗列 |

**排序规则**：theme_1 的 commit 数最多，theme_N 依次递减。commit 数相同时按代码核心程度排序。

**仅输出有值的字段**：当 theme_count < 5 时，不用的 theme_5/theme_5_commits/theme_5_shas/theme_5_summary 不会出现在输出中。

## 结构示意

```json
{
  "schema_version": 2,

  "project_id": "uuid",
  "based_on": { "project_id": "...", "scan_id": "...", "head": "abc1234" },
  "analyzed_at": "2026-07-22T18:37:24+0800",
  "previous_analyzed_at": "2026-07-22T17:00:00+0800",

  "upstream_sync": { "remote": "upstream", "ahead_count": 26, ... },
  "our_commits": [ { "sha": "...", "message": "...", ... } ],

  "total_commits": 24,
  "span": { "first_at": "2026-07-20", "last_at": "2026-07-22" },

  "one_liner": "整组改动的一句话总结",
  "theme_count": 4,
  "theme_1": "核心代码改动",
  "theme_1_commits": 8,
  "theme_1_shas": ["sha1", "sha2", "sha3"],
  "theme_1_summary": "该主题的语义归纳",
  "theme_2": "文档建设",
  "theme_2_commits": 5,
  "theme_2_shas": ["sha4", "sha5"],
  "theme_2_summary": "...",
  "theme_3": "工具链",
  "theme_3_commits": 3,
  "theme_3_shas": ["sha6"],
  "theme_3_summary": "...",

  "delta_summary": "本次无新增 commit，工作区有 3 个未提交改动"
}
```

## v1 → v2 变更摘要

| 变化 | v1 | v2 |
|------|----|----|
| summary 嵌套 | `summary.themes[]` 数组 | 去掉 summary 层，扁平 `theme_N` 字段 |
| themes 结构 | 嵌套数组 + foreach 穿透校验 | 扁平字段，只验顶层 |
| theme_N_shas | `representative` 数组 | `theme_N_shas` 数组（包含所有代表性 SHA） |
| delta | `summary.delta_since_last_scan.{}` 嵌套对象 | 顶层 `delta_summary` 字符串 + `previous_analyzed_at` |
| null 字段 | theme_5 固定输出 null | 用 `del(..|nulls)` 清除，无空字段 |
| commits 类型 | 校验要求 number | 程序层做 `tonumber? // .` 宽容归一 |
