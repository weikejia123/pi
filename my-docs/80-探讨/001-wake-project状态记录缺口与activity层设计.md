# wake-project 状态记录缺口与 activity 层设计探讨

> 探讨时间：2026-07-22
> 探讨性质：需求边界澄清 + 方案设计 + 可行性验证 + 价值审视
> 参与方：用户 × agent

---

## 一、探讨背景

`.wake-project/` 已有程序扫描（scan.json / tech-stack.json）和 LLM 扫描（base-llm.json）产物。从第一性原理出发——假设一个资深开发者搁置项目 1 个月后回来，想了解项目情况进行二开/借鉴/提取模块——审视当前扫描信息还缺什么。

## 二、探讨点演进（三轮边界澄清）

### 第一轮：agent 初判，列出大量缺口

agent 从"资深开发回归认知恢复路径"出发，列出 14 项缺口，涵盖入口命令、环境前置、模块依赖图、git 活动、测试现状、CI 配置、文档地图、技术债、API surface、fork 差异等。

### 第二轮：用户纠正边界——"状态记录"而非"使用说明"

> 用户："这个项目怎么动，应该是项目文档记录的，我们要的是状态记录，不是项目使用说明。"

**关键边界界定**：
- 项目文档的职责：怎么跑、怎么构建、scripts、env、CI 怎么发、API 怎么用 → "教人怎么做"
- `.wake-project` 的职责：某个时间点上项目客观状态的快照，以及随时间的变化 → "项目现在是什么样"

按此边界重筛，agent 收窄为四类纯状态缺口：活动状态（git 动态）、分布状态、差异状态、语义状态回填。

### 第三轮：用户再收窄到两个核心诉求

> 用户：
> 1. 上游同步状态（如果有上游/fork 项目），简单记录落后多少
> 2. 最主要的是我们自己对这个项目做过什么，要有时间线倒序的记录，而且不仅是记录，是分析总结（针对当前单个项目）

**最终定位**：`.wake-project` 要补的不是"项目客观状态全集"，而是"**我们与这个项目的关系档案**"——我们改过什么、改动的语义总结、我们相对上游的位置。这是单项目视角的、属于"我们"的状态记录。

---

## 三、最终结论：activity-llm.json 设计方案

### 文件归属

新增 `activity-llm.json`（对标 base-llm.json 命名），程序提取 + LLM 总结的混合产物，职责单一，不污染 agent.json 的语义层。

### Schema 设计

```json
{
  "schema_version": 1,
  "project_id": "...",
  "based_on": { "project_id": "...", "scan_id": "...", "head": "..." },
  "analyzed_at": "...",

  "upstream_sync": {
    "remote": "upstream",
    "upstream_default_branch": "main",
    "ahead_count": 20,
    "behind_count": 0,
    "upstream_latest": { "sha": "...", "message": "...", "at": "..." },
    "note": "behind 基于最近一次 fetch 的 ref，非实时"
  },

  "our_commits": [
    {
      "sha": "...",
      "at": "...",
      "author": "...",
      "message": "...",
      "files_changed": 1,
      "scope": "my-pi-scripts"
    }
  ],

  "summary": {
    "total_commits": 20,
    "span": { "first_at": "...", "last_at": "..." },
    "themes": [
      {
        "theme": "...",
        "commits": 8,
        "representative": ["sha..."],
        "summary": "..."
      }
    ],
    "one_liner": "...",
    "delta_since_last_scan": {
      "previous_analyzed_at": "...",
      "new_commits_count": 2,
      "dirty_files_count": 3,
      "summary": "自上次扫描以来新增改动的一句话总结"
    }
  }
}
```

### 三层分工

