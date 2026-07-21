# Pi Agent 扩展挂钩（Hooking）系统

- **文档生成时间**: 2026-07-21 18:46:35 +0800
- **Pi 版本**: 0.80.10
- **包名**: `@earendil-works/pi-coding-agent`

## 概述

Pi 的 Hook 机制通过 **Extension（扩展）系统**实现。扩展是 TypeScript 模块（`.ts` 或 `.js`），可以订阅 Agent 生命周期事件、注册 LLM 可调用的工具、注册命令和快捷键。核心 API 在 `ExtensionAPI` 中定义（源码：`core/extensions/types.ts:1167-1402`）。

## 支持的钩子事件（完整清单）

所有事件均通过 `pi.on(event, handler)` 注册，共 **24 种**：

### 1. Session 生命周期（9 个）

| 事件名 | 触发时机 | 可修改内容 | 典型用途 |
|--------|---------|-----------|---------|
| `session_start` | session 启动/加载/重载时 | — | 初始化资源、记录 session 开始 |
| `session_info_changed` | session 名称变更时 | — | 同步 session 元数据 |
| `session_before_switch` | 切换到另一个 session 前 | 可取消 (`cancel: true`) | 确认未保存的数据 |
| `session_before_fork` | fork session 前 | 可取消 (`cancel: true`) | 确认 fork 操作 |
| `session_before_compact` | 上下文压缩前 | 可取消、注入自定义压缩逻辑 | 自定义压缩策略 |
| `session_compact` | 上下文压缩后 | — | 记录压缩事件 |
| `session_shutdown` | session 关闭/重载/替换时 | — | 清理资源 |
| `session_before_tree` | 会话树导航前 | 可取消、注入摘要 | 自定义分支摘要 |
| `session_tree` | 会话树导航后 | — | 记录导航事件 |

### 2. Agent / LLM 调用（9 个）

| 事件名 | 触发时机 | 可修改内容 | 典型用途 |
|--------|---------|-----------|---------|
| `context` | 每次 LLM 调用前 | 可替换完整消息列表 | 注入/修改上下文消息 |
| `before_provider_request` | provider 请求发送前 | 可替换 payload | 审计/修改 API 请求体 |
| `before_provider_headers` | 请求头组装后，HTTP 调用前 | 可原地修改 headers | 注入追踪/会话 Header |
| `after_provider_response` | provider 响应接收后，流消费前 | — | 记录响应状态和头信息 |
| `before_agent_start` | 用户提交消息后，Agent 循环前 | 可注入自定义消息、替换 system prompt | 动态调整提示词 |
| `agent_start` | Agent 循环开始时 | — | 记录 Agent 启动 |
| `agent_end` | Agent 循环结束时 | — | 汇总本轮结果 |
| `agent_settled` | Agent 完全静默（无重试/压缩/队列）后 | — | 确定本轮已完成 |
| `turn_start` | 每一轮（turn）开始时 | — | 计时、日志 |
| `turn_end` | 每一轮（turn）结束时 | — | 收集工具调用结果 |

### 3. 消息流（3 个）

| 事件名 | 触发时机 | 可修改内容 | 典型用途 |
|--------|---------|-----------|---------|
| `message_start` | 消息（user/assistant/toolResult）开始时 | — | 监控消息类型 |
| `message_update` | Assistant 消息流式更新时（token 级） | — | 实时消息监控 |
| `message_end` | 消息结束时 | 可替换消息 | 记录/修改最终消息 |

### 4. 工具执行（3 个）

| 事件名 | 触发时机 | 可修改内容 | 典型用途 |
|--------|---------|-----------|---------|
| `tool_execution_start` | 工具开始执行时 | — | 记录工具调用 |
| `tool_execution_update` | 工具执行过程中（流式输出） | — | 监控执行进度 |
| `tool_execution_end` | 工具执行完成时 | — | 记录执行结果 |

### 5. 具体工具调用前后（2 个事件）

| 事件名 | 触发时机 | 可修改内容 | 典型用途 |
|--------|---------|-----------|---------|
| `tool_call` | 工具执行**前** | 可阻止执行 (`block: true`)；可原地修改 `event.input` | 参数校验、权限控制、参数修改 |
| `tool_result` | 工具执行**后** | 可替换 content/details/isError | 结果审计、脱敏、修改 |

每个 `tool_call` / `tool_result` 事件会携带具体的**工具类型**信息：

```
bash:   event.toolName: "bash"   → input: { command, timeout? }
read:   event.toolName: "read"   → input: { path, offset?, limit? }
edit:   event.toolName: "edit"   → input: { path, edits[] }
write:  event.toolName: "write"  → input: { path, content }
grep:   event.toolName: "grep"   → input: { pattern, path?, glob?, ... }
find:   event.toolName: "find"   → input: { pattern, path?, limit? }
ls:     event.toolName: "ls"     → input: { path?, limit? }
(自定义): toolName: string        → input: Record<string, unknown>
```

### 6. 用户输入（1 个）

| 事件名 | 触发时机 | 可修改内容 | 典型用途 |
|--------|---------|-----------|---------|
| `input` | 用户输入后、Agent 处理前 | 可拦截 (`action: "handled"`)、转换 (`action: "transform"`) | 预处理器、命令过滤器 |

### 7. 用户 Bash 执行（1 个）

| 事件名 | 触发时机 | 可修改内容 | 典型用途 |
|--------|---------|-----------|---------|
| `user_bash` | 用户通过 `!`/`!!` 执行 bash 时 | 可提供自定义 Operations、替代结果 | 远程执行、命令审计 |

