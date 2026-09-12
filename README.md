# OhNews

[简体中文](README.md) | [English](README.en.md)

OhNews 是一个原生的 macOS 新闻阅读器。默认接入 Hacker News，也可以添加任意 RSS / Atom 订阅源，把它们放在同一个三栏界面里阅读；可选的中文 AI 摘要用来帮你判断一条内容值不值得打开。

它面向的使用场景是：快速扫一遍今天有什么、看懂一条内容在讨论什么、需要时直接读到正文，而不用在十几个浏览器标签之间来回切换。

---

## 安装

要求 **macOS 15.0 或更高版本**。安装包按处理器架构分开发布，请选择与你的机器对应的那个：

| 文件 | 适用机型 |
| --- | --- |
| `OhNews-<版本>-arm64.dmg` | Apple Silicon（M 系列芯片） |
| `OhNews-<版本>-x86_64.dmg` | Intel 芯片 |

安装步骤：

1. 打开下载好的 `.dmg`；
2. 把 `OhNews.app` 拖进 `Applications`；
3. 从「启动台」或「应用程序」里打开。

**首次打开会被系统拦截。** 目前的安装包没有使用 Apple 开发者证书签名、也未经过公证，macOS 会提示「无法验证开发者」。解决办法是：在 Finder 里**按住 Control 点击应用图标**，选择「打开」，再在弹窗里确认一次；之后就能正常双击启动。如果 Control-click 后仍然打不开，到「系统设置 → 隐私与安全性」里点「仍要打开」。

应用开箱即用，不配置任何东西也能完整阅读 Hacker News 和订阅源。AI 摘要需要你自己的接口凭据，属于可选项。

---

## 功能

### 多信息源

- **Hacker News**：首页、最佳、最新、提问、展示五个榜单。
- **RSS / Atom**：可以添加任意订阅源，在侧栏按来源分组管理，支持重命名与删除。
- 每个来源有自己的频道，条目 ID 带来源前缀，不同来源的内容不会互相覆盖。

### 列表与刷新

- 切换频道只读本地缓存，不会每次切换都联网。
- 冷启动刷新一次；当前频道每 4 小时自动刷新一次；也可以随时手动刷新。
- 刷新采用**增量合并**：新条目从顶部插入，已有条目原地更新分数与评论数，列表不会整片闪动。
- 列表条数可选 **30 / 50 / 100** 条。
- 已读状态、订阅配置、侧栏选中的频道都会保留。
- 设置里会显示缓存占用，并可一键清除（订阅配置与各项偏好不受影响）。

### AI 摘要（可选）

- 生成范围可选：**只生成最前面若干条**（默认 12 条，控制调用成本）、**生成全部**、或者**完全不自动生成**。
- 在列表里**右键任意条目**可以单独生成或重新生成摘要，不受自动生成的条数限制。
- 摘要包含中文标题、中文摘要、主题标签和评论共识。
- 摘要按条目、模型与提示词版本缓存，换模型会自动重新生成。
- AI 状态会区分「没有密钥」「密钥读不出来」「配置不完整」「请求失败」，一次性的失败可以关闭。

### 阅读器

- 应用内直接读正文，正文抽取用 Mozilla Readability.js。
- 抓不到正文时逐级降级：保留标题、提示是否存在讨论区、并提供在系统浏览器中打开的入口。
- 阅读器排版针对长文优化：正文宽度约 720px、行高 1.9。

### 界面

- 极简杂志风格：纯纸白底、墨黑文字、衬线标题、等宽大写的小字元信息，条目之间用发丝线分隔。
- **深浅色一键切换**（主窗口工具栏），设置里也可以选择「跟随系统 / 浅色 / 深色」。
- 支持方向键在列表中移动选择。
- 所有动效都遵循系统的「减少动态效果」设置。

---

## AI 摘要配置

AI 是可选的。不配置时 OhNews 就是一个完整的阅读器。

从工具栏或 `Command-,` 打开设置：

1. 选择供应商预设；
2. 填写 OpenAI 兼容的接口地址与模型名；
3. 需要密钥的供应商填入 API Key；
4. 保存前建议先点「测试连接」，它会用一条极短的内容真实调用一次接口。

默认预设是 DeepSeek：

- 接口地址：`https://api.deepseek.com/v1`
- 摘要模型：`deepseek-v4-flash`

