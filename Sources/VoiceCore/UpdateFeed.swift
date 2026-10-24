import Foundation

// Self-update check, after Bugler's `UpdateFeed.swift` and `UpdateWatcher`:
// read the published `latest.json`, compare it with the running build, and
// offer the release page. Nothing here downloads or installs anything — an
// app that replaces its own bundle needs signing, a channel and a rollback
// story this build does not have.

/// The running build in the feed's shape: `0.1.0-build.327`. The build is a
/// numeric prerelease identifier, so builds of one version order numerically,
/// and the feed must publish the same shape: a bare `0.1.0` would outrank
/// every build of itself.
public enum AppFeedVersion {
    public static func string(shortVersion: String?, build: String?) -> String {
        let trimmed = shortVersion?.trimmingCharacters(in: .whitespaces) ?? ""
        // "0" rather than "": a version nothing can parse is never older.
        let version = trimmed.isEmpty ? "0" : trimmed
        guard let build = build?.trimmingCharacters(in: .whitespaces),
              build.allSatisfy(\.isASCII), let number = Int(build), number >= 0
        else { return version }
        return "\(version)-build.\(number)"
    }

    public static func string(bundle: Bundle = .main) -> String {
        string(
            shortVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }
}

/// A SemVer 2.0 comparator: numeric prerelease identifiers order numerically
/// (`build.10 > build.2`) and a release outranks any prerelease of its core.
public enum SemVer {
    private enum Identifier: Equatable {
        case numeric(Int)
        case alphanumeric(String)
    }

    private struct Parsed {
        let core: [Int]
        let prerelease: [Identifier]
    }

    /// True only when `candidate` is strictly newer. Anything that does not
    /// parse is never newer, so a garbled feed cannot raise a spurious offer.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = parse(candidate), let b = parse(current) else { return false }
        return compare(a, b) == .orderedDescending
    }

    private static func isDigits(_ part: Substring) -> Bool {
        !part.isEmpty && part.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func parse(_ raw: String) -> Parsed? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v"), value.dropFirst().first?.isNumber == true { value.removeFirst() }
        if let plus = value.firstIndex(of: "+") { value = String(value[..<plus]) }
        guard !value.isEmpty else { return nil }
        let hyphen = value.firstIndex(of: "-")
        let coreString = hyphen.map { value[..<$0] } ?? Substring(value)
        let coreParts = coreString.split(separator: ".", omittingEmptySubsequences: false)
        guard coreParts.count <= 3, coreParts.allSatisfy(isDigits) else { return nil }
        var core = coreParts.compactMap { Int($0) }
        guard core.count == coreParts.count else { return nil }
        while core.count < 3 { core.append(0) }

        var prerelease: [Identifier] = []
        if let hyphen {
            for part in value[value.index(after: hyphen)...].split(separator: ".", omittingEmptySubsequences: false) {
                guard !part.isEmpty else { return nil }
                if isDigits(part), let number = Int(part) {
                    prerelease.append(.numeric(number))
                } else {
                    prerelease.append(.alphanumeric(String(part)))
                }
            }
        }
        return Parsed(core: core, prerelease: prerelease)
    }

    private static func compare(_ a: Parsed, _ b: Parsed) -> ComparisonResult {
        for index in 0..<3 where a.core[index] != b.core[index] {
            return a.core[index] < b.core[index] ? .orderedAscending : .orderedDescending
        }
        switch (a.prerelease.isEmpty, b.prerelease.isEmpty) {
        case (true, true): return .orderedSame
        case (true, false): return .orderedDescending
        case (false, true): return .orderedAscending
        case (false, false): break
        }
        for (lhs, rhs) in zip(a.prerelease, b.prerelease) {
            switch (lhs, rhs) {
            case let (.numeric(x), .numeric(y)) where x != y:
                return x < y ? .orderedAscending : .orderedDescending
            case (.numeric, .alphanumeric):
                return .orderedAscending  // numeric identifiers rank lower
            case (.alphanumeric, .numeric):
                return .orderedDescending
            case let (.alphanumeric(x), .alphanumeric(y)) where x != y:
                return x < y ? .orderedAscending : .orderedDescending
            default:
                continue
            }
        }
        if a.prerelease.count == b.prerelease.count { return .orderedSame }
        return a.prerelease.count < b.prerelease.count ? .orderedAscending : .orderedDescending
    }
}

/// The decoded `latest.json`.
public struct UpdateFeed: Equatable, Sendable {
    public let version: String
    public let releaseURL: URL?

    public init(version: String, releaseURL: URL?) {
        self.version = version
        self.releaseURL = releaseURL
    }
}

/// Failure classes only: no message, path or body, because this is what the
/// log and the screen may quote.
public enum UpdateFeedFailure: String, Equatable, Sendable {
    case notFound = "not_found"
    case serverError = "server_error"
    case timeout
    case malformed
    case transport
}

public enum UpdateFeedResult: Equatable, Sendable {
    case success(UpdateFeed)
    case unavailable(UpdateFeedFailure)
}

extension UpdateFeed {
    public static let url = URL(string: "https://kael.io.vn/projects/bugvoice/latest.json")!
    static let maxBytes = 16 * 1024
    static let maxVersionLength = 64

    private struct Wire: Decodable {
        let version: String
        let releaseURL: String?
        enum CodingKeys: String, CodingKey {
            case version
            case releaseURL = "release_url"
        }
    }

