// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import OhNewsKit

/// 版本检查。
///
/// 只回答「有没有更新」，不做下载与安装。安装包是 ad-hoc 签名、未经公证的，
/// 自动替换后容易被 Gatekeeper 拦下，用户看到的是「更新完打不开」，比不更新更糟。
/// 等配上 Developer ID 与公证之后再考虑接 Sparkle。
///
/// 接口用的是公开仓库的发布页，不需要任何凭据，也不涉及用户数据。
actor UpdateService {
    /// 更新检查的地址。
    ///
    /// 用发布页而不是 API：API 有「每 IP 每小时 60 次」的限额，未认证请求共享
    /// 同一个额度，公司或学校网络下的用户会互相影响。这个地址只回一个 302，
    /// 跳到最新 tag 的页面，同样会跳过草稿与预览版。
    private static let latestReleasePage =
        URL(string: "https://github.com/nipheryang/OhNews/releases/latest")

    private let session: URLSession
    private let currentVersion: AppVersion?

    init(
        session: URLSession = .shared,
        currentVersion: AppVersion? = UpdateService.bundledVersion()
    ) {
        self.session = session
        self.currentVersion = currentVersion
    }

    /// 应用包里的版本号。读不到就没法比较，此时安静地放弃这次检查。
    static func bundledVersion() -> AppVersion? {
        guard let text = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        else { return nil }
        return AppVersion(text)
    }

    /// 查询是否有更新。
    ///
    /// 任何失败都归入 `.failed`，由调用方决定是否让用户看见——自动检查不说，
    /// 用户手动点时才说。
    func check() async -> UpdateCheckResult {
        guard let currentVersion else {
            return .failed("读不到当前版本号")
        }
        guard let url = Self.latestReleasePage else {
            return .failed("接口地址无效")
        }

        var request = URLRequest(url: url)
        request.setValue("OhNews/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            // 不取内容，只看最终落在哪个地址：重定向由 URLSession 自动跟随。
            let (_, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                return .failed("应答格式异常")
            }
            guard http.statusCode == 200, let finalURL = http.url else {
                return .failed("接口返回 \(http.statusCode)")
            }

            let info = try GitHubReleasePageParser.parse(finalURL)
            return info.version > currentVersion ? .newer(info) : .upToDate
        } catch let error as UpdateParseError {
            switch error {
            case .notARelease: return .failed("还没有发布版本")
            case .malformed: return .failed("应答结构与预期不符")
            }
        } catch {
            return .failed("网络请求失败")
        }
    }
}