### 8. 模型相关（2 个）

| 事件名 | 触发时机 | 可修改内容 | 典型用途 |
|--------|---------|-----------|---------|
| `model_select` | 模型切换时 | — | 记录模型变更 |
| `thinking_level_select` | 思维级别切换时 | — | 记录思维级别变更 |

### 9. 启动/资源（2 个）

| 事件名 | 触发时机 | 可修改内容 | 典型用途 |
|--------|---------|-----------|---------|
| `project_trust` | 项目信任检查时 | 可返回 yes/no/undecided | 自动信任策略 |
| `resources_discover` | session_start 后 | 可提供额外的 skill/prompt/theme 路径 | 动态资源发现 |

## 扩展提供的其他功能

### 注册工具（registerTool）

通过 `pi.registerTool()` 注册自定义工具，LLM 可直接调用。工具定义包含：

| 字段 | 说明 |
|------|------|
| `name` | 工具名（LLM 调用时使用） |
| `label` | 界面显示标签 |
| `description` | 对 LLM 的描述 |
| `parameters` | TypeBox JSON Schema 参数定义 |
| `execute()` | 执行函数（接受 toolCallId + params + signal + onUpdate + ctx） |
| `renderCall()` | 可选：自定义调用显示 |
| `renderResult()` | 可选：自定义结果显示 |

### 注册命令（registerCommand）

自定义 `/command` 斜杠命令。处理函数接收 `(args, ctx)`。

### 注册快捷键（registerShortcut）

注册键盘快捷键处理。

### 注册 CLI 标志（registerFlag）

注册自定义 CLI 启动参数。

### 注册 Provider（registerProvider）

注册或覆盖模型 Provider（API、密钥、模型列表等）。

### 消息渲染（registerMessageRenderer / registerEntryRenderer）

注册自定义消息和条目的 UI 渲染器。

## 扩展配置方法

### 方法一：`~/.pi/agent/extensions/` 目录（全局）

将 `.ts` 或 `.js` 文件放入此目录，Pi 自动发现并加载。

```
~/.pi/agent/extensions/
├── my-extension.ts        # 单个文件扩展
├── my-package/            # 子目录（需有 index.ts 或 package.json pi.extensions）
│   ├── index.ts
│   └── package.json
```

### 方法二：项目本地扩展

在项目目录下的 `.pi/extensions/`（通过 `CONFIG_DIR_NAME` 配置）放置扩展文件。

```
<project_root>/.pi/extensions/
├── my-project-extension.ts
```

### 方法三：显式配置路径

在 Pi Agent 的 settings 或 SDK 创建参数中显式传入扩展路径列表。

### 方法四：package.json pi 声明

在 `package.json` 中声明 `pi.extensions` 字段：

```json
{
  "name": "my-package",
  "pi": {
    "extensions": ["./dist/extension.js"]
  }
}
```

## SDK 方式集成

通过 `@earendil-works/pi-coding-agent` 的 `createAgentSession()` 传入 `customTools` 或 `resourceLoader` 加载自定义扩展。

## 最小示例

一个监听 `tool_call` 和 `tool_result` 事件的扩展：

```typescript
// ~/.pi/agent/extensions/log-calls.ts
export default function (pi: ExtensionAPI) {
  // 工具调用前记录
  pi.on("tool_call", (event, ctx) => {
    if (event.toolName === "bash") {
      console.log(`[Hook] bash command: ${event.input.command}`);
    }
    if (event.toolName === "read") {
      console.log(`[Hook] read file: ${event.input.path}`);
    }
    // 返回 { block: true, reason: "..." } 可阻止执行
  });

  // 工具结果后处理
  pi.on("tool_result", (event, ctx) => {
    if (event.isError) {
      console.log(`[Hook] ${event.toolName} failed`);
    }
  });

  // 用户输入拦截示例
  pi.on("input", (event, ctx) => {
    if (event.text.startsWith("!")) {
      return { action: "handled" }; // 阻止 Agent 处理
    }
    return { action: "continue" };
  });

  // 注册自定义工具
  pi.registerTool({
    name: "my_custom_tool",
    label: "My Custom Tool",
    description: "A demo tool registered by extension",
    parameters: Type.Object({
      message: Type.String({ description: "Message to log" }),
    }),
    execute: async (toolCallId, params, signal, onUpdate, ctx) => {
      console.log(`[Extension Tool] ${params.message}`);
      return { content: [{ type: "text", text: "Done" }] };
    },
  });

  // 注册自定义命令
  pi.registerCommand("my-command", {
    description: "A demo command",
    handler: async (args, ctx) => {
      ctx.ui.notify(`Command executed with args: ${args}`);
    },
  });
}
```

## 关键注意事项

1. **事件处理函数**可以是 `void`（无返回）或返回指定的结果类型
2. `tool_call` 的 `event.input` 是**可变的**：修改它会影响到后续处理器和实际工具执行
3. `before_provider_headers` 的 `headers` 是**可变的**：原地修改会影响实际 HTTP 请求
4. `context` 事件返回的 `messages` 会**替换**整个消息列表（不仅仅是追加）
5. 扩展通过 `jiti` 在运行时加载 TypeScript，无需预编译
6. 扩展可访问的库：`typebox`、`@earendil-works/pi-agent-core`、`@earendil-works/pi-tui`、`@earendil-works/pi-ai`、`@earendil-works/pi-coding-agent`
