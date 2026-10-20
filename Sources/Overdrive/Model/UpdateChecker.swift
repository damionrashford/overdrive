import Foundation
import Observation

/// Looks up the latest GitHub release of the direct edition. Off by default, never automatic in the
/// App Store edition (the store delivers updates), and it sends nothing but a plain GET.
@MainActor @Observable
final class UpdateChecker {
    enum State: Equatable {
        case idle, checking, upToDate, available(version: String, url: URL), failed(String)
    }

    static let latestRelease = URL(string: "https://api.github.com/repos/damionrashford/overdrive/releases/latest")!
    static let interval: TimeInterval = 7 * 24 * 3600

    private(set) var state: State = .idle
    private(set) var lastChecked: Date?

    var available: (version: String, url: URL)? {
        if case .available(let version, let url) = state { return (version, url) }
        return nil
    }

    /// Runs the weekly check when the person turned it on.
    func checkIfDue(settings: AppSettings) async {
        guard settings.checkForUpdates else { return }
        if let last = settings.lastUpdateCheck, Date().timeIntervalSince(last) < Self.interval { return }
        await check(settings: settings)
    }

    func check(settings: AppSettings) async {
        state = .checking
        var request = URLRequest(url: Self.latestRelease)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let page = (json["html_url"] as? String).flatMap(URL.init) else {
                state = .failed("GitHub did not return a release.")
                return
            }
            let latest = Self.normalize(tag)
            let current = Self.normalize(Bundle.main.shortVersion)
            state = Self.isNewer(latest, than: current) ? .available(version: latest, url: page) : .upToDate
        } catch {
            state = .failed(error.localizedDescription)
        }
        lastChecked = Date()
        settings.lastUpdateCheck = lastChecked
    }

    static func normalize(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Numeric comparison of dotted versions, so 1.10.0 is newer than 1.9.0.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
