# Pi CLI 命令行帮助文档（中文解释）

> 基于 `pi --help` 输出整理，对每个选项和概念进行中文解释。

## 概述

`pi` 是一个 AI 编程助手，内置了 `read`（读取文件）、`bash`（执行命令）、`edit`（编辑文件）、`write`（写入文件）等工具，可以在终端中以交互或非交互方式与 AI 协作完成编程任务。

---

## 基本用法

```
pi [options] [@files...] [messages...]
```

- `[options]`：命令行选项（见下文）
- `[@files...]`：通过 `@` 前缀引用文件，将文件内容附加到消息中
- `[messages...]`：发送给 AI 的初始消息

---

## 子命令（Commands）

| 命令 | 说明 |
|------|------|
| `pi install <source> [-l]` | 安装扩展源并添加到配置中。`-l` 表示仅本地安装 |
| `pi remove <source> [-l]` | 从配置中移除扩展源 |
| `pi uninstall <source> [-l]` | `remove` 的别名 |
| `pi update [source\|self\|pi]` | 更新 pi 本身、扩展或模型目录 |
| `pi list` | 列出已安装的扩展 |
| `pi config [-l]` | 打开 TUI 界面来启用/禁用包资源（Tab 键切换作用域） |
| `pi <command> --help` | 显示特定子命令的帮助信息 |

---

## 选项详解（Options）

### 模型与提供商

| 选项 | 说明 |
|------|------|
| `--provider <name>` | 指定 AI 提供商名称（默认：google） |
| `--model <pattern>` | 模型匹配模式或 ID。支持 `provider/id` 格式，可选追加 `:<thinking>` 指定思考级别 |
| `--api-key <key>` | 手动指定 API 密钥（默认从环境变量读取） |
| `--models <patterns>` | 逗号分隔的模型模式列表，用于交互模式中 Ctrl+P 切换模型。支持通配符（如 `anthropic/*`、`*sonnet*`）和模糊匹配 |
| `--thinking <level>` | 设置思考级别：`off`、`minimal`、`low`、`medium`、`high`、`xhigh`、`max` |
| `--list-models [search]` | 列出可用模型（可选模糊搜索过滤） |

### 提示词

| 选项 | 说明 |
|------|------|
| `--system-prompt <text>` | 自定义系统提示词（默认为编程助手提示词） |
| `--append-system-prompt <text>` | 向系统提示词追加文本或文件内容（可多次使用） |

### 运行模式

| 选项 | 说明 |
|------|------|
| `--mode <mode>` | 输出模式：`text`（默认，纯文本）、`json`（JSON 格式）、`rpc`（RPC 协议） |
| `--print, -p` | 非交互模式：处理完提示词后直接退出，不进入交互界面 |
| `--verbose` | 强制显示详细启动信息（覆盖 quietStartup 设置） |

### 会话管理

| 选项 | 说明 |
|------|------|
| `--continue, -c` | 继续上一次会话 |
| `--resume, -r` | 选择一个历史会话来恢复 |
| `--session <path\|id>` | 使用指定的会话文件或部分 UUID |
| `--session-id <id>` | 使用精确的项目会话 ID，若不存在则创建 |
| `--fork <path\|id>` | 将指定会话分叉（fork）为新会话 |
| `--session-dir <dir>` | 指定会话存储和查找的目录 |
| `--no-session` | 不保存会话（临时会话，用完即弃） |
| `--name, -n <name>` | 设置会话的显示名称 |

### 工具控制

| 选项 | 说明 |
|------|------|
| `--no-tools, -nt` | 默认禁用所有工具（内置和扩展工具全部关闭） |
| `--no-builtin-tools, -nbt` | 仅禁用内置工具，保留扩展/自定义工具 |
| `--tools, -t <tools>` | 逗号分隔的工具白名单，仅启用列出的工具（适用于内置、扩展和自定义工具） |
| `--exclude-tools, -xt <tools>` | 逗号分隔的工具黑名单，禁用列出的工具 |

### 扩展与技能

| 选项 | 说明 |
|------|------|
| `--extension, -e <path>` | 加载扩展文件（可多次使用） |
| `--no-extensions, -ne` | 禁用扩展自动发现（但通过 `-e` 显式指定的仍生效） |
| `--skill <path>` | 加载技能文件或目录（可多次使用） |
| `--no-skills, -ns` | 禁用技能的自动发现和加载 |
| `--prompt-template <path>` | 加载提示词模板文件或目录（可多次使用） |
| `--no-prompt-templates, -np` | 禁用提示词模板的自动发现和加载 |
| `--theme <path>` | 加载主题文件或目录（可多次使用） |
| `--no-themes` | 禁用主题的自动发现和加载 |

