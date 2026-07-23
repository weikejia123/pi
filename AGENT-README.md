# AGENT-README: pi — AI CLI Coding Agent

> **分析版本**: V1-20260724
> **分析框架**: [ANALYSIS-DIR-CODER-AGENT.md](../../../ANALYSIS-DIR-CODER-AGENT.md) (PV1-20260724)
> **项目路径**: `/Users/weikejia/CODE/my-agent-group/projects/coder-agent/pi/`

---

## 1. 身份与定位

| 指标 | 内容 |
|------|------|
| **名称** | pi |
| **Tagline** | "Minimal terminal coding harness." |
| **定位语** | "Adapt pi to your workflows, not the other way around" — 极简核心 + 可扩展 |
| **设计哲学** | Core is minimal; extensions, skills, themes 是扩展方式；不做 Sub-agent/Plan mode 等内置 |
| **许可证** | 专有（非标准，需确认具体协议） |
| **运行时语言** | TypeScript (Node.js / Bun) |
| **构建系统** | npm workspaces + esbuild |
| **上游** | `github:earendil-works/pi` (Fork: `weikejia123/pi`) |
| **发布方式** | npm (`@earendil-works/pi-coding-agent`) + Bun standalone binary |
| **社区** | Discord, pi.dev 生态, Hugging Face 会话分享 |

**核心权衡**: TypeScript 生态丰富性 vs 内存/启动性能; 最小核心 + 扩展系统 vs 内置全功能

---

## 2. 核心架构

| 指标 | 内容 |
|------|------|
| **运行时** | Node.js ≥ 18 + Bun (可选) |
| **Monorepo 包** | 7 个 workspaces: `coding-agent`, `agent`, `ai`, `tui`, `orchestrator`, `server`, `storage` |
| **核心包** | `@earendil-works/pi-coding-agent` (CLI), `@earendil-works/pi-agent-core` (运行时), `@earendil-works/pi-ai` (Provider 抽象), `@earendil-works/pi-tui` (TUI 框架) |
| **Agent 主循环** | 提示词构建 → `pi-ai` Provider 调用 (流式) → 工具执行 → 状态更新 → 循环 (在 `pi-agent-core` 中实现) |
| **系统提示词构建** | 静态基础提示 + 动态上下文注入（AGENTS.md / 会话历史 / 工具定义） |
| **上下文注入文件** | `AGENTS.md` (项目级)、`~/.pi/agent/` 用户级配置 |
| **状态管理** | 内部 Zustand-style store (非 Zustand, 自实现) |

**架构亮点**: 四层分离清晰（CLI / Agent Runtime / AI Provider / TUI），Provider 抽象统一多 API 协议

---

## 3. Provider 与模型支持

| 指标 | 内容 |
|------|------|
| **原生 Provider 数量** | 20+ |
| **订阅 OAuth** | Anthropic Claude Pro/Max, OpenAI ChatGPT Plus/Pro (Codex), GitHub Copilot |
| **API Key 直连** | Anthropic, OpenAI, Azure OpenAI, DeepSeek, Google Gemini, Google Vertex, Amazon Bedrock, Mistral, Groq, Cerebras, Cloudflare AI Gateway, Cloudflare Workers AI, xAI, OpenRouter, Vercel AI Gateway, ZAI, OpenCode Zen, OpenCode Go, Hugging Face, Fireworks, Together AI, Kimi, MiniMax, Xiaomi MiMo |
| **自定义 Provider** | 通过 `~/.pi/agent/models.json` 配置自定义模型; 或开发 Extension 实现完整自定义 Provider |
| **本地模型** | llama.cpp router server 支持 (`/login llama.cpp`, `/llama` 管理) |
| **模型目录** | 自动刷新，`pi update --models` 强制刷新 |

**Provider 丰富度**: ★★★★☆ (20+ Provider, 覆盖主流 API + OAuth 订阅 + 本地)

---

## 4. 工具系统

