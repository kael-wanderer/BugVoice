import Foundation
import Testing
@testable import VoiceCore

@Suite struct BuiltInDownloadPlanTests {
    @Test func nextStep() {
        #expect(BuiltInDownloadPlan.next(partialBytes: nil, expected: 100) == .start)
        #expect(BuiltInDownloadPlan.next(partialBytes: 0, expected: 100) == .start)
        #expect(BuiltInDownloadPlan.next(partialBytes: 40, expected: 100) == .resume(rangeHeader: "bytes=40-"))
        #expect(BuiltInDownloadPlan.next(partialBytes: 100, expected: 100) == .verify)
        #expect(BuiltInDownloadPlan.next(partialBytes: 150, expected: 100) == .restart)
    }

    @Test func urls() {
        let model = BuiltInCatalog.models[0]
        let dir = URL(fileURLWithPath: "/tmp/x", isDirectory: true)
        #expect(BuiltInDownloadPlan.finalURL(for: model, in: dir).lastPathComponent == model.fileName)
        #expect(BuiltInDownloadPlan.partialURL(for: model, in: dir).lastPathComponent == model.fileName + ".part")
    }

    @Test func cleanupModelsPath() {
        let paths = AppPaths(root: URL(fileURLWithPath: "/tmp/root", isDirectory: true))
        #expect(paths.cleanupModels.path == "/tmp/root/Models/Cleanup")
    }
}
