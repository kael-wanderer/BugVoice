import Foundation
import Testing

struct AppBundleUsageDescriptionTests {
    @Test func infoPlistHasSystemAudioCaptureDescription() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let plist = root.appendingPathComponent("App/Info.plist")
        let data = try Data(contentsOf: plist)
        let dictionary = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let description = try #require(dictionary["NSAudioCaptureUsageDescription"] as? String)
        #expect(!description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
