# Pi Agent TUI 启动时注入上下文的工具分析

## 概述

当 pi 以 TUI 模式启动并输入第一条消息时，LLM 的 system prompt 中会注入以下内容。理解这些内容的构成有助于解释首轮消息的响应质量。

## 一、注入的层级结构

system prompt 由 `buildSystemPrompt()` 函数构建（`core/system-prompt.ts`），按以下顺序拼接：

```
1. Agent 身份声明（固定文本）
2. Available tools 列表（含每工具一行 promptSnippet）
3. Guidelines（来自工具的 promptGuidelines + 默认规则）
4. Pi 文档路径说明
5. appendSystemPrompt（来自资源加载器）
6. <project_context> — AGENTS.md / CLAUDE.md 文件内容（如有）
7. Skills 区块（如有）
8. Current working directory
```

## 二、注册但非全部激活的 7 个 Built-in 工具

Pi 核心代码定义了 7 个工具（`core/tools/index.ts:83` `ToolName = "read" | "bash" | "edit" | "write" | "grep" | "find" | "ls"`），**默认只激活 4 个**：

### 默认激活的 4 个工具（出现在 system prompt 中）

| 工具 | 功能描述 | 参数 JSON Schema |
|------|---------|-----------------|
| **read** | 读取文件内容。支持文本和图片(jpg/png/gif/webp/bmp)。文本输出截断至 200 行/100KB，支持 offset/limit 分段读取。 | `{ path: string, offset?: number, limit?: number }` |
| **bash** | 在当前工作目录执行 bash 命令。返回 stdout/stderr，输出截断至最后 200 行/100KB（截断时保存到临时文件）。可选 timeout 参数。 | `{ command: string, timeout?: number }` |
| **edit** | 精确文本替换编辑。每处 edits[].oldText 必须在文件中唯一、不重叠。支持单次调用多 edits，diff 预览。 | `{ path: string, edits: [{ oldText: string, newText: string }] }` |
| **write** | 写入/覆盖文件。自动创建父目录。 | `{ path: string, content: string }` |

### 已注册但默认不激活的 3 个工具（在 registry 中，但不在 system prompt）

| 工具 | 功能描述 | 激活条件 |
|------|---------|---------|
| **grep** | 内容搜索。支持正则/字面量、glob 过滤、忽略大小写、上下文行数、limit 限制（默认 100）。 | 需通过 settings 或扩展显式激活 |
| **find** | 文件查找。按 glob 模式搜索文件（默认 limit 1000）。使用 fd 或系统 find。 | 同上 |
| **ls** | 目录列表。列出目录条目（默认 limit 500）。 | 同上 |

**Grep/Find/Ls 默认不激活的原因**（`agent-session.ts:2562-2564`）：
```typescript
const defaultActiveToolNames = this._baseToolsOverride
  ? Object.keys(this._baseToolsOverride)
  : ["read", "bash", "edit", "write"];
```

## 三、注入 system prompt 的配套内容

### 3.1 工具 promptSnippet（一行摘要）

每个工具的 `promptSnippet` 字段被提取为 `toolSnippets`，在 system prompt 中表现为一行 `- <name>: <snippet>`。

| 工具 | 注入的 snippet |
|------|---------------|
| read | "Read file contents" |
| bash | "Execute bash commands (ls, grep, find, etc.)" |
| edit | "Make precise file edits with exact text replacement, including multiple disjoint edits in one call" |
| write | "Create or overwrite files" |

### 3.2 工具 promptGuidelines（行为指导）

| 工具 | 注入的 guidelines |
|------|------------------|
| read | "Use read to examine files instead of cat or sed." |
| edit | 4 条：使用 edit 精确替换；多处修改合并到一个 edits[]；oldText 基于原始文件匹配；保持 oldText 最小化 |
| write | "Use write only for new files or complete rewrites." |

此外所有工具都自动注入 2 条默认指南：
- "Be concise in your responses"
- "Show file paths clearly when working with files"