### 上下文与安全

| 选项 | 说明 |
|------|------|
| `--no-context-files, -nc` | 禁用 AGENTS.md 和 CLAUDE.md 的自动发现和加载 |
| `--approve, -a` | 信任项目本地文件（本次运行生效） |
| `--no-approve, -na` | 忽略项目本地文件（本次运行生效） |
| `--offline` | 禁用启动时的网络操作（等同于 `PI_OFFLINE=1`） |

### 其他

| 选项 | 说明 |
|------|------|
| `--export <file>` | 将会话文件导出为 HTML 后退出 |
| `--help, -h` | 显示帮助信息 |
| `--version, -v` | 显示版本号 |

> 扩展可以注册额外的命令行标志（例如 plan-mode 扩展注册的 `--plan`）。

---

## 内置工具（Built-in Tools）

| 工具名 | 功能 | 默认状态 |
|--------|------|----------|
| `read` | 读取文件内容 | 启用 |
| `bash` | 执行 bash 命令 | 启用 |
| `edit` | 通过查找/替换编辑文件 | 启用 |
| `write` | 写入文件（创建或覆盖） | 启用 |
| `grep` | 搜索文件内容（只读） | 默认关闭 |
| `find` | 按 glob 模式查找文件（只读） | 默认关闭 |
| `ls` | 列出目录内容（只读） | 默认关闭 |

---

## 使用示例

### 交互模式
```bash
pi
```
启动交互式 TUI 界面。

### 带初始提示词的交互模式
```bash
pi "List all .ts files in src/"
```
启动交互模式并发送第一条消息。

### 附加文件到消息
```bash
pi @prompt.md @image.png "What color is the sky?"
```
将 `prompt.md` 和 `image.png` 的内容附加到初始消息中。

### 非交互模式
```bash
pi -p "List all .ts files in src/"
```
处理完提示词后直接输出结果并退出。

### 多条消息
```bash
pi "Read package.json" "What dependencies do we have?"
```
交互模式下依次发送多条消息。

### 继续上次会话
```bash
pi --continue "What did we discuss?"
```

### 命名会话
```bash
pi --name "Refactor auth module"
```

### 指定提供商和模型
```bash
pi --provider openai --model gpt-4o-mini "Help me refactor this code"
```

### 使用 provider/id 格式（无需 --provider）
```bash
pi --model openai/gpt-4o "Help me refactor this code"
```

### 模型 + 思考级别简写
```bash
pi --model sonnet:high "Solve this complex problem"
```

### 限制可切换的模型列表
```bash
pi --models claude-sonnet,claude-haiku,gpt-4o
```

### 使用通配符限定提供商
```bash
pi --models "github-copilot/*"
```

### 固定思考级别的模型切换
```bash
pi --models sonnet:high,haiku:low
```

### 只读模式（禁止文件修改）
```bash
pi --tools read,grep,find,ls -p "Review the code in src/"
```

### 禁用特定工具
```bash
pi --exclude-tools ask_question
```

### 导出会话为 HTML
```bash
pi --export ~/.pi/agent/sessions/--path--/session.jsonl
pi --export session.jsonl output.html
```

---

## 环境变量

### AI 提供商 API 密钥

