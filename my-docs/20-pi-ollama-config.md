# Pi + Ollama 本地模型配置

## 概述

Pi agent 通过 `~/.pi/agent/models.json` 自定义配置文件接入 Ollama 本地模型。Ollama 暴露 OpenAI 兼容的 `/v1/chat/completions` 接口，pi 使用 `openai-completions` API 协议对接。

## 当前配置

### Provider: ollama

- **baseUrl**: `http://localhost:11434/v1`（Ollama 默认端口）
- **api**: `openai-completions`（OpenAI 兼容协议）
- **apiKey**: `ollama`（占位符 — Ollama 忽略 key，但 pi 要求 auth 存在）

### 已注册模型

| 模型 ID | 名称 | 类型 | 上下文窗口 | 备注 |
|---------|------|------|-----------|------|
| `qwen3.6:35b` | Qwen 3.6 35B Q4_K_M | text+vision | 262,144 tokens | Qwen 3.6 MoE 架构，支持 tools/thinking/vision |

### Compat 配置

```json
"compat": {
  "supportsDeveloperRole": false,
  "supportsReasoningEffort": false
}
```

Ollama 上 Qwen 系模型不支持 `developer` role（需降级为 `system` 消息），也不支持 `reasoning_effort` 参数。这两个 compat 标志避免 pi 发送不兼容的请求参数。

### 费用

免费（本地运行，零 API 费用）。

## 使用方法

### 交互模式

```bash
pi
# 在交互界面输入 /model
# 选择 ollama 下的 richardyoung/qwythos-9b-abliterated:Q8_0
```

### 命令行模式

```bash
pi -p "你的问题" --model "ollama/richardyoung/qwythos-9b-abliterated:Q8_0"
```

### 首次使用需登录 auth

Pi 要求每个 provider 显式记录 auth。登录命令：

```bash
pi /login ollama
```

之后即可在 `/model` 中看到 Ollama 的模型列表。

## 配置文件位置

| 文件 | 说明 |
|------|------|
| `~/.pi/agent/models.json` | 自定义 provider 和模型定义（热加载，无需重启） |
| `~/.pi/agent/auth.json` | 各 provider 的认证信息 |
| `~/.pi/agent/settings.json` | 默认 provider/model 等全局设置 |

## 热加载

编辑 `models.json` 后无需重启 pi，下次执行 `/model` 或 `--list-models` 时自动重新加载。

## 模型能力

经 Ollama API 查询，qwen3.6:35b 的 capabilities 包含：

- **completion** — 文本生成
- **tools** — 函数调用（pi 可使用工具调用功能）
- **thinking** — 推理标记（pi 可展示思考过程）
- **vision** — 视觉输入（pi 支持多模态）

架构基于 Qwen 3.6 MoE（36.0B 参数），Q4_K_M 量化，上下文窗口 262,144 tokens。

## 添加更多模型

Ollama 拉取新模型后，在 `models.json` 的 `models` 数组中追加即可：

```json
{ "id": "llama3.1:8b" },
{ "id": "qwen2.5-coder:7b" }
```

最简单的写法只需要 `id`，其他字段（contextWindow, maxTokens 等）使用默认值。
