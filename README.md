# HeyNews

HeyNews is a native macOS Hacker News reader with optional Chinese AI summaries and an in-app reading view.

It is designed for people who want to scan Hacker News, understand the discussion around a story, and open the original article without switching between several browser tabs.

> HeyNews is currently a proprietary, source-available product. The repository is private. The terms in `LICENSE` and `EULA.md` apply to use and distribution.

## Current Version

V0 focuses on the reading loop:

- Hacker News Top, Best, New, Ask HN, and Show HN lists
- Local cache for fast startup and offline viewing of previously loaded stories
- Read-state persistence
- Optional AI summaries for the first 12 stories in a list
- Chinese title, summary, topic tags, and comment consensus
- OpenAI-compatible providers: DeepSeek, OpenAI, Ollama, and custom endpoints
- API keys stored in the macOS Keychain
- In-app article reading with Mozilla Readability.js
- Graceful fallback for paywalls, PDFs, JavaScript-heavy pages, and blocked sites

V0 does not include paid-feature gating, activation, account sync, or cloud storage.

## Requirements

- macOS 15.0 or later
- Xcode 26.3 or later for development
- Swift 6 language mode
- Apple Silicon or Intel Mac supported by the selected Xcode toolchain

## Build

The Xcode project is generated from `project.yml` with XcodeGen. XcodeGen is a build-time tool; the generated project is also checked in.

```bash
brew install xcodegen
cd HeyNews
xcodegen generate
xcodebuild -project HeyNews.xcodeproj \
  -scheme HeyNews \
  -configuration Debug \
  -destination 'platform=macOS' build
```

Open `HeyNews.xcodeproj` in Xcode and run the `HeyNews` scheme to use the app locally.

The pure logic layer has its own test target and can be tested without launching the app:

```bash
swift test --package-path Packages/HeyNewsKit
```

When adding or removing source files under `HeyNews/`, run `xcodegen generate` before building so the generated Xcode project stays in sync.

## AI Setup

AI is optional. Without a configured provider, HeyNews remains a usable Hacker News reader.

Open Settings from the toolbar or with `Command-,`:

1. Choose a provider preset.
2. Enter the provider's OpenAI-compatible endpoint and model name.
3. Enter an API key when the provider requires one.
4. Use **Test Connection** before saving.

The default preset is DeepSeek:

- Base URL: `https://api.deepseek.com/v1`
- Summary model: `deepseek-v4-flash`
- Analysis model reserved for a later version: `deepseek-v4-pro`

Ollama can be used with a local endpoint such as `http://localhost:11434/v1`. The model name must match a model installed on the local machine.

Keys are stored in the macOS Keychain. They are not written to UserDefaults, the repository, or application logs. When AI is disabled or not configured, HeyNews does not send article text or comments to an AI provider.

## Data And Privacy

Hacker News data is fetched from the public Firebase API and Algolia HN Search API. Previously loaded stories, read state, and summaries are stored in the app's local Application Support container.

When AI summaries are enabled, the story title, metadata, and a bounded selection of HN comments are sent to the provider configured by the user. Provider retention and data handling are governed by that provider's own terms and privacy policy.

Article pages are loaded directly in a local WKWebView for reading-mode extraction. HeyNews does not operate a server-side article proxy.

## Reader Limitations

Third-party sites can require a subscription, login, JavaScript challenge, or a browser-specific rendering path. In those cases the app may not be able to extract the article body. HeyNews falls back to the story title, HN discussion availability, and a button to open the original URL in the system browser.

A paywall means that the external publisher restricts the article behind a subscription or login. It is a limitation of the source website, not a HeyNews payment feature.

The app uses request throttling and bounded comment/article processing. It is intended for personal reading, not automated bulk crawling or redistribution of third-party content.

## License And Legal Documents

HeyNews is proprietary software. See [`LICENSE`](LICENSE) and [`EULA.md`](EULA.md) before using or distributing the application.

The app includes Mozilla Readability.js 0.6.0 under the Apache License 2.0. See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) and [`LICENSES/Apache-2.0.txt`](LICENSES/Apache-2.0.txt) for attribution and the complete third-party license text.

The EULA is a product draft and should be reviewed by counsel before any commercial release or paid feature launch.
