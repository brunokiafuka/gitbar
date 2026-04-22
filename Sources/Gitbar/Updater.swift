import Foundation

struct GHRelease: Decodable, Equatable, Sendable {
    let tagName: String
    let htmlUrl: String
    let name: String?
    let prerelease: Bool
    let draft: Bool

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case name, prerelease, draft
    }
}

@MainActor
final class Updater: ObservableObject {
    @Published private(set) var latestRelease: GHRelease?
    @Published private(set) var lastCheckedAt: Date?

    private let repo: String
    let currentVersion: String?
    private var timer: Timer?
    private let checkInterval: TimeInterval = 24 * 60 * 60
    private let lastCheckKey = "gitbar.updater.lastCheckedAt"

    init(repo: String = "brunokiafuka/gitbar") {
        self.repo = repo
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        self.currentVersion = raw?.isEmpty == false ? raw : nil
        if let ts = UserDefaults.standard.object(forKey: lastCheckKey) as? Date {
            self.lastCheckedAt = ts
        }
    }

    /// Runs a check now + every 24h. No-op when there's no bundled version
    /// (e.g. `swift run` dev mode — keeps the footer quiet locally).
    func start() {
        guard currentVersion != nil else { return }
        Task { await check() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
    }

    var hasUpdate: Bool {
        guard let current = currentVersion, let release = latestRelease else { return false }
        guard !release.prerelease, !release.draft else { return false }
        return Self.isNewer(release.tagName, than: current)
    }

    var releaseURL: URL? {
        guard hasUpdate, let s = latestRelease?.htmlUrl else { return nil }
        return URL(string: s)
    }

    var latestTag: String? { latestRelease?.tagName }

    func check() async {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token = Config.resolveToken(), !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
            let release = try JSONDecoder().decode(GHRelease.self, from: data)
            self.latestRelease = release
            let now = Date()
            self.lastCheckedAt = now
            UserDefaults.standard.set(now, forKey: lastCheckKey)
        } catch {
            // Silent: low-frequency background check; stale data is fine until next tick.
        }
    }

    private static func isNewer(_ tag: String, than current: String) -> Bool {
        let a = semverParts(tag)
        let b = semverParts(current)
        guard !a.isEmpty, !b.isEmpty else { return false }
        for (x, y) in zip(a, b) where x != y { return x > y }
        return a.count > b.count
    }

    private static func semverParts(_ s: String) -> [Int] {
        var t = s
        if t.hasPrefix("v") { t.removeFirst() }
        if let dash = t.firstIndex(of: "-") { t = String(t[..<dash]) }
        return t.split(separator: ".").compactMap { Int($0) }
    }
}