| 指标 | 内容 |
|------|------|
| **默认内置工具** | 4 个核心工具: `read`, `write`, `edit`, `bash` |
| **工具注册机制** | 在 `pi-agent-core` 中注册; Skills/Extensions 可以添加更多工具 |
| **MCP 支持** | 通过 Extensions 支持 MCP Server 集成 |
| **工具权限模型** | 无内置权限系统 — 默认以启动进程权限运行; 建议容器化隔离 |
| **第三方工具扩展** | Extensions (TypeScript API), Skills (配置驱动), Pi Packages (npm 分发) |

**工具生态成熟度**: ★★★☆☆ (核心工具极简, 主要通过扩展系统增强)

---

## 5. 用户界面与交互

| 指标 | 内容 |
|------|------|
| **TUI 技术栈** | 自研 `@earendil-works/pi-tui` — 差分渲染 (differential rendering) |
| **交互模式** | 交互式 / Print JSON (`-p --json`) / RPC (进程集成) / SDK (嵌入式) |
| **编辑器功能** | 多行 (Shift+Enter), 文件引用 (`@` 模糊搜索), 路径补全 (Tab), 外部编辑器 (Ctrl+G), Bash 命令 (`!`/`!!`), 图片粘贴 |
| **快捷键系统** | 完善的双键/组合键系统; 可通过 `~/.pi/agent/keybindings.json` 自定义 |
| **主题系统** | 内置主题 + 自定义主题 (`themes`), 暗/亮色检测 |
| **消息队列** | Steering (当前轮次后) / Follow-up (全部完成后) / 排队消息编辑 (Alt+Up) |

**TUI 亮点**: 自研差分渲染引擎（非 Ink），启动速度中等; message queue 机制提供异步引导能力

---

## 6. 会话管理

| 指标 | 内容 |
|------|------|
| **存储格式** | JSONL (每行一个 entry，带 id + parentId) |
| **存储位置** | `~/.pi/agent/sessions/` 按工作目录组织 |
| **分支能力** | `/tree` 树状导航 — 折叠/展开/搜索, 过滤模式, 标签书签 |
| **Fork/Clone** | `/fork` (从历史点创建新会话), `/clone` (复制当前分支为新会话), `--fork` CLI 参数 |
| **Compaction** | 自动 + 手动 (`/compact`), 定期/溢出触发; 有损但完整历史保留在 JSONL |
| **Session Resume** | `/resume`, `pi -c` (最近), `pi -r` (浏览), `--session` (指定) |
| **Export/Import** | HTML / JSONL (`/export`, `/import`, `/share` gist) |

**会话管理成熟度**: ★★★★★ (树状分支、Fork/Clone/Resume、自动压缩 + 完整历史)

---

## 7. 定制化与生态

| 指标 | 内容 |
|------|------|
| **Skills** | 配置驱动的能力包; `/skill:name` 调用; 自动语义匹配加载 |
| **Prompt Templates** | 模板语法; `/templatename` 展开; 可在 skills 中引用 |
| **Extensions** | TypeScript API, 可注册命令/工具/UI 组件/Provider; 生命周期: load/init/shutdown |
| **Themes** | 自定义主题定义; 语法高亮/配色方案 |
| **Pi Packages** | 通过 npm 或 git 分享 skills/templates/extensions/themes 的组合包 |
| **自修改能力** | 通过 `/reload` 热重载 extensions/skills/templates/themes; 可要求 Agent 生成扩展 |

**生态成熟度**: ★★★★☆ (四层扩展体系+包管理, 但无官方 Marketplace)

---

## 8. 记忆与上下文

| 指标 | 内容 |
|------|------|
| **长期记忆** | 无内置向量记忆系统; 依赖 AGENTS.md + 会话 JSONL 回顾 |
| **项目上下文** | `AGENTS.md` 文件自动加载; 多个 AGENTS.md 层级合并 |
| **会话间复用** | `/resume` 浏览历史会话; 无自动语义召回 |
| **上下文窗口管理** | 自动 + 手动 Compaction; Token 使用监控 (↑↓RW/CH) |
| **上下文大小** | 取决于当前模型上下文窗口 |

**记忆能力**: ★★☆☆☆ (无向量记忆/语义搜索, 依赖文件上下文 + JSONL 历史)

---

## 9. 差异化功能

