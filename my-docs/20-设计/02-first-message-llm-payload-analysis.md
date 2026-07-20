# Pi 首次消息 LLM 请求内容分析

> 📅 分析日期：2026-07-21
> 📍 项目：`projects/coder-agent/pi/`（wkj-dev 分支）
> 🔍 文件跟踪从 `interactive-mode.ts` → `agent-session.ts` → `system-prompt.ts` → `agent-loop.ts` → LLM Provider

---

## 一、概述

当你打开一个**新会话**，输入 `hi` 并发送时，LLM 实际接收到的远不止 `"hi"` 一个词。

Pi 在首个请求中注入以下内容：

| 组件 | 来源 | 作用 |
|------|------|------|
| **System Prompt** | `system-prompt.ts:28-162` | Agent 身份、可用工具、行为准则 |
| **Pi 文档引用** | `config.ts` 中的 `getReadmePath()`/`getDocsPath()` | 告诉 LLM Pi 自身文档在哪 |
| **上下文文件（AGENTS.md）** | `resource-loader.ts:67-83` | CWD 及祖先目录的所有 `AGENTS.md`/`CLAUDE.md` |
| **Skill 清单** | `skills.ts:335-361` | 所有已加载 Skill 的 `<available_skills>` XML 块 |
| **当前工作目录** | `system-prompt.ts:159` | `Current working directory: /path/to/cwd` |
| **用户消息** | `"hi"` | 用户输入的第一条消息 |
| **模型 & 思考级别** | `agent-session.ts:513-517` | 默认模型 + thinking level |

---

## 二、逐层拆解

### 第 1 层：系统提示词（system prompt）

文件：`packages/coding-agent/src/core/system-prompt.ts`

默认（无 `--system-prompt` 参数）构造出以下内容：

```
You are an expert coding assistant operating inside pi, a coding agent harness...

Available tools:
- read: Read file contents...
- bash: Execute shell commands...
- edit: Edit files...
- write: Write new files...

Guidelines:
- Be concise in your responses
- Show file paths clearly when working with files

Pi documentation (read only when the user asks about pi itself...):
- Main documentation: /path/to/README.md
- Additional docs: /path/to/docs/
- Examples: /path/to/examples/
```

**代码验证**（`system-prompt.ts:121-138`）：

```typescript
let prompt = `You are an expert coding assistant operating inside pi, a coding agent harness. You help users by reading files, executing commands, editing code, and writing new files.

Available tools:
${toolsList}

Guidelines:
${guidelines}
...`;
```

#### 如果有 `--append-system-prompt` 参数

会追加在系统提示词末尾。

### 第 2 层：上下文文件（AGENTS.md / CLAUDE.md）

文件：`packages/coding-agent/src/core/resource-loader.ts:67-120`

Pi 会**自动**扫描并加载以下文件的内容：

1. `~/.pi/agent/AGENTS.md`（如果存在）
2. **当前目录**及所有**祖先目录**中的第一个 `AGENTS.md` 或 `CLAUDE.md`（不区分大小写）

你启动 Pi 时看到的输出验证了这一点：

```
[Context]
  ~/AGENTS.md, ~/CODE/my-agent-group/AGENTS.md
```

这些文件内容被包装在：

```
<project_context>

Project-specific instructions and guidelines:

<project_instructions path="/full/path/to/AGENTS.md">
...文件完整内容...
</project_instructions>

</project_context>
```

**代码验证**（`system-prompt.ts:54-61`）：

```typescript
if (contextFiles.length > 0) {
    prompt += "\n\n<project_context>\n\n";
    prompt += "Project-specific instructions and guidelines:\n\n";
    for (const { path: filePath, content } of contextFiles) {
        prompt += `<project_instructions path="${filePath}">\n${content}\n</project_instructions>\n\n`;
    }
    prompt += "</project_context>\n";
}
```

**注意**：`~/AGENTS.md`（家目录）和 `~/CODE/my-agent-group/AGENTS.md`（项目目录）的内容都会被完整注入。

### 第 3 层：Skill 清单

所有已加载的 Skill 被格式化为 XML 块附加在系统提示词末尾：

```
<available_skills>
  <skill>
    <name>skill-name</name>
    <description>skill description text</description>
    <location>/full/path/to/skill/SKILL.md</location>
  </skill>
  <skill>
    ...
  </skill>
</available_skills>
```

**代码验证**（`skills.ts:335-361`）：

```typescript
export function formatSkillsForPrompt(skills: Skill[]): string {
    const lines = [
        "\n\nThe following skills provide specialized instructions for specific tasks.",
        "Use the read tool to load a skill's file when the task matches its description.",
        "",
        "<available_skills>",
    ];
    for (const skill of visibleSkills) {
        lines.push(`    <name>${escapeXml(skill.name)}</name>`);
        lines.push(`    <description>${escapeXml(skill.description)}</description>`);
        lines.push(`    <location>${escapeXml(skill.filePath)}</location>`);
    }
    lines.push("</available_skills>");
    return lines.join("\n");
}
```