### 3.3 Pi 文档路径引用

```
- Main documentation: <readmePath>
- Additional docs: <docsPath>
- Examples: <examplesPath>
- 按主题分别指向 docs/extensions.md, docs/themes.md, docs/skills.md 等
```

### 3.4 项目上下文文件（AGENTS.md / CLAUDE.md）

Resource Loader 扫描工作目录，找到 `AGENTS.md` 或 `CLAUDE.md` 后，内容被包装为 `<project_context>` XML 标签注入 system prompt。这通常是首轮上下文中**体积最大**的部分。

### 3.5 Skills

Resource Loader 扫描 `~/.pi/agent/skills/` 和项目目录下 `.pi/skills/`，将找到的 SKILL.md 内容注入为 `<skill>` 标签区块。**如果有大量 skills，这会显著膨胀首轮 context。**

### 3.6 Append System Prompt

来自 resource loader 的 `appendSystemPrompt`，可配置于 settings 或扩展。

## 四、不在 system prompt 中但影响首轮响应的因素

### 4.1 Auth/Model 验证（首轮前阻塞操作）

当用户输入第一条消息时，pi 在 `agent-session.ts:1157-1173` 执行模型和认证验证：

```
- 检查 model 是否选择（无模型抛错）
- 检查 provider auth 是否配置（无 auth 抛错）
- OAuth 过期检查
```

这些不在 system prompt 中，但在消息发送到 LLM 之前执行。**如果 auth 检查耗时，表现为首轮响应延迟。**

### 4.2 其他间接注入上下文的信息

| 信息来源 | 说明 | 首轮是否可用？ |
|---------|------|:-------------:|
| 会话历史（session history） | 之前的对话轮次 | 是（如有） |
| Compacted context | 压缩后的历史摘要 | 是（如已压缩） |
| Branch summary | 分支切换时的摘要 | 是（如有） |
| Session entry messages | 从 session 树加载的消息 | 是（如有） |
| Bash execution messages | 之前执行的 bash 记录 | 是（如有） |

### 4.3 工具代码参数（不在 prompt 中但影响执行）

| 对象 | 注入位置 |
|------|---------|
| **LLM 的函数定义（tool declarations）** | 不在 system prompt 文本中。由 Agent 框架（`pi-agent-core`）以原生 LLM function calling 格式注入 |
| 每个工具的 `parameters` 字段（JSON Schema） | 转换为 LLM 的 function/tool 声明格式 |
| 每个工具的 name/label/description | 转换为 LLM tool 声明的 description 字段 |
| cwd（当前工作目录） | 在 system prompt 末尾 `Current working directory: <path>` |

## 五、首轮"冷启动"问题根因回到首轮

结合工具分析，首轮响应质量差（需要第二轮才理解）的根本原因是：

1. **system prompt 以项目规则为主，没有用户意图的引导** — 大量 token 被 AGENTS.md、skills 等占据
2. **首轮没有对话历史** — LLM 只看到"系统指令 + 你的第一句话"，无法理解上下文
3. **重复输入时，第二轮有了首轮的"错误回复"作为参考** — LLM 可从中推断用户意图
4. **grep/find/ls 默认不激活** — 如果用户期望 pi 自动搜索文件，首轮只能靠 bash 实现，bash 本身是一种"绕路"操作

## 六、关键配置项对 context 的影响

| 配置 | 效果 | 首轮 token 影响 |
|-----|------|:--------------:|
| `quietStartup: true` | 启动时不显示加载的资源列表 | 不影响（仅 UI） |
| `--verbose` / `verbose: true` | 显示更详细的启动信息 | 不影响 |
| skill 数量 | 每个 skill 注入 <skill> 标签 | 显著增加 |
| AGENTS.md 大小 | 注入为 <project_context> | 显著增加 |
| 工具激活数 | 仅 active 工具注入 prompt | 轻度增加 |