| 功能 | 支持情况 | 说明 |
|------|---------|------|
| 多 Agent 协同 | ❌ | 设计哲学不内置; 可通过扩展实现 |
| 目标驱动工作流 | ❌ | 无 Plan/Goal 模式 |
| Computer Use | ❌ | 无内置 |
| 浏览器自动化 | ❌ | 无内置 |
| 语音模式 | ❌ | 无内置 |
| 远程控制 | ❌ | 但 SDK 模式可用于嵌入; 有 chat 变体 (`pi-chat`) |
| 制品托管 | ❌ | 无 Artifact 系统 |
| 监控 | ❌ | 无内置 (但 `/share` 支持 Hugging Face 会话上传) |
| 容器化 | ⚠️ 有文档 | `containerization.md` 提供三种模式 (Gondolin/Docker/OpenShell) |

**差异化定位**: 极简内核 + 可扩展 = 用户自构建; 不是"开箱即用全功能", 而是"按需装配"

---

## 10. 性能

| 指标 | 数据 | 来源 |
|------|------|------|
| **启动耗时 (首次帧)** | ~590.7 ms (Range: 369.6–934.8 ms) | jcode README 对比数据 |
| **启动耗时 (首次输入)** | ~596.4 ms (Range: 373.9–955.2 ms) | jcode README 对比数据 |
| **内存 (1 会话)** | ~144.4 MB PSS | jcode README 对比数据 |
| **内存 (10 会话)** | ~833.0 MB PSS (每会话增量 ~76.5 MB) | jcode README 对比数据 |
| **构建方式** | esbuild 打包 | — |
| **二进制体积** | npm 包 + 运行时依赖 | — |

**性能评级**: ★★★☆☆ (中等; Node.js 生态正常水平, 慢于 Rust/Go 原生)

---

## 11. 安全

| 指标 | 内容 |
|------|------|
| **权限模型** | 无内置 — 全权运行; 建议容器化 |
| **沙箱支持** | 文档提供三种方案: Gondolin (micro-VM), Docker, OpenShell |
| **供应链安全** | npm lockfile + shrinkwrap; `--ignore-scripts` 安装; `min-release-age=2`; 可审计 lockfile 变更; CI audit 检查 |
| **签名** | GitHub Release SHA256SUMS; Bun binary 签名 |

**安全评级**: ★★★☆☆ (无内置权限系统, 但供应链安全实践较好)

---

## 12. 开发与社区

| 指标 | 内容 |
|------|------|
| **测试框架** | Vitest (单元/集成), `test.sh` (LLM 无关测试) |
| **测试策略** | QA gate: `npm run check` + `./test.sh`; E2E 使用 faux provider |
| **CI/CD** | GitHub Actions (CI + Build Binaries + Publish npm) |
| **社区模式** | 严格: 新 contributor Issue/PR 自动关闭; lgtm/lgtmi 审批流程 |
| **贡献指南** | CONTRIBUTING.md + AGENTS.md (严格的开发规则) |
| **发布工程** | Lockstep versioning (`patch`=fix+add, `minor`=breaking); 自动化 CHANGELOG; `release:local` smoke test 流水线 |

**社区活跃度**: 封闭但精良 (上游社区有争议的 Issue 管理, 但质量门槛极高)

---

## 版本演进

### V1-20260724 — 初始分析
- **分析范围**: 基于 pi monorepo 源码 + 文档的全面分析
- **数据来源**: README.md, AGENTS.md, packages/coding-agent/README.md, jcode 性能对比数据
- **关键发现**: pi 的核心竞争力在于极简内核 + 四层扩展体系; 劣势在于内存/启动性能, 无内置记忆系统
- **分析框架**: 12 维度, PV1

---

## 横向对比摘要

| 核心维度 | pi |
|---------|:---:|
| 运行时 | Node.js / Bun (TS) |
| 哲学 | 最小核心 + 扩展 |
| Provider 数 | 20+ |
| 内置工具类型 | 4 (极简) |
| MCP | 通过 Extension |
| 记忆系统 | ❌ |
| Swarm | ❌ |
| 启动耗时 | ~590ms (中) |
| 内存(1会话) | ~144 MB (中) |
| 生态成熟度 | ★★★★☆ |
| 安全性 | 无内置权限 |
| 代码质量 | ★★★★★ |