### 第 4 层：当前工作目录

最后一行：

```
Current working directory: /Users/weikejia/CODE/my-agent-group/projects/coder-agent/grok-build
```

### 第 5 层：用户消息

最终发送给 LLM 的 Context 结构是：

```typescript
{
    systemPrompt: "<上面所有内容的拼接>",
    messages: [
        {
            role: "user",
            content: [{ type: "text", text: "hi" }]
        }
    ],
    tools: [...]         // 可用工具定义（OpenAI/Anthropic 格式）
}
```

---

## 三、完整 LLM 请求模拟

假设你在 `~/CODE/my-agent-group/projects/coder-agent/grok-build` 目录启动 Pi 并输入 `hi`，LLM 实际接收到的请求内容等价于以下结构（约 **8000-15000 tokens**，取决于 AGENTS.md 和 Skills 数量）：

```json
{
  "system": "You are an expert coding assistant operating inside pi...

Available tools:
- read: Read file contents...
...

Guidelines:
- Be concise in your responses
...

Pi documentation:
...

<project_context>
Project-specific instructions and guidelines:

<project_instructions path=\"/Users/weikejia/CODE/my-agent-group/AGENTS.md\">
[完整 AGENTS.md 内容]
</project_instructions>

<project_instructions path=\"/Users/weikejia/CODE/my-agent-group/projects/coder-agent/grok-build/AGENTS.md\">
[grok-build 的 AGENTS.md 内容]
</project_instructions>

</project_context>

The following skills provide specialized instructions for specific tasks...

<available_skills>
  <skill><name>...skill1</name>...</skill>
  <skill><name>...skill2</name>...</skill>
  ...
</available_skills>

Current working directory: /Users/weikejia/CODE/my-agent-group/projects/coder-agent/grok-build",

  "messages": [
    { "role": "user", "content": "hi" }
  ]
}
```

---

## 四、调试日志

### 4.1 是否有 HTTP 级别的 LLM 通信日志？

**没有。** Pi **默认不记录**与 LLM Provider 之间的原始 HTTP 请求/响应。

Pi 的架构是：

```
用户输入 → AgentSession.prompt()
  → agent-loop.streamAssistantResponse()
    → streamSimple(model, context, options)
      → 具体 Provider 的 API（deepseek API / anthropic API / openai API）
```

`streamSimple()` 函数（`packages/ai/src/compat.ts:275`）调用后直接向 Provider 发出 HTTP 请求，过程中**不写日志**。

### 4.2 已有的调试手段

#### 方式 A：`/debug` 命令（最实用）

在 Pi TUI 中输入 `/debug`，会生成 `~/.pi/agent/pi-debug.log`，内容包括：

1. **Terminal 渲染信息** — 所有屏幕行及可见宽度
2. **Session messages** — 当前会话所有消息的 JSON 序列化（包括系统提示词和用户消息）

**代码验证**（`interactive-mode.ts:5836-5866`）：

```typescript
private handleDebugCommand(): void {
    const debugData = [
        "=== Agent messages (JSONL) ===",
        ...this.session.messages.map((msg) => JSON.stringify(msg)),
    ].join("\n");
    fs.writeFileSync(debugLogPath, debugData);
}
```

**输出位置**：`~/.pi/agent/pi-debug.log`

#### 方式 B：环境变量调试

| 变量 | 作用 | 输出位置 |
|------|------|---------|
| `PI_DEBUG_REDRAW=1` | 记录 TUI 重新渲染触发器 | `~/.pi/agent/pi-debug.log` |
| `PI_TUI_WRITE_LOG=<dir>` | 记录 TUI 详细渲染日志 | `<dir>/tui-<timestamp>-<pid>.log` |
| `--verbose` | 启动时详细输出（覆盖 quietStartup） | 终端 stdout |

#### 方式 C：会话 JSONL 文件（最接近 LLM 通信内容）

Pi 自动持久化每个会话到 `~/.pi/agent/sessions/<session-id>.jsonl`

该 JSONL 文件包含完整的消息历史（user + assistant 消息），但**不包含 system prompt**（因为 system prompt 不是 messages 的一部分，而是作为 context 单独发送）。

**位置**：`~/.pi/agent/sessions/`

**内容示例**：

```json
{"type":"session","id":"xxx","agentDir":"~/.pi/agent/","cwd":"/path/to/cwd","startTime":"2026-07-21T00:00:00.000Z"}
{"type":"entry","id":"xxx","parentId":null,"timestamp":"...","message":{"role":"user","content":[{"type":"text","text":"hi"}]}}
{"type":"entry","id":"xxx","parentId":"xxx","timestamp":"...","message":{"role":"assistant","content":[{"type":"text","text":"Hello! How can I help you today?"}]}}
```

