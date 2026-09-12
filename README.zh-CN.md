# OhNews

[English](README.md) | 简体中文

OhNews 是一款原生 macOS 新闻阅读应用，当前支持 Hacker News，提供可选的中文 AI 摘要与应用内正文阅读。Hacker News 是它接入的第一个信息源。

它面向这样一类使用方式：快速浏览 Hacker News，理解一条内容背后的讨论，并直接打开原文，而不必在多个浏览器标签之间来回切换。

OhNews 是采用 **GNU Affero 通用公共许可证 v3** 的自由开源软件，并采用双授权模式：无法接受 AGPL 约束的场景（例如嵌入闭源产品）可另行购买商业授权。详见 [`LICENSE`](LICENSE) 与 [`LICENSING.md`](LICENSING.md)。

## 安装

OhNews 以 macOS 磁盘映像（DMG）形式分发，要求 macOS 15.0 或更高版本。

1. 打开下载得到的 `.dmg` 文件。
2. 将 `OhNews.app` 拖入 `Applications` 文件夹。
3. 从 `Applications` 或 Spotlight 启动 OhNews。

正式发布版本使用 Developer ID 证书签名并通过 Apple 公证。在公证版本就绪之前，macOS 的 Gatekeeper 可能提示开发者身份不明；遇到这种情况时，在 Finder 中按住 Control 点击应用，选择一次「打开」即可。

不做任何配置，应用即可作为完整的 Hacker News 阅读器使用。AI 摘要为可选功能，需要自行配置服务商凭据。

## 当前版本

0.1.0 版本聚焦于完整的阅读闭环：

- Hacker News 的 Top、Best、New、Ask HN、Show HN 榜单
- 本地缓存，支持快速启动与已加载内容的离线浏览
- 已读状态持久化
- 可选：为列表中前 12 条内容生成 AI 摘要
- 中文标题、中文摘要、主题标签、评论区共识
- 兼容 OpenAI 接口的服务商：DeepSeek、OpenAI、Ollama 及自定义地址
- API Key 存放于 macOS 钥匙串
- 应用内正文阅读，正文识别使用 Mozilla Readability.js
- 对付费墙、PDF、重 JavaScript 页面与被拦截站点的优雅降级

0.1.0 版本不包含付费功能门控、激活校验、账号同步或云端存储。

## 路线图

- 接入 Hacker News 之外的信息源
- 详情级深度分析，以及每日首页简报
- Windows 客户端
- 全局搜索与收藏/稍后读

计划会随实际进展调整，不代表承诺的交付时间。

## AI 配置

AI 是可选功能。未配置服务商时，OhNews 仍是一个完整可用的 Hacker News 阅读器。

在工具栏打开「设置」，或使用 `Command-,`：

1. 选择服务商预设。
2. 填写该服务商兼容 OpenAI 的接口地址与模型名。
3. 服务商需要密钥时填写 API Key。
4. 保存前先用「测试连接」验证。

默认预设为 DeepSeek：

- 接口地址：`https://api.deepseek.com/v1`
- 摘要模型：`deepseek-v4-flash`
- 深度分析模型（预留，后续版本启用）：`deepseek-v4-pro`

Ollama 可使用本机地址，例如 `http://localhost:11434/v1`，模型名须与本机已安装的模型一致。

密钥存放于 macOS 钥匙串，不会写入 UserDefaults、仓库或应用日志。关闭 AI 或未配置服务商时，OhNews 不会向任何 AI 服务商发送正文或评论内容。

## 数据与隐私

Hacker News 数据来自公开的 Firebase API 与 Algolia HN Search API。已加载的内容、已读状态与摘要保存在应用本地的 Application Support 容器中。

启用 AI 摘要后，标题、元信息与有长度上限的部分 HN 评论会发送至用户自行配置的服务商。该服务商的留存策略与数据处理方式适用其自身的条款与隐私政策。

文章页面在本地 WKWebView 中直接加载以做阅读模式抽取，OhNews 不运营服务端正文代理。

## 阅读器限制

第三方站点可能要求订阅、登录、通过 JavaScript 校验，或只能按特定浏览器路径渲染。遇到这些情况时，应用可能无法抽取正文，会降级为显示标题、是否可查看 HN 讨论，以及一个在系统浏览器中打开原链接的按钮。

付费墙指外部媒体将正文限制在订阅或登录之后。这属于来源站点的限制，不是 OhNews 的收费功能。

应用对请求做了节流，并对评论与正文处理设定了长度上限。它面向个人阅读，不用于自动化批量抓取或转载第三方内容。

## 从源码构建

Xcode 工程由 `project.yml` 通过 XcodeGen 生成。XcodeGen 是构建期工具，生成出的工程也一并纳入版本管理。

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project OhNews.xcodeproj \
  -scheme OhNews \
  -configuration Debug \
  -destination 'platform=macOS' build
```

之后用 Xcode 打开 `OhNews.xcodeproj`，运行 `OhNews` scheme。

开发需要 Xcode 26.3 或更高版本，以及 Swift 6 语言模式。

纯逻辑层有独立的测试目标，不必启动应用即可验证：

```bash
swift test --package-path Packages/OhNewsKit
```

在 `OhNews/` 下新增或删除源文件后，先运行 `xcodegen generate` 再构建，以保证生成的 Xcode 工程同步。

## 许可与法律文件

OhNews 以 **GNU Affero 通用公共许可证 v3** 开源（[`LICENSE`](LICENSE)）。你可以免费使用、修改与再分发，**包括商业用途**，前提是沿用同一许可并提供完整对应源码；若把修改版作为网络服务提供给他人使用，还须向使用者提供源码（AGPL 第 13 条）。

如果 AGPL 不适合你的情况（例如要把 OhNews 嵌入闭源产品），可购买商业授权，详见 [`LICENSING.md`](LICENSING.md)。

贡献代码需要授予再授权权利，以便项目同时提供两种授权；见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

应用包含以 Apache License 2.0 授权的 Mozilla Readability.js 0.6.0。Apache-2.0 与 AGPL 兼容，因此该组件可以随本作品分发，其归属要求保持不变。归属声明与完整第三方许可文本见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) 与 [`LICENSES/Apache-2.0.txt`](LICENSES/Apache-2.0.txt)。