| 层 | 内容 | 产出方 |
|---|---|---|
| `upstream_sync` | ahead/behind 计数 + 上游最新一条 | 程序（git） |
| `our_commits` | 倒序 commit 清单 + scope 自动推断 | 程序（`git log upstream/main..HEAD` + 改动目录前缀） |
| `summary.themes` / `one_liner` | 主题归类 + 一句话总结 | LLM（基于 commit 清单生成） |
| `summary.delta_since_last_scan` | 与上次扫描的增量总结 | 程序算 sha 差集 + LLM 总结（无上次扫描或无新增时为 `null` / 硬编码） |

### 关键设计点

1. `upstream_sync` 是**条件字段**：无 upstream remote 的项目该字段为 `null`。
2. `scope` 自动推断：程序读 `git log --name-only`，取每个 commit 改动文件的一级目录频次（packages 下取二级）。
3. `behind` 标注近似性：扫描时不强制 fetch，基于已有 ref，`note` 字段说明。
4. 倒序 + themes 双视图：`our_commits` 是流水（倒序），`summary.themes` 是语义聚合——搁置回来先看 `one_liner` 和 `themes`，要细节再翻 `our_commits`。
5. `delta_since_last_scan` 是**增量头条**：`one_liner` 覆盖从 baseline 起的全弧线，`delta_since_last_scan` 聚焦"自上次扫描以来"的新增——这是搁置回归时信号密度最高的字段。程序用 sha 差集计算新增 commit + `git status --porcelain` 采集工作区未提交改动（无 commit 不代表无文件变动），LLM 只做语义总结。无上次扫描时为 `null`；有上次扫描但无新增 commit 且无工作区改动时硬编码"自上次扫描无新增 commit，工作区无改动"；有任一变化时请 LLM 总结。两次扫描间隔可能很短时，提示 agent 如实简短描述，不夸大变化。
6. **agent 自主读取背景**：不在 PROMPT 内联 base-llm.json 等背景字段，而是用 `--tools "read,ls,find"` 让 agent 按需自主读取 `.wake-project/` 下的 JSON。只做文字提醒（含 prompt 注入边界声明）+ jq 结构校验，不过度限制 agent 的阅读自由度。覆盖写入时若检测到上次扫描结果，提醒 agent 先阅读作为状态延续输入。

---

## 四、可行性验证（agent 独立采集，未调 pi）

### 程序层（git 提取，全部成功）

**upstream_sync**：
- remote `upstream` → `earendil-works/pi`，default branch `main`
- `ahead_count: 20`，`behind_count: 0`（当前已同步上游）
- upstream_latest: `c901d9a87` | 2026-07-21 | Mario Zechner | "docs: audit unreleased changelogs"

**our_commits**：20 条全部提取，scope 分布：

| scope | commits |
|---|---|
| `.wake-project` | 7 |
| `my-pi-scripts` | 5 |
| `my-docs` | 4 (+2*) |
| `(root)` | 2 |

### 发现的边界 case（实现须处理）

scope 推断对**中文路径**出错：git 默认 `core.quotepath` 会把非 ASCII 文件名转义成 `"my-docs/00-\351...` 并加引号，导致目录分割错乱。修复一行：`git -c core.quotepath=false`。

### LLM 层（agent 基于 commit 清单分析，已产出）

20 条 commit 归成 4 个主题：

| Theme | commits | 代表 sha | 总结 |
|---|---|---|---|
| wake-project 元数据工具链建设 | 9 | 7d5394090, f34ea646d, 7e9149d7a, 9f7c63215, 3a1420a46 | 从零搭建扫描/分析工具链：单项目分析(wake-base-llm.sh)、批量扫描(wake-scan-all.sh)、状态分析(wake-state-agent.sh)，含元数据回写与 JSONL 日志 |
| pi 机制逆向分析文档 | 5 | 9dbd42329, 68273c62d, 48d4b0a8a | 逆向分析 hook 系统(24事件+能力分类+全局/项目级配置)、首屏 LLM payload、ollama 接入、tools context |
| 自动扫描维护提交 | 3 | 37398b228, 2ed4be5d7, 4b6f210d2 | wake-project 扫描工具自动产生的元数据更新（auto-app-wp: scan update），非人工编辑 |
| 上游同步与部署 | 3 | 76857dd34, a937c19cf, 181351b19 | 合并 upstream main 到 wkj-dev、修正合并后 orchestrator→server 引用、新增 wkj-dev 部署脚本 |

