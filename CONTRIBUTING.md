# Contributing

Thanks for considering a contribution.

## 1. Licensing of contributions

OhNews is released under the **MIT License** (see [`LICENSE`](LICENSE)).
Contributions are accepted under the same license, so there is nothing to sign:
by submitting a pull request you agree that your contribution is licensed to
everyone under the MIT terms.

Please just state in your pull request that you wrote the code (or otherwise
have the right to submit it) and that you agree to license it under MIT.

## 2. Practical notes

- The project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):
  after adding or removing files, run `xcodegen generate`.
- Pure logic lives in the `OhNewsKit` package and is covered by tests. Run them
  before submitting:

  ```bash
  swift test --package-path Packages/OhNewsKit
  ```

- The app target must build without warnings:

  ```bash
  xcodebuild -project OhNews.xcodeproj -scheme OhNews -configuration Debug \
    -destination 'platform=macOS' build
  ```

- UI conventions, design tokens and the two non-obvious SwiftUI constraints are
  documented in the maintainer's notes; keep changes consistent with the
  existing style rather than introducing new colours, fonts or motion curves.
