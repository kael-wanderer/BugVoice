import Foundation
import Testing
@testable import VoiceCore

struct AppFeedVersionTests {
    @Test func writesTheBuildAsANumericPrerelease() {
        #expect(AppFeedVersion.string(shortVersion: "0.1.0", build: "327") == "0.1.0-build.327")
        #expect(AppFeedVersion.string(shortVersion: " 0.1.0 ", build: "0042") == "0.1.0-build.42")
    }

    @Test func fallsBackToTheBareVersion() {
        #expect(AppFeedVersion.string(shortVersion: "0.1.0", build: nil) == "0.1.0")
        #expect(AppFeedVersion.string(shortVersion: "0.1.0", build: "abc") == "0.1.0")
        #expect(AppFeedVersion.string(shortVersion: nil, build: "7") == "0-build.7")
    }
}

struct SemVerTests {
    @Test func ordersBuildsNumerically() {
        #expect(SemVer.isNewer("0.1.0-build.10", than: "0.1.0-build.9"))
        #expect(!SemVer.isNewer("0.1.0-build.306", than: "0.1.0-build.327"))
        #expect(!SemVer.isNewer("0.1.0-build.327", than: "0.1.0-build.327"))
    }

    @Test func aVersionBumpBeatsAnyBuild() {
        #expect(SemVer.isNewer("0.2.0-build.1", than: "0.1.0-build.9999"))
        #expect(SemVer.isNewer("1.0", than: "0.9.9"))
        #expect(SemVer.isNewer("v1.0.0", than: "0.9.0"))
    }

    @Test func aReleaseOutranksItsPrereleases() {
        #expect(SemVer.isNewer("0.1.0", than: "0.1.0-build.327"))
        #expect(!SemVer.isNewer("0.1.0-build.1", than: "0.1.0"))
        #expect(SemVer.isNewer("1.0.0-beta", than: "1.0.0-1"))
        #expect(SemVer.isNewer("1.0.0-beta.2.1", than: "1.0.0-beta.2"))
    }

    @Test func garbageIsNeverNewer() {
        for bad in ["", "latest", "1.x", "1.2.3.4", "1.0.0-", "1.0.0-a..b", "-1.0"] {
            #expect(!SemVer.isNewer(bad, than: "0.0.1"), "\(bad)")
            #expect(!SemVer.isNewer("9.9.9", than: bad), "\(bad)")
        }
    }
}

struct UpdateFeedDecodeTests {
    let release = "https://kael.io.vn/api/download/releases/x"

    @Test func readsThePublishedFeed() {
        let body = Data(#"{"version":"0.1.0-build.306","release_url":"\#(release)"}"#.utf8)
        #expect(UpdateFeed.decode(status: 200, data: body)
            == .success(UpdateFeed(version: "0.1.0-build.306", releaseURL: URL(string: release))))
    }

    @Test func dropsAReleaseURLThatIsNotHTTPS() throws {
        for raw in ["file:///Applications/Calculator.app", "http://kael.io.vn/x", "bugvoice://open", "javascript:alert(1)", "not a url"] {
            let body = try JSONSerialization.data(withJSONObject: ["version": "1.0.0", "release_url": raw])
            #expect(UpdateFeed.decode(status: 200, data: body) == .success(UpdateFeed(version: "1.0.0", releaseURL: nil)), "\(raw)")
        }
    }

