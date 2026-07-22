# LLM 输出 JSON 结构设计方法论

> 从 wake-base-llm 稳定 vs wake-activity 不稳定 的对比中提炼

## 起源

wake-activity.sh 使用了与 wake-base-llm.sh 完全相同的技术栈——pi agent + ollama/qwen3.6:35b + 同样的一段 prompt 去让模型分析项目并输出 JSON。但 base-llm 长期稳定，activity 却反复失败（3 次重试全被 jq validation 丢弃）。

对比后发现问题不在模型，在 JSON Schema 的验证设计。

## 两个 Schema 的对比

### wake-base-llm.sh 验证（稳定）

```
.identity.type                       → type == "string"        # 2 层
.identity.one_liner                  → type == "string"
.identity.confidence                 → type == "number"
.domains                             → type == "array"         # 不穿透数组元素
.tech_summary.primary_language       → type == "string"
.critical_paths                      → type == "array", length <= 5  # 不穿透数组元素
```

只检查 6 个**顶层/二级字段的类型**，不穿透到数组元素内部做类型校验。

### wake-activity.sh 验证（不稳定）

```
.one_liner              → type == "string", length > 0
.themes                 → type == "array", length >= 1
.themes[].theme         → type == "string"           ← 穿透到数组元素
.themes[].commits       → type == "number"           ← 最脆弱的点
.themes[].summary       → type == "string"
.themes[].representative → type == "array"
```

6 个顶层检查 + **4 个对数组元素内部的类型穿透检查**。jq 的 `themes[]` 是 foreach 语义——对数组每一个元素逐一校验，任何一个不通过则全局失败。

## 核心结论：嵌套数组穿透检查是模型不稳定的根源

### 出错面放大

base-llm 的失败面是 **6 个独立字段**——模型跑偏一个字段只丢那个 check，其他字段不影响。

activity 的失败面是 **4 个 theme × 4 个字段 = 16 次子检查**——任何一个 theme 的任何一个字段的类型不对（如 `"commits": "5"` 而非 `5`），整条输出被丢弃。

### 模型最容易出错的地方

| 模型天然倾向 | 举例 | 对验证的影响 |
|-------------|------|-------------|
| 数字写成字符串 | `"commits": "4"` 而非 `4` | type == "number" 失败 |
| 漏掉某个字段 | representative 数组为空 | type == "array" 失败（可为空数组） |
| 字段名变形 | `"commit_count": 4` 而非 `"commits": 4` | 整条 jq 找不到该字段 |
| 多加围栏或说明文字 | 在 JSON 前后写 "以下是分析结果" | python3 提取级可能剥离，但围栏外文字会使 awk 提取失败 |

### 为什么 base-llm 的嵌套就稳定

base-llm 也有嵌套结构（`identity → confidence` 是 3 层），但它的特点是：
- **不穿透数组**：`critical_paths` 只检查 `type == "array"`，不查 `critical_paths[].path` 的类型
- **不同字段之间的独立性高**：`identity` 内部的 4 个字段互不影响
- **没有 foreach 级联校验**：不存在"一个元素不对导致数组级别断裂"的情况

## 设计原则

### 原则一：尽量扁平

LLM 输出 JSON 的理想结构是 2 层以内，避免 3 层以上嵌套。

```
推荐:
{
  "one_liner": "...",
  "theme_1": "...",     ← 平铺，每个字段独立
  "theme_1_commits": 4,
  "theme_2": "...",
  "theme_2_commits": 3
}

避免:
{
  "themes": [           ← 嵌套数组，需要穿透验证
    {"theme": "...", "commits": 4},
    {"theme": "...", "commits": 3}
  ]
}
```

平铺的成本是字段名变多（`theme_N` 系列），但每个字段独立验证，一个字段出错不影响其他。

### 原则二：不穿透数组元素做类型校验

如果因为程序消费需要保留数组结构，则验证策略应该是：

```
# 正确做法：只校验数组本身是否存在、是数组
.themes → type == "array"

# 拿到 JSON 后，在 shell/程序层做宽容提取
jq '.themes[] | {theme, commits: (.commits | tonumber? // .)}'
```

不把 `themes[].commits | type == "number"` 写在 validation 里——这种穿透校验把模型的小偏差放大成整条丢弃。

### 原则三：数字字段接受 string fallback

LLM 经常把数字输出成字符串 `"5"` 而非 `5`。设计时应接受两种类型：

```jq
.themes[] | (.commits | type == "number" or type == "string")
```

或者在提取时做宽容转换：

```jq
(.commits | tonumber?) // .  # 尝试转数字，失败则保留原值
```

### 原则四：属性数量越大，验证要求越低

如果一个字段出现在 N 个数组元素中（如 themes[]），它的出错概率是单字段的 N 倍。验证设计应根据卡片数调整严格程度：

| 字段出现次数 | 验证策略 |
|-------------|---------|
| 1 次（全局字段） | 可以严格（type + length > 0） |
| 2-5 次 | 放宽到 type only, 不检查 length |
| 5+ 次 | 只检查存在性，或完全留下次验证 |

### 原则五：长度约束只加在全局字段

`length >= 1`/`length > 0` 只加在 `one_liner` 这样的单例字段上。对数组内的字段不加长度约束——模型偶尔输出空数组或空字符串时不应成为拒绝整条 JSON 的理由。

## 总结：两种 Schema 设计的实用模板

### 宽松版（推荐用于 LLM 输出验证）

```jq
# 只检查：字段存在 + 类型正确
(.one_liner | type == "string") and
(.field2 | type == "string" or type == "number") and
(.array_field | type == "array")
# 不做 foreach 穿透，不做 length 检查
```

### 严格版（仅在需要确保证据完整时使用）

```jq
# 全局字段可以严格
(.one_liner | type == "string" and length > 0) and

# 数组只检查形状
(.themes | type == "array") and

# 不渗透到 themes[] 内部 —— 预留消费端二次宽容提取
```

## 对照表

| 设计方案 | wake-base-llm | wake-activity | 推荐做法 |
|---------|--------------|--------------|---------|
| 嵌套层级 | 3 层但不穿透数组 | 3 层 + 穿透数组 | ≤2 层，或 3 层但不穿透数组 |
| 数组的内部字段 | 不检查 | 检查 type | 不检查，留到程序层宽容提取 |
| 数字字段 | 1 个顶层字段 | N 个嵌套字段 | 接受 string fallback |
| length 约束 | 无 | length >= 1 | 仅加在全局字段 |
| 验证失败后果 | 不会因此失败 | 整条输出丢弃 | 让步提取，不整条丢弃 |
| 稳定性 | 稳定 | 不稳定（3次重试全失败） | 参考 base-llm 设计 |

---

结论：**扁平结构 + 避免嵌套数组的 foreach 类型穿透校验 + 数字字段宽容处理**，是让 LLM 输出 JSON 稳定的关键。