| 环境变量 | 说明 |
|----------|------|
| `ANTHROPIC_API_KEY` | Anthropic Claude API 密钥 |
| `ANTHROPIC_OAUTH_TOKEN` | Anthropic OAuth 令牌（API 密钥的替代方式） |
| `ANT_LING_API_KEY` | Ant Ling API 密钥 |
| `OPENAI_API_KEY` | OpenAI GPT API 密钥 |
| `AZURE_OPENAI_API_KEY` | Azure OpenAI API 密钥 |
| `AZURE_OPENAI_BASE_URL` | Azure OpenAI 基础 URL（如 `https://{resource}.openai.azure.com`） |
| `AZURE_OPENAI_RESOURCE_NAME` | Azure OpenAI 资源名称（替代 base URL 的方式） |
| `AZURE_OPENAI_API_VERSION` | Azure OpenAI API 版本（默认：v1） |
| `AZURE_OPENAI_DEPLOYMENT_NAME_MAP` | Azure OpenAI 模型到部署名的映射（逗号分隔） |
| `DEEPSEEK_API_KEY` | DeepSeek API 密钥 |
| `NVIDIA_API_KEY` | NVIDIA NIM API 密钥 |
| `GEMINI_API_KEY` | Google Gemini API 密钥 |
| `GROQ_API_KEY` | Groq API 密钥 |
| `CEREBRAS_API_KEY` | Cerebras API 密钥 |
| `XAI_API_KEY` | xAI Grok API 密钥 |
| `FIREWORKS_API_KEY` | Fireworks API 密钥 |
| `TOGETHER_API_KEY` | Together AI API 密钥 |
| `OPENROUTER_API_KEY` | OpenRouter API 密钥 |
| `AI_GATEWAY_API_KEY` | Vercel AI Gateway API 密钥 |
| `ZAI_API_KEY` | ZAI Coding Plan API 密钥（全球） |
| `ZAI_CODING_CN_API_KEY` | ZAI Coding Plan API 密钥（中国） |
| `MISTRAL_API_KEY` | Mistral API 密钥 |
| `MINIMAX_API_KEY` | MiniMax API 密钥 |
| `MOONSHOT_API_KEY` | Moonshot AI（月之暗面）API 密钥 |
| `OPENCODE_API_KEY` | OpenCode Zen/Go API 密钥 |
| `KIMI_API_KEY` | Kimi For Coding API 密钥 |
| `CLOUDFLARE_API_KEY` | Cloudflare API 令牌（Workers AI 和 AI Gateway） |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare 账户 ID（两者都需要） |
| `CLOUDFLARE_GATEWAY_ID` | Cloudflare AI Gateway slug（AI Gateway 必需） |
| `QWEN_TOKEN_PLAN_API_KEY` | 通义千问 Token Plan API 密钥（国际区域） |
| `QWEN_TOKEN_PLAN_CN_API_KEY` | 通义千问 Token Plan API 密钥（中国区域） |
| `XIAOMI_API_KEY` | 小米 MiMo API 密钥（api.xiaomimimo.com 计费） |
| `XIAOMI_TOKEN_PLAN_CN_API_KEY` | 小米 MiMo Token Plan API 密钥（中国区域） |
| `XIAOMI_TOKEN_PLAN_AMS_API_KEY` | 小米 MiMo Token Plan API 密钥（阿姆斯特丹区域） |
| `XIAOMI_TOKEN_PLAN_SGP_API_KEY` | 小米 MiMo Token Plan API 密钥（新加坡区域） |

### AWS Bedrock

| 环境变量 | 说明 |
|----------|------|
| `AWS_PROFILE` | Amazon Bedrock 使用的 AWS 配置文件 |
| `AWS_ACCESS_KEY_ID` | AWS 访问密钥 |
| `AWS_SECRET_ACCESS_KEY` | AWS 秘密密钥 |
| `AWS_BEARER_TOKEN_BEDROCK` | Bedrock API 密钥（Bearer Token 方式） |
| `AWS_REGION` | AWS 区域（如 `us-east-1`） |

### Pi 配置相关

| 环境变量 | 说明 |
|----------|------|
| `PI_CODING_AGENT_DIR` | 配置目录（默认：`~/.pi/agent`） |
| `PI_CODING_AGENT_SESSION_DIR` | 会话存储目录（被 `--session-dir` 覆盖） |
| `PI_PACKAGE_DIR` | 覆盖包目录路径（用于 Nix/Guix store 路径） |
| `PI_OFFLINE` | 设为 `1`/`true`/`yes` 时禁用启动网络操作 |
| `PI_TELEMETRY` | 设为 `1`/`true`/`yes` 或 `0`/`false`/`no` 覆盖遥测设置 |
| `PI_SHARE_VIEWER_URL` | `/share` 命令的基础 URL（默认：`https://pi.dev/session/`） |

---

## 核心概念说明

### 思考级别（Thinking Level）
控制模型在回答前"思考"的深度。从 `off`（不思考）到 `max`（最大思考量），级别越高，模型推理越深入，但响应速度越慢、token 消耗越多。

### 会话（Session）
每次交互都会创建一个会话文件，记录完整的对话历史。可以通过 `--continue` 继续最近会话，`--resume` 选择历史会话，`--fork` 从某个会话分叉出新会话。

### 扩展（Extension）
扩展是为 pi 添加额外功能的插件，可以注册新的工具、命令或行为。通过 `pi install` 安装，`--extension` 手动加载。

### 技能（Skill）
技能是 Markdown 文件，教 AI 如何执行特定任务。比扩展更轻量，适合定义工作流程和最佳实践。

### 提示词模板（Prompt Template）
预定义的提示词模板，可以快速复用常见的提示词结构。

### 工具白名单/黑名单
- `--tools`：白名单模式，只启用列出的工具
- `--exclude-tools`：黑名单模式，禁用列出的工具，其余保持可用
- 两者结合可实现精细的工具权限控制，例如只读模式：`--tools read,grep,find,ls`
