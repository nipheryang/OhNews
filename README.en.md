# OhNews

[简体中文](README.md) | [English](README.en.md)

OhNews is a native macOS news reader. It ships with Hacker News and accepts any RSS or Atom feed, so you can read everything in one three-column window. Optional Chinese AI summaries help you decide whether a story is worth opening.

It is built for the everyday loop: scan what is new, understand what a story is about, and read the article when it matters — without juggling browser tabs.

**Open source under the MIT License.** Use it, modify it, redistribute it, including commercially.

---

## Install

Requires **macOS 15.0 or later**. Builds are published per architecture; pick the one that matches your Mac:

| File | For |
| --- | --- |
| `OhNews-<version>-arm64.dmg` | Apple Silicon (M-series) |
| `OhNews-<version>-x86_64.dmg` | Intel |

To install:

1. Open the downloaded `.dmg`.
2. Drag `OhNews.app` onto `Applications`.
3. Launch it from Launchpad or Applications.

**The first launch will be blocked.** Current builds are not signed with an Apple Developer certificate and are not notarized, so macOS reports an unidentified developer. To open it: **Control-click the app in Finder**, choose **Open**, and confirm once in the dialog. Afterwards it launches normally by double-click. If Control-click does not work, allow it under System Settings → Privacy & Security → "Open Anyway".

The app is usable out of the box. AI summaries are optional and require your own provider credentials.

---

## Features

### Sources

- **Hacker News**: Top, Best, New, Ask HN, and Show HN.
- **RSS / Atom**: add any feed, grouped by source in the sidebar, with rename and delete.
- Each source owns its channels. Item IDs carry a source prefix, so entries from different sources never collide.

### Lists and refresh

- Switching channels reads the local cache and does not hit the network every time.
- One refresh on cold start, an automatic refresh every four hours, and manual refresh on demand.
- Refreshes **merge in place**: new items are inserted at the top, existing items update their score and comment count, and the list does not flash.
- Choose a list size of **30 / 50 / 100** items.
- Read state, feed subscriptions, and the selected channel persist across launches.
- Settings shows how much the cache occupies and can clear it; subscriptions and preferences are kept.

### AI summaries (optional)

- Choose a scope: **leading items only** (12 by default, to bound cost), **everything**, or **manual only**.
- **Right-click any row** to generate or regenerate a single summary, regardless of the automatic limit.
- Summaries carry a Chinese title, a Chinese summary, topic tags, and a comment consensus.
- Summaries are cached per item, model, and prompt version; switching models regenerates them.
- The app distinguishes "no key", "key unreadable", "incomplete configuration", and "request failed", and a one-off failure can be dismissed.

### Reader

- Read the article in-app; extraction uses Mozilla Readability.js.
- When extraction fails, the app degrades gracefully: it keeps the title, tells you whether a discussion exists, and offers to open the original in your browser.
- Typography is tuned for long reads: roughly 720px measure and 1.9 line height.

### Interface

- Minimal editorial style: paper-white background, ink-black text, serif headlines, monospaced uppercase metadata, and hairline rules between entries.
- **One-click light/dark toggle** in the toolbar, plus System / Light / Dark in Settings.
- Arrow-key navigation through the list.
- Every animation respects the system Reduce Motion setting.

---

## AI Setup

AI is optional. Without a configured provider, OhNews remains a complete reader.

Open Settings from the toolbar or with `Command-,`:

1. Pick a provider preset.
2. Enter the OpenAI-compatible endpoint and model name.
3. Enter an API key if the provider needs one.
4. Use **Test Connection** before saving; it makes one real call with a very short input.

The default preset is DeepSeek:

- Base URL: `https://api.deepseek.com/v1`
- Summary model: `deepseek-v4-flash`

Local models work too, for example Ollama at `http://localhost:11434/v1`; the model name must match one installed locally.

Keys are stored in the macOS Keychain, never in config files, the repository, or logs.

> **Note**: rebuilding the app changes its signature, which can invalidate the Keychain authorisation, surfacing as "cannot read API Key" in the UI. Re-saving the key in Settings restores it — the key itself is not lost. Published builds are unaffected.

---

## Data And Privacy

- Hacker News data comes from the public Firebase API and the Algolia HN Search API; feed content is fetched directly from the URLs you add.
- Loaded items, read state, and summaries are cached in the app's own container.
- With AI summaries enabled, the story title, metadata, and a **bounded** selection of comments are sent to the provider you configured. Retention and handling are governed by that provider's own terms.
- Articles load in a local WKWebView for reading-mode extraction. OhNews operates no server-side proxy.
- Requests are throttled and comment/article processing is bounded. The app is a personal reading tool, not a bulk crawler or a way to redistribute third-party content.

---

## Known Limitations

- **Paywalls and logins**: third-party sites may require a subscription, login, a JavaScript challenge, or a browser-specific rendering path. In those cases the body may be unavailable. "Paywall" here means the external site's restriction, not an OhNews feature — OhNews has no paid tier.
- **Comment threads**: summaries can reference a comment consensus, but the full comment tree is not browsable yet. It is planned.
- **Code signing**: current builds are ad-hoc signed and not notarized, hence the manual first-launch step above.

---

## Build From Source

The Xcode project is generated from `project.yml` with XcodeGen, and the generated project is checked in.

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project OhNews.xcodeproj \
  -scheme OhNews \
  -configuration Debug \
  -destination 'platform=macOS' build
```

You can also open `OhNews.xcodeproj` in Xcode and run the `OhNews` scheme. Development requires Xcode 26.3 or later and the Swift 6 language mode.

The pure logic layer lives in its own Swift package and can be tested without launching the app:

```bash
swift test --package-path Packages/OhNewsKit
```

After adding or removing files under `OhNews/`, run `xcodegen generate` before building, otherwise the generated project will not include them.

To build both disk images:

```bash
scripts/build-dmg.sh              # both architectures
scripts/build-dmg.sh arm64        # Apple Silicon only
scripts/build-dmg.sh x86_64       # Intel only
```

Artifacts land in `dist/OhNews-<version>/`. For an official distribution, set the `SIGN_IDENTITY` and `NOTARY_PROFILE` environment variables to enable signing and notarization; credentials pass only through environment variables and the Keychain and are never written to the repository.

---

## Project Layout

```text
OhNews/                 the app (SwiftUI)
  App/                  app state and config persistence
  Models/               display-oriented model extensions
  Services/             networking, article extraction, AI calls, Keychain
  Support/              design tokens, theme, small helpers
  Views/                interface
  Resources/            reader stylesheet, Readability.js, third-party notices
Packages/OhNewsKit/     pure logic (parsing, caching, prompt building)
  Sources/OhNewsKit/
  Tests/OhNewsKitTests/
scripts/build-dmg.sh    dual-architecture packaging script
project.yml             XcodeGen definition (single source for the version)
```

---

## Roadmap

Possible directions, not committed delivery dates:

- Comment thread reading
- Detail-level AI analysis and a daily digest
- OPML import and export, to migrate subscriptions from other readers
- Search, favorites, and read-later
- More sources
- A Windows client

---

## License

OhNews is released under the **MIT License**; the full text is in [`LICENSE`](LICENSE). You may use, modify, and redistribute it, including in commercial and closed-source products. The only requirement is that the copyright notice and license text stay with the software.

Contributions are welcome; please read [`CONTRIBUTING.md`](CONTRIBUTING.md) first.

The app bundles Mozilla Readability.js 0.6.0 (Apache License 2.0). See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) and [`LICENSES/Apache-2.0.txt`](LICENSES/Apache-2.0.txt) for attribution and the full third-party license text.