也可以使用本地模型，例如 Ollama 的 `http://localhost:11434/v1`，模型名需与本机已安装的模型一致。

密钥保存在 macOS 钥匙串中，不写入配置文件、不进仓库、不落日志。

> **提示**：应用每次重新构建后签名会变化，钥匙串授权可能失效，表现为界面提示「无法读取 API Key」。这时到设置里重新保存一次即可恢复，密钥本身没有丢失。正式分发的安装包不受影响。

---

## 数据与隐私

- Hacker News 数据来自公开的 Firebase API 与 Algolia HN Search API；订阅源内容直接从你填写的地址抓取。
- 已加载的条目、已读状态和摘要缓存在应用自己的容器目录里。
- 启用 AI 摘要时，条目标题、元信息以及**有数量上限**的评论会被发送到你自己配置的服务商。该服务商如何留存和处理这些数据，适用它自己的条款与隐私政策。
- 正文在本地的一个 WKWebView 中加载以做阅读模式抽取，OhNews 不运营任何服务端代理。
- 应用对请求做了节流，评论与正文处理都有上限，定位是个人阅读工具，不是批量抓取或再分发第三方内容的工具。

---

## 已知限制

- **付费墙与登录**：第三方站点可能要求订阅、登录、通过 JavaScript 挑战，或依赖特定浏览器渲染路径，这些情况下可能取不到正文。这里的「付费墙」指的是外部站点的限制，不是 OhNews 的收费功能——OhNews 本身没有付费功能。
- **评论树**：目前摘要会参考评论共识，但还不能完整浏览评论树，属于后续计划。
- **应用签名**：当前发布包为 ad-hoc 签名、未公证，因此需要上面的手动放行步骤。

---

## 从源码构建

Xcode 工程由 `project.yml` 经 XcodeGen 生成，生成结果同时纳入了版本管理。

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project OhNews.xcodeproj \
  -scheme OhNews \
  -configuration Debug \
  -destination 'platform=macOS' build
```

也可以直接用 Xcode 打开 `OhNews.xcodeproj`，运行 `OhNews` scheme。开发需要 Xcode 26.3 或更高版本，使用 Swift 6 语言模式。

纯逻辑层在独立的 Swift Package 里，不启动应用即可测试：

```bash
swift test --package-path Packages/OhNewsKit
```

在 `OhNews/` 下新增或删除源文件后，先跑一次 `xcodegen generate` 再构建，否则生成的工程不会包含新文件。

打包双架构安装包：

```bash
scripts/build-dmg.sh              # 两个架构都打
scripts/build-dmg.sh arm64        # 只打 Apple Silicon
scripts/build-dmg.sh x86_64       # 只打 Intel
```

产物输出到 `dist/OhNews-<版本>/`。若要正式分发，设置 `SIGN_IDENTITY` 与 `NOTARY_PROFILE` 环境变量即可启用签名与公证；凭据只通过环境变量和钥匙串传入，不写进仓库。

---

## 项目结构

```text
OhNews/                 应用本体（SwiftUI）
  App/                  应用状态与配置持久化
  Models/               展示用的模型扩展
  Services/             网络、正文抽取、AI 调用、钥匙串
  Support/              设计令牌、主题、辅助类型
  Views/                界面
  Resources/            阅读器样式、Readability.js、第三方声明
Packages/OhNewsKit/     纯逻辑层（解析、缓存、提示词构建）
  Sources/OhNewsKit/
  Tests/OhNewsKitTests/
scripts/build-dmg.sh    双架构安装包脚本
project.yml             XcodeGen 工程定义（版本号唯一来源）
```

---

## 后续计划

以下是可能的方向，不代表承诺的交付时间：

- 评论树阅读，把讨论区完整呈现出来
- 详情级的 AI 解读与每日简报
- OPML 导入导出，方便从其他阅读器迁移订阅
- 搜索、收藏与稍后读
- 更多信息源
- Windows 客户端

---

## 许可

OhNews 以 **MIT 许可证**开源，全文见 [`LICENSE`](LICENSE)。你可以自由使用、修改和再分发，包括用于商业项目和闭源产品，唯一要求是保留版权声明与许可文本。

欢迎贡献代码，提交前提请阅读 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

应用内置 Mozilla Readability.js 0.6.0（Apache License 2.0）。归属声明与完整第三方许可文本见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) 与 [`LICENSES/Apache-2.0.txt`](LICENSES/Apache-2.0.txt)。