    /// Status and body classification, so every branch is testable without a
    /// network.
    public static func decode(status: Int, data: Data) -> UpdateFeedResult {
        switch status {
        case 200:
            guard data.count <= maxBytes,
                  let wire = try? JSONDecoder().decode(Wire.self, from: data),
                  isPlainVersion(wire.version)
            else { return .unavailable(.malformed) }
            return .success(UpdateFeed(version: wire.version, releaseURL: webURL(wire.releaseURL)))
        case 404:
            return .unavailable(.notFound)
        default:
            return .unavailable(.serverError)
        }
    }

    public static func classify(_ error: URLError) -> UpdateFeedFailure {
        error.code == .timedOut ? .timeout : .transport
    }

    private static func isPlainVersion(_ raw: String) -> Bool {
        !raw.isEmpty && raw.count <= maxVersionLength
            && raw.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "+") }
    }

    /// Only `https`. The release URL ends up at `NSWorkspace.open`, which
    /// launches a `file:` URL or hands a custom scheme to another app — a
    /// button that promises the release page must not do either. A refused
    /// URL leaves the version reported with no link.
    private static func webURL(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw), url.scheme == "https", url.host() != nil else { return nil }
        return url
    }

    /// One GET with a short bound. The body is read in full by URLSession,
    /// but the size check above refuses anything past the cap before parsing.
    public static func fetch(url: URL = UpdateFeed.url, session: URLSession = HTTP.noRedirectSession) async -> UpdateFeedResult {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            return decode(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        } catch let error as URLError {
            return .unavailable(classify(error))
        } catch {
            return .unavailable(.transport)
        }
    }
}

/// One offered update: a newer version and the page to open for it.
public struct UpdateAvailable: Equatable, Sendable {
    public let version: String
    public let releaseURL: URL

    public init(version: String, releaseURL: URL) {
        self.version = version
        self.releaseURL = releaseURL
    }
}

public enum UpdateSelection {
    /// An offer needs both a newer version and a page to open.
    public static func pick(_ feed: UpdateFeed, currentVersion: String) -> UpdateAvailable? {
        guard SemVer.isNewer(feed.version, than: currentVersion), let url = feed.releaseURL else { return nil }
        return UpdateAvailable(version: feed.version, releaseURL: url)
    }
}

/// "Check on launch, and once a day while BugVoice is running." Every side
/// effect is injected so a test can step it without a timer or a network.
/// Announcing never installs anything: it says a version exists.
@MainActor
public final class UpdateWatcher {
    public static let lastCheckAtKey = "updateLastCheckAt"
    public static let lastAnnouncedKey = "updateLastAnnounced"
    public static let interval: TimeInterval = 24 * 60 * 60
    /// The loop wakes hourly and checks once the day is up: a sleeping Mac
    /// stops the clock, so one 24-hour sleep can stretch over several days.
    public static let tick: TimeInterval = 60 * 60

    public enum Outcome: Equatable, Sendable {
        case disabled
        case cooldown
        case unavailable(UpdateFeedFailure)
        case upToDate
        case alreadyAnnounced
        case announced(String)
    }

    private let fetch: @MainActor () async -> UpdateFeedResult
    private let currentVersion: @MainActor () -> String
    private let isEnabled: @MainActor () -> Bool
    private let announce: @MainActor (UpdateAvailable) -> Void
    private let found: @MainActor (UpdateAvailable?) -> Void
    private let now: @MainActor () -> Date
    private let defaults: UserDefaults
    private var task: Task<Void, Never>?

    public init(
        fetch: @escaping @MainActor () async -> UpdateFeedResult = { await UpdateFeed.fetch() },
        currentVersion: @escaping @MainActor () -> String = { AppFeedVersion.string() },
        isEnabled: @escaping @MainActor () -> Bool,
        announce: @escaping @MainActor (UpdateAvailable) -> Void,
        found: @escaping @MainActor (UpdateAvailable?) -> Void = { _ in },
        now: @escaping @MainActor () -> Date = Date.init,
        defaults: UserDefaults = .standard
    ) {
        self.fetch = fetch
        self.currentVersion = currentVersion
        self.isEnabled = isEnabled
        self.announce = announce
        self.found = found
        self.now = now
        self.defaults = defaults
    }

    /// Idempotent. The launch check is forced; the loop's keep a day apart.
    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            _ = await self?.check(force: true)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(Self.tick)) } catch { return }
                _ = await self?.check(force: false)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    @discardableResult
    public func check(force: Bool) async -> Outcome {
        guard isEnabled() else { return .disabled }
        // A clock set backwards leaves the stamp in the future; that counts as due.
        if !force, let last = defaults.object(forKey: Self.lastCheckAtKey) as? Date,
           now() >= last, now().timeIntervalSince(last) < Self.interval {
            return .cooldown
        }
        defaults.set(now(), forKey: Self.lastCheckAtKey)
        switch await fetch() {
        case .unavailable(let failure):
            return .unavailable(failure)
        case .success(let feed):
            // Every answer the feed gives reaches `found`, so a standing offer
            // (the menu row) survives a relaunch; `announce` runs once a version.
            let update = UpdateSelection.pick(feed, currentVersion: currentVersion())
            found(update)
            guard let update else { return .upToDate }
            guard defaults.string(forKey: Self.lastAnnouncedKey) != update.version else { return .alreadyAnnounced }
            announce(update)
            defaults.set(update.version, forKey: Self.lastAnnouncedKey)
            return .announced(update.version)
        }
    }
}