**one_liner**：2026-07-20~22 两天内围绕 wake-project 工具链从零搭建 + pi 机制逆向分析两条主线，配套上游同步与部署，未触碰 packages 核心代码。

---

## 五、价值审视：组合信息支撑的四类决策

核心判断：**把"项目是什么"（scan + base-llm）和"我们与项目的关系是什么"（activity）拼成完整图景，支撑接续、同步、剥离、投入四类决策。** 单独任何一份信息都给不出这些结论，价值产生于组合。

### 决策1：接续——"我上次做到哪了"

信息组合：activity.one_liner + themes + 最近 1 条 commit

结论：工具链三脚本已齐备，进入收尾调优阶段（最近 commit 是参数微调"修改失败间隔为180秒"）。5 秒恢复上下文，不必翻 git log。

### 决策2：同步——"要不要/能不能 sync 上游"

信息组合：upstream_sync（ahead=20 / behind=0）+ our_commits 的 scope

结论：behind=0 是同步成本最低窗口；上游刚 audit changelogs（发版前兆）；我们改动几乎不碰核心，冲突概率极低。把"sync 还是不同步"从拍脑袋变成基于偏离度和冲突风险的判断。

### 决策3：剥离——"我的改动能不能独立提取/移植"（最有价值的组合洞察）

信息组合：activity.scope 分布 + base-llm.critical_paths

结论：20 个 commit 里 19 个落在 `.wake-project` / `my-pi-scripts` / `my-docs` / 根目录，**只有 1 个 commit 碰了 `packages/ai`**（且是初步分析改动）。

→ **我们的工作是"外挂式"的，几乎不侵入核心**。我们 accumulated 的资产（工具链 + 分析文档）可以几乎无损地从当前 fork 剥离，移植到 pi 的任意新版本。

这是单看 scan 或单看 activity 都得不出的结论——必须把"我们改了哪"和"核心在哪"叠在一起才浮现。直接支撑"二开/借鉴/提取模块"的信心：可移植性高，不必绑死在这个 fork 版本上。

### 决策4：投入——"还值不值得继续"

信息组合：upstream 活跃度 + 我们的投入密度 + scan.timeline

结论：上游昨天还在提交（活跃维护），我们两天密集投入 20 commit，工作刚到收尾调优阶段。项目健康、上游在动、势头正续 → 值得继续。

---

## 六、核心结论

1. **边界**：`.wake-project` 是"状态记录"不是"使用说明"；使用说明归项目文档。
2. **定位**：activity 层填补的空白是把"项目状态"从客观事实变成"**我们与这个项目的关系状态**"——后者才是搁置回归做决策的依据。
3. **价值本质**：单看 scan 看不到我们自己，单看 activity 不知道改动位置意味着什么，组合后才浮现"外挂式可移植"这类决策洞察。
4. **可行性**：agent 不依赖 pi CLI，仅用 git + 自身分析即可完整产出 activity-llm.json 三层信息。唯一实现细节是中文路径需 `git -c core.quotepath=false`。

---

## 七、待办/未决

- [x] activity-llm.json 已落盘：脚本 `my-pi-scripts/wake-activity.sh` 实现并测试通过（两次测试：无上次扫描 / 有上次扫描，均产出有效 JSON）。
- [x] scope 推断的中文路径处理：已加 `git -c core.quotepath=false`。
- [x] `delta_since_last_scan` 增量字段已实现：程序算 sha 差集 + LLM 总结 + 无新增/无上次扫描的 null 边界。
- [x] agent 自主读取背景：用 `--tools` + 文字提醒替代内联，附 prompt 注入边界声明。
- [ ] agent.json 语义层（terminology/relations）仍全空，是独立于 activity 的另一缺口，本次未展开。
