import Foundation
import Testing
@testable import VoiceCore

@Suite struct BuiltInCatalogTests {
    private let gb: UInt64 = 1_073_741_824

    @Test func orderedSmallToLarge() {
        #expect(BuiltInCatalog.models.map(\.tier) == [.small, .medium, .large])
        let mem = BuiltInCatalog.models.map(\.memoryBytes)
        #expect(mem == mem.sorted())
    }

    @Test func idsAreUniqueAndContainQwen() {
        let ids = BuiltInCatalog.models.map(\.id)
        #expect(Set(ids).count == ids.count)
        for id in ids { #expect(id.lowercased().contains("qwen")) }
    }

    @Test func urlsArePinnedHuggingFace() throws {
        let pattern = try Regex("^https://huggingface\\.co/[^/]+/[^/]+/resolve/[0-9a-f]{40}/[^/]+$")
        for m in BuiltInCatalog.models {
            #expect(m.url.absoluteString.wholeMatch(of: pattern) != nil)
            #expect(m.url.lastPathComponent == m.fileName)
        }
    }

    @Test func hashesAreLowercaseHex64() throws {
        let pattern = try Regex("^[0-9a-f]{64}$")
        for m in BuiltInCatalog.models { #expect(m.sha256.wholeMatch(of: pattern) != nil) }
    }

    @Test func ratingsInRange() {
        for m in BuiltInCatalog.models {
            #expect((1...3).contains(m.speed))
            #expect((1...3).contains(m.quality))
        }
    }

    @Test func lookupById() {
        let m = BuiltInCatalog.models[1]
        #expect(BuiltInCatalog.model(id: m.id) == m)
        #expect(BuiltInCatalog.model(id: "nope") == nil)
    }

    @Test func recommendedNilWhenNothingFits() {
        #expect(BuiltInCatalog.recommended(physicalMemory: 1 * gb) == nil)
    }

    @Test func recommendedLargestOn96GB() {
        #expect(BuiltInCatalog.recommended(physicalMemory: 96 * gb) == BuiltInCatalog.models.last)
    }

    @Test func recommendedOn16GBFollowsRule() {
        let budget = BuiltInCatalog.memoryShare * Double(16 * gb)
        let expected = BuiltInCatalog.models.last { Double($0.memoryBytes) <= budget }
        #expect(expected != nil)
        #expect(BuiltInCatalog.recommended(physicalMemory: 16 * gb) == expected)
    }
}
