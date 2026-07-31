# Pi CLI 实时输出工作状态 — JSON 事件流模式使用技巧

> 用户视角使用技巧。内容以源代码为准（`packages/coding-agent/`），非官方文档。

## 适用场景

用 `pi` 做**一轮对话**（非交互），但希望**实时看到工作过程**，而不只是等结尾拿到最终答案：

- 脚本/CI 里调用 pi，实时观察模型输出与工具执行进度
- 管道场景（`| jq`、`| while read`）程序化消费事件流
- 想看到"它正在读哪个文件、跑哪条命令、写到一半的文本"

## 一句话结论

- `pi --mode json -p "问题"` → **实时 JSON 事件流**，每行一个事件 ✅
- `pi -p "问题"`（纯文本模式）→ **不流式**，只在结束后打印最后一条 assistant 消息 ❌
- `pi "问题"`（交互式 TUI）→ 完整实时渲染界面 ✅

## 基本用法

```bash
pi --mode json -p "帮我分析一下这个仓库的结构"
```

`--mode json` 与 `-p` 可任选其一触发非交互模式（源代码 `main.ts` 中 `resolveAppMode`：`--mode json` 直接进 json 模式；管道 stdin 非 TTY 时也会进 print 模式）。

## 输出格式

标准输出是 **JSON Lines**（每行一个 JSON 对象），共分两类：

### 1. 首行 header（会话元信息，`SessionManager.getHeader()`）

```json
{"type":"session","id":"...","timestamp":"...","cwd":"/path/to/project"}
```

### 2. 事件流（`session.subscribe` 逐条实时写入，`print-mode.ts`）

| 事件类型 | 含义 |
|----------|------|
| `agent_start` / `agent_end` | 整轮开始 / 结束（`agent_end` 附最终消息列表） |
| `turn_start` / `turn_end` | 单个回合开始 / 结束 |
| `message_start` / `message_update` / `message_end` | 消息生命周期；**`message_update` 是模型流式增量**（内含 `assistantMessageEvent`，有 `text_delta` / `thinking_delta` / `toolcall_delta` 等子事件） |
| `tool_execution_start` / `tool_execution_update` / `tool_execution_end` | 工具执行状态（哪个工具、什么参数、逐步结果） |
| `bash_execution_update` | **bash 工具的真实时输出增量**（`delta` 字段） |
| `compaction_start` / `compaction_end` | 上下文压缩 |
| `auto_retry_start` / `auto_retry_end` | 自动重试 |
| `queue_update` / `entry_appended` / `agent_settled` 等 | 内部状态同步 |

示例（截取片段）：

```json
{"type":"agent_start"}
{"type":"message_start","message":{"role":"assistant","content":[]}}
{"type":"message_update","message":{"role":"assistant","content":[{"type":"text","text":"我来分析..."}]},"assistantMessageEvent":{"type":"text_delta","contentIndex":0,"delta":"我来分析"}}
{"type":"tool_execution_start","toolCallId":"call_1","toolName":"bash","args":{"command":"ls -la"}}
{"type":"bash_execution_update","id":"...","delta":"drwxr-xr-x  ..."}
{"type":"tool_execution_end","toolCallId":"call_1","toolName":"bash","result":"...","isError":false}
{"type":"message_end","message":{...}}
{"type":"turn_end","message":{...},"toolResults":[...]}
{"type":"agent_end","messages":[...]}
{"type":"agent_settled"}
```

## 消费技巧

### 只看工具调用轨迹

```bash
pi --mode json -p "重构 utils.ts" | jq -c 'select(.type | startswith("tool_execution"))'
```

### 只看模型最终回复（正文）

```bash
pi --mode json -p "问题" | jq -c 'select(.type=="agent_end") | .messages[-1].content[] | select(.type=="text") | .text'
```

### 实时观察 bash 工具输出

```bash
pi --mode json -p "跑一下测试" | jq -c 'select(.type=="bash_execution_update") | .delta'
```

### 实时进度条式监控

```bash
pi --mode json -p "..." | while IFS= read -r line; do
  case "$(echo "$line" | jq -r '.type')" in
    tool_execution_start) echo "→ 开始执行工具";;
    tool_execution_end)   echo "← 工具执行完毕";;
    agent_end)            echo "✔ 完成";;
  esac
done
```

## 与其他模式的对比

| 模式 | 命令 | 实时性 | 用途 |
|------|------|--------|------|
| 纯文本 | `pi -p "问题"` | ❌ 只输出最终文本 | 简单一问一答 |
| JSON 事件流 | `pi --mode json -p "问题"` | ✅ 全事件实时 | 脚本/管道消费 |
| RPC | `pi --mode rpc` | ✅ 全事件实时（JSONL 协议） | 进程间完整控制 |
| 交互式 TUI | `pi "问题"` | ✅ 界面实时渲染 | 人工观看 |

补充说明（源代码事实）：

- json 模式每收到一个事件立即 `writeRawStdout`，**不攒批**（`output-guard.ts`），所以是真正实时
- json 模式输出时会对 stdout 做接管（`takeOverStdout`），日志/诊断走 stderr，**stdout 只给事件流**，方便直接管道
- 结束时有 `flushRawStdout` 兜底，正常场景无需等待
- 想获得比 `message_update` 更细的增量，可解析其中的 `assistantMessageEvent` 字段

## 注意事项

- `--mode json` 与 `--mode rpc` 互斥；rpc 是完整的请求/响应协议（stdin 下发命令），json 是单向事件流
- 事件里的 `partial` 字段（`message_update` 内的 `assistantMessageEvent.partial`）是**未完成的消息快照**，属增量消费的参考数据，最终以 `message_end` / `agent_end` 为准
- 若只是想在终端里"边看边等"，交互式 TUI（`pi "问题"`）体验更好，无需解析 JSON
