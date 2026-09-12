# OhNews

English | [简体中文](README.zh-CN.md)

OhNews is a native macOS app for reading Hacker News, with optional Chinese AI summaries and an in-app reading view. Hacker News is the first source it supports.

It is designed for people who want to scan Hacker News, understand the discussion around a story, and open the original article without switching between several browser tabs.

OhNews is free and open source software, released under the MIT License. You can use, modify and redistribute it, including commercially. See [`LICENSE`](LICENSE).

## Install

OhNews is distributed as a macOS disk image (DMG). macOS 15.0 or later is required.

1. Open the downloaded `.dmg` file.
2. Drag `OhNews.app` onto the `Applications` folder.
3. Launch OhNews from `Applications` or Spotlight.

Release builds are signed with a Developer ID certificate and notarized by Apple. Until a notarized build is available, macOS Gatekeeper may warn about an unidentified developer; in that case, Control-click the app in Finder and choose **Open** once.

The app works as a complete Hacker News reader without any configuration. AI summaries require your own provider credentials and are optional.

## Current Version

Version 0.1.0 focuses on the reading loop:

- Hacker News Top, Best, New, Ask HN, and Show HN lists
- Local cache for fast startup and offline viewing of previously loaded stories
- Read-state persistence
- Optional AI summaries for the first 12 stories in a list
- Chinese title, summary, topic tags, and comment consensus
- OpenAI-compatible providers: DeepSeek, OpenAI, Ollama, and custom endpoints
- API keys stored in the macOS Keychain
- In-app article reading with Mozilla Readability.js
- Graceful fallback for paywalls, PDFs, JavaScript-heavy pages, and blocked sites

Version 0.1.0 does not include paid-feature gating, activation, account sync, or cloud storage.

## Roadmap

- Additional news sources beyond Hacker News
- Detail-level deep analysis and a daily digest
- A Windows client
- Search, favorites, and read-later

Plans may change as development progresses and do not represent committed delivery dates.

## AI Setup

AI is optional. Without a configured provider, OhNews remains a usable Hacker News reader.

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

Keys are stored in the macOS Keychain. They are not written to UserDefaults, the repository, or application logs. When AI is disabled or not configured, OhNews does not send article text or comments to an AI provider.

## Data And Privacy

Hacker News data is fetched from the public Firebase API and Algolia HN Search API. Previously loaded stories, read state, and summaries are stored in the app's local Application Support container.

When AI summaries are enabled, the story title, metadata, and a bounded selection of HN comments are sent to the provider configured by the user. Provider retention and data handling are governed by that provider's own terms and privacy policy.

Article pages are loaded directly in a local WKWebView for reading-mode extraction. OhNews does not operate a server-side article proxy.

## Reader Limitations

Third-party sites can require a subscription, login, JavaScript challenge, or a browser-specific rendering path. In those cases the app may not be able to extract the article body. OhNews falls back to the story title, the availability of the HN discussion, and a button that opens the original URL in the system browser.

A paywall means that the external publisher restricts the article behind a subscription or login. It is a limitation of the source website, not a OhNews payment feature.

The app uses request throttling and bounded comment and article processing. It is intended for personal reading, not automated bulk crawling or redistribution of third-party content.

## Build From Source

The Xcode project is generated from `project.yml` with XcodeGen. XcodeGen is a build-time tool; the generated project is also checked in.

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project OhNews.xcodeproj \
  -scheme OhNews \
  -configuration Debug \
  -destination 'platform=macOS' build
```

Open `OhNews.xcodeproj` in Xcode and run the `OhNews` scheme.

Development requires Xcode 26.3 or later and the Swift 6 language mode.

The pure logic layer has its own test target and can be tested without launching the app:

```bash
swift test --package-path Packages/OhNewsKit
```

When adding or removing source files under `OhNews/`, run `xcodegen generate` before building so the generated Xcode project stays in sync.

## License And Legal Documents

OhNews is open source under the **MIT License** ([`LICENSE`](LICENSE)): use it, modify it, redistribute it, including in commercial and closed-source products. The only requirement is that the copyright notice and the license text stay with the software.

Contributions are welcome and are accepted under the same license; see [`CONTRIBUTING.md`](CONTRIBUTING.md).

The app includes Mozilla Readability.js 0.6.0 under the Apache License 2.0. See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) and [`LICENSES/Apache-2.0.txt`](LICENSES/Apache-2.0.txt) for attribution and the complete third-party license text.
