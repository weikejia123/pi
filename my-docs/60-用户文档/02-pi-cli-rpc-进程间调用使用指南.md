# Pi CLI RPC 模式 — 进程间调用使用指南

> 用户视角使用指南。内容以源代码为准（`packages/coding-agent/src/modes/rpc/`、`packages/server/`），非官方文档。

## 适用场景

把 pi 当作**可编程服务**嵌入你自己的应用：GUI/Web 前端、Agent 编排控制器、CI 长驻任务、IDE 插件。与 json 模式的区别在于——rpc 是**双向 + 长驻**的协议：能指挥 agent、能中途插话、能反向问宿主要输入；json 模式是一次性审计流（发完就跑）。

## 一、协议概述（源码事实）

- **入口**：`pi --mode rpc`（main.ts 中 RPC 模式启动后在后台刷新模型目录）
- **stdin 下发命令**（JSONL，每行一个 `RpcCommand`），**stdout 输出响应 + 事件**（每行一个 JSON）
- **stdout 被接管**：诊断/日志走 stderr，stdout 纯协议流，可直接管道消费
- **进程长驻**：`rpc-mode.ts` 中 `return new Promise(() => {})` 永不退出；宿主必须**关闭 stdin** 或发 **SIGTERM** 才会退出
- **帧格式**（jsonl.ts）：LF 分隔；payload 内允许 U+2028/U+2029，必须按 `\n` 切行（不能用 readline）

### 三种 stdout 行类型

| 类型 | 说明 |
|------|------|
| `{"type":"response","id":"req_1","command":"prompt","success":true,...}` | 命令确认/结果，`id` 与命令关联 |
| `{"type":"agent_start"}` 等 | AgentSessionEvent 实时工作状态事件（同 json 模式事件流） |
| `{"type":"extension_ui_request","id":"ui_1","method":"confirm",...}` | **扩展需要用户输入**，宿主回 `{"type":"extension_ui_response","id":"ui_1",...}` |

### 命令清单（rpc-types.ts，30+ 个）

| 类别 | 命令 |
|------|------|
| 对话 | `prompt` / `steer`（中途插话）/ `follow_up` / `abort` |
| 会话 | `new_session` / `switch_session` / `fork` / `clone` / `get_entries` / `get_tree` / `get_fork_messages` / `get_messages` / `get_last_assistant_text` / `set_session_name` / `export_html` / `get_session_stats` |
| 模型 | `set_model` / `cycle_model` / `get_available_models` / `set_thinking_level` / `cycle_thinking_level` / `get_available_thinking_levels` |
| 工具 | `bash` / `abort_bash` |
| 控制 | `set_steering_mode` / `set_follow_up_mode` / `compact` / `set_auto_compaction` / `set_auto_retry` / `abort_retry` |
| 状态 | `get_state` / `get_commands`（扩展命令 + prompt 模板 + skills） |

## 二、用法 A：裸协议（任何语言）

```bash
# 启动长驻进程
pi --mode rpc &
PID=$!

# 发一条命令（带 id 关联）
printf '%s\n' '{"type":"prompt","id":"req_1","message":"分析这个仓库"}' > /proc/$PID/fd/0

# 关闭 stdin 优雅退出
exec 0<&-; kill -TERM $PID
```

stdout 上会先收到 `{"type":"response","id":"req_1","command":"prompt","success":true}`（预检通过即返回），随后是完整事件流。

## 三、用法 B：官方 TypeScript 客户端（推荐）

`RpcClient`（`rpc-client.ts`）已封装协议为类型化 API：

```ts
import { RpcClient } from "@earendil-works/pi-coding-agent";

const client = new RpcClient({
  cwd: "/path/to/project",
  model: "openai/gpt-5.5",
});
await client.start();

// 实时工作状态
client.onEvent((event) => {
  switch (event.type) {
    case "tool_execution_start":
      console.log(`→ 工具 ${event.toolName}`);
      break;
    case "bash_execution_update":
      console.log(event.delta);   // 实时 shell 输出
      break;
  }
});

// 一轮对话并等结束（内部：prompt + 收集事件到 agent_settled）
const events = await client.promptAndWait("分析这个仓库");

// 继续指挥
await client.steer("等等，先聚焦测试文件");
await client.getState();
await client.stop();   // SIGTERM，1s 超时后 SIGKILL
```

内部要点（源码事实）：`start()` 等 100ms 初始化；`send()` 30s 响应超时；`waitForIdle()` / `promptAndWait()` 默认 60s 等 `agent_settled`。

## 四、用法 C：多实例架构（参考 packages/server）

仓库已有现成样板：`packages/server/src/rpc-process.ts` 的 `RpcProcessInstance` 封装了 spawn RPC 子进程 + 请求 id 关联 + 事件分发 + **extension UI 请求转发**；另有 supervisor（守护多实例）与 ipc（Unix socket）。

```
┌─ 宿主进程（你自己的 UI / 控制器 / IDE 插件）
│   ├─ RpcProcessInstance #1 → pi --mode rpc   (会话 A：读文件)
│   ├─ RpcProcessInstance #2 → pi --mode rpc   (会话 B：跑测试)
│   └─ RpcProcessInstance #3 → pi --mode rpc   (会话 C：写代码)
│
│   事件流 → 驱动宿主渲染（消息/工具/bash 实时状态）
│   extension_ui_request → 宿主弹出自己的 confirm/select 对话框
│   宿主回 extension_ui_response → agent 继续
```

典型场景：
- **GUI/Web 前端**：自己画界面，pi 当后端，扩展的确认/选择弹窗由前端接管
- **Agent 编排**：一个控制器管多个 pi 实例分工，`steer` 中途改方向、`abort` 叫停、`bash` 直接执行命令
- **CI 长驻**：一次启动（模型/扩展/会话加载只做一遍）连续处理多轮任务

## 五、注意事项（源码事实）

1. **RPC 下部分 TUI 专属能力不可用**（`createExtensionUIContext` 中明确 no-op）：`setWorkingMessage`、`setFooter/setHeader`、`getEditorText`（同步方法等不了 RPC 响应，返回空串）、`onTerminalInput`、自定义组件。需要这些须自行实现。
2. **服务端不主动退出**：必须由宿主关 stdin 或发 SIGTERM。
3. **`--mode rpc` 不接受 `@file` 参数**（main.ts 显式报错）。
4. **stdout 只走协议**：`takeOverStdout()` 保证 stdout 纯净，宿主可直接管道消费。
5. 扩展 UI 请求带超时/中止支持（`createDialogPromise`），宿主不响应时按默认值继续。
