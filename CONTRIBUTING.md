# Contributing

Thanks for considering a contribution. Two things to know before you open a
pull request.

## 1. Licensing of contributions

OhNews is dual-licensed: the public project is AGPL-3.0, and the maintainer also
sells commercial licenses (see [`LICENSING.md`](LICENSING.md)).

That model only works if the maintainer holds enough rights over **all** of the
code to offer it under both licenses. If your contribution were merged under the
AGPL alone, the maintainer could no longer grant a commercial license for the
parts you wrote.

So by submitting a pull request you agree that:

1. you are the author of the contribution, or have the right to submit it;
2. you grant the maintainer a perpetual, worldwide, non-exclusive, royalty-free,
   irrevocable licence to use, reproduce, modify, distribute and **relicense**
   your contribution, including under the commercial license;
3. your contribution is provided without warranty of any kind.

Please state that you agree with the above in your pull request description. A
pull request without that statement cannot be merged.

If you would rather not grant relicensing rights — that is completely
reasonable — please open an issue describing the change instead of a pull
request, and it will be implemented independently.

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