    @Test func refusesAFeedThatCannotBeTrusted() {
        let bodies = [
            Data(repeating: 0x20, count: UpdateFeed.maxBytes + 1),
            Data("not json".utf8),
            Data(#"{"message":"private"}"#.utf8),
            Data(#"{"version":""}"#.utf8),
            Data(#"{"version":42}"#.utf8),
            Data(#"{"version":"1.0.0 <script>"}"#.utf8),
            Data(#"{"version":"\#(String(repeating: "1", count: 65))"}"#.utf8),
        ]
        for body in bodies {
            #expect(UpdateFeed.decode(status: 200, data: body) == .unavailable(.malformed))
        }
    }

    @Test func classifiesStatusCodes() {
        let body = Data(#"{"version":"1.0.0"}"#.utf8)
        #expect(UpdateFeed.decode(status: 404, data: body) == .unavailable(.notFound))
        #expect(UpdateFeed.decode(status: 500, data: body) == .unavailable(.serverError))
        #expect(UpdateFeed.decode(status: 302, data: body) == .unavailable(.serverError))
        #expect(UpdateFeed.classify(URLError(.timedOut)) == .timeout)
        #expect(UpdateFeed.classify(URLError(.notConnectedToInternet)) == .transport)
    }

    @Test func offersOnlyANewerVersionWithAPage() {
        let url = URL(string: release)!
        #expect(UpdateSelection.pick(UpdateFeed(version: "0.1.0-build.330", releaseURL: url), currentVersion: "0.1.0-build.327")
            == UpdateAvailable(version: "0.1.0-build.330", releaseURL: url))
        #expect(UpdateSelection.pick(UpdateFeed(version: "0.1.0-build.306", releaseURL: url), currentVersion: "0.1.0-build.327") == nil)
        #expect(UpdateSelection.pick(UpdateFeed(version: "0.1.0-build.330", releaseURL: nil), currentVersion: "0.1.0-build.327") == nil)
    }
}

@MainActor
struct UpdateWatcherTests {
    final class Box: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_792_411_200)
        var result: UpdateFeedResult = .success(UpdateFeed(version: "0.1.0-build.330", releaseURL: URL(string: "https://kael.io.vn/r")))
        var fetches = 0
        var announced: [String] = []
        var enabled = true
    }

    func watcher(_ box: Box, defaults: UserDefaults) -> UpdateWatcher {
        UpdateWatcher(
            fetch: { box.fetches += 1; return box.result },
            currentVersion: { "0.1.0-build.327" },
            isEnabled: { box.enabled },
            announce: { box.announced.append($0.version) },
            now: { box.now },
            defaults: defaults
        )
    }

    func freshDefaults() -> UserDefaults {
        let name = "UpdateWatcherTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func announcesANewVersionOnce() async {
        let box = Box(), w = watcher(box, defaults: freshDefaults())
        #expect(await w.check(force: true) == .announced("0.1.0-build.330"))
        #expect(await w.check(force: true) == .alreadyAnnounced)
        #expect(box.announced == ["0.1.0-build.330"])
        box.result = .success(UpdateFeed(version: "0.1.0-build.331", releaseURL: URL(string: "https://kael.io.vn/r")))
        #expect(await w.check(force: true) == .announced("0.1.0-build.331"))
    }

    @Test func staysQuietWhenOffUpToDateOrFailing() async {
        let box = Box(), w = watcher(box, defaults: freshDefaults())
        box.enabled = false
        #expect(await w.check(force: true) == .disabled)
        #expect(box.fetches == 0)
        box.enabled = true
        box.result = .success(UpdateFeed(version: "0.1.0-build.306", releaseURL: URL(string: "https://kael.io.vn/r")))
        #expect(await w.check(force: true) == .upToDate)
        box.result = .unavailable(.timeout)
        #expect(await w.check(force: true) == .unavailable(.timeout))
        #expect(box.announced.isEmpty)
    }

    @Test func keepsUnforcedChecksADayApart() async {
        let box = Box(), w = watcher(box, defaults: freshDefaults())
        _ = await w.check(force: true)
        box.now += UpdateWatcher.interval - 1
        #expect(await w.check(force: false) == .cooldown)
        box.now += 1
        #expect(await w.check(force: false) == .alreadyAnnounced)
        #expect(box.fetches == 2)
    }

    @Test func treatsACheckStampedInTheFutureAsDue() async {
        let box = Box(), defaults = freshDefaults(), w = watcher(box, defaults: defaults)
        defaults.set(box.now.addingTimeInterval(3_600), forKey: UpdateWatcher.lastCheckAtKey)
        #expect(await w.check(force: false) == .announced("0.1.0-build.330"))
    }
}