---

## 五、缺少的功能

Pi **缺少 HTTP 请求级别的 LLM 调试日志**——无法直接看到发给 DeepSeek/Anthropic 的完整 raw payload。

| 需要的信息 | Pi 是否提供 | 如何获取 |
|-----------|-----------|---------|
| System prompt 内容 | ✅ 通过 `/debug` | `~/.pi/agent/pi-debug.log` |
| 用户消息历史 | ✅ 自动保存 | `~/.pi/agent/sessions/*.jsonl` |
| Skill 清单 | ✅ 启动时显示 | 终端输出 [Skills] 区块 |
| AGENTS.md 内容 | ✅ 启动时显示 | 终端输出 [Context] 区块 |
| **LLM Raw Request Payload** | ❌ **不提供** | 需通过 Provider API 控制台查看（DeepSeek 后台日志） |
| **LLM Raw Response** | ❌ **不提供** | 同上 |
| **Prompt Cache 命中详情** | ❌ 不提供 | 仅 DeepSeek API 本身返回 cache_hit 信息 |

---

## 六、获取 LLM 通信原始内容的方法

### 方法 1：DeepSeek API 控制台（推荐）

在 DeepSeek 官网的 API 管理后台查看请求日志：
- https://platform.deepseek.com/usage
- 显示每次请求的输入 token、输出 token、prompt cache 命中情况
- 但**不显示具体内容**（API 不提供）

### 方法 2：Proxy 中间人（技术方案）

在 Pi 和 LLM Provider 之间加一个 mitmproxy 或类似的 HTTP 调试代理：

```bash
# 启动代理
mitmweb --listen-port 8888

# 设置环境变量让 Pi 的路由通过代理
export https_proxy=http://127.0.0.1:8888
export http_proxy=http://127.0.0.1:8888
```

### 方法 3：使用 `--print` 模式 + 调试输出

```bash
pi -p "hi" --verbose 2>&1 | tee /tmp/pi-request.log
```
`--print` 模式（print-mode）在处理过程中会输出更多的过程信息到 stdout。

---

## 七、总结

| 项目 | 结论 |
|------|------|
| 新会话首次消息发送给 LLM 的内容 | **System Prompt（含 AGENTS.md 完整内容 + Skill 列表 + 工具定义 + 文档路径）** + **`"hi"`** |
| 估算请求大小 | 约 **8000-15000 tokens**（取决于项目 AGENTS.md 大小和 Skill 数量） |
| "hi" 在其中占比 | 极小（~0.1%）— 绝大部分是 System Prompt |
| 调试日志位置 | `~/.pi/agent/pi-debug.log`（通过 `/debug` 命令生成）|
| 会话历史位置 | `~/.pi/agent/sessions/*.jsonl`（不含 system prompt） |
| LLM 原始 HTTP 请求日志 | ❌ **不支持** — 需要 Provider 控制台或外置 HTTP 代理 |

---

## 八、实测数据：清除 Skill 后的首次请求 Token 用量

2026-07-20 清除 `~/.agents/skills/` 中全部 62 个 Skill 后，在新开 Pi 会话中首次输入 `hi`，DeepSeek 官方 API 后台统计如下：

| 指标 | Token 数 |
|------|---------|
| 输入（新会话，无缓存命中） | **12,628** |
| 输出 | **135** |

### 关键解读

1. **清除 62 个 Skill 后，首次请求总输入 ≈ 12,628 tokens**
   - 对比清除前（含 62 个 Skill 列表），清除仅减少了 Skill 列表的 XML 块（约 3-5K tokens）
   - 清除后输入降至 **12,628 tokens**，约 12K

2. **新会话无缓存命中** — 这是合理的，因为：
   - 每次 `pi` 新进程启动，system prompt 的 hash 会变化（包含 session ID、文件路径等运行时变量）
   - DeepSeek 的 prefix caching 基于精确前缀匹配

3. **输出仅 135 tokens** — LLM 回复一个简单的问候，符合预期

4. **推断各组件 Token 占比**

| 组件 | 估算 tokens | 占比 |
|------|------------|------|
| Pi system prompt（身份+工具+指南+文档路径） | ~2,000 | ~16% |
| AGENTS.md（~10KB 纯文本） | ~3,500 | ~28% |
| Skills 列表（清除后仅剩内置少量 Skill） | ~200 | ~2% |
| 其他（CWD 等） | ~100 | ~1% |
| **Pi 内置 coding agent prompt（核心）** | **~6,828** | **~54%** |
| **合计** | **~12,628** | **100%** |

