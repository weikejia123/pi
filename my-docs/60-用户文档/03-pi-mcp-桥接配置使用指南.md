# pi 接入 MCP（minimax web_search）— 配置使用指南

> V1-20260801 · 2026-08-01 · 状态：已投入使用

## 背景

pi 无内置 MCP 支持（设计如此，见上游 docs/usage.md："It intentionally does not include built-in MCP"）。
本地已有一个 minimax web_search MCP server，需要让 pi agent 能调用它。

## 问题诊断

1. **本地 MCP server 启动即崩**：`~/.reasonix/minimax-mcp-wrapper.sh` 内
   `minimax-coding-plan-mcp 0.0.4` 声明依赖 `mcp>=1.6.0`（无上限），
   uv 解析到了 `mcp 2.0.0`，而 mcp 2.x 移除了 `mcp.server.fastmcp`。
   修复：uvx 加 `--with "mcp<2"` 约束。
2. **pi 无法直接用 MCP**：需通过扩展桥接——用 MCP SDK 连接 server，
   把 MCP 工具注册为 pi 自定义工具。

## 方案

通用 MCP 桥接扩展（不限于 minimax，任意 stdio MCP server 可接）：

- 扩展在 `session_start` 时连接所有配置的 MCP server，`listTools` 后逐个 `registerTool`
- MCP 工具注册为 pi 工具，命名为 `<toolPrefix>_<toolName>`
- `session_shutdown` 时关闭连接
- server 配置从 `~/.pi/agent/mcp.json` 读取

## 交付物

| 路径 | 作用 |
|------|------|
| `~/.pi/agent/extensions/mcp/index.ts` | 通用 MCP 桥接扩展源码 |
| `~/.pi/agent/extensions/mcp/package.json` + node_modules | 依赖：`@modelcontextprotocol/sdk 1.30.0`、`typebox 1.1.38` |
| `~/.pi/agent/extensions/mcp/minimax-wrapper.sh` | 修复版 wrapper（`--with "mcp<2"`），独立于原 reasonix 文件 |
| `~/.pi/agent/mcp.json` | server 配置（当前含 minimax） |

## 配置方法

`~/.pi/agent/mcp.json` 格式：

```json
{
  "mcpServers": [
    {
      "name": "minimax",
      "command": "/bin/bash",
      "args": ["/Users/weikejia/.pi/agent/extensions/mcp/minimax-wrapper.sh"],
      "toolPrefix": "minimax"
    }
  ]
}
```

字段：`name`（必填）、`command`（必填）、`args`、`env`、`cwd`、`toolPrefix`（默认取 name）。

新增 MCP server：往 `mcpServers` 数组加条目，保存后 pi 内 `/reload` 生效。

## 使用

启动 pi 即自动加载（`~/.pi/agent/extensions/` 全局扩展自动发现）。
当前 minimax server 暴露 2 个工具：

- `minimax_web_search`（参数 `query`）— 联网搜索
- `minimax_understand_image` — 图片理解

## 验证结果（2026-08-01 实测）

1. jiti 加载扩展 + 订阅事件正常
2. 真实连接 minimax MCP，`listTools` 返回 2 个工具
3. `minimax_web_search` 实际执行搜索返回真实结果
4. 真实 pi 会话中模型成功调用 `minimax_web_search` 并基于结果回答

## 注意事项

- `~/.reasonix/minimax-mcp-wrapper.sh`（原文件）同样受 mcp 2.x bug 影响，
  reasonix 等其它使用它的工具也会挂。本次未改动它，仅 pi 侧用独立修复版 wrapper。
- MCP server 每次 session_start 重新连接，`/reload` 会重连。
- 扩展依赖安装：`~/.pi/agent/extensions/mcp/` 下 `npm install`（已装好）。
