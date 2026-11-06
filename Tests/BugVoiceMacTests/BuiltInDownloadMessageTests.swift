import Foundation
import Testing
@testable import BugVoiceMac

@Suite struct BuiltInDownloadMessageTests {
    @Test func notEnoughSpaceSaysHowMuch() {
        let text = BuiltInDownloadError.message(for: BuiltInDownloadError.notEnoughSpace(neededBytes: 2_760_000_000))
        #expect(text == "Not enough disk space. The download needs 2.8 GB free.")
    }

    @Test func hashMismatch() {
        #expect(BuiltInDownloadError.message(for: BuiltInDownloadError.hashMismatch) == "The download was damaged. Try again.")
    }

    @Test func offline() {
        #expect(BuiltInDownloadError.message(for: URLError(.notConnectedToInternet))
            == "This Mac is not connected to the internet. Try again when it is.")
    }

    @Test func droppedConnection() {
        let expected = "The connection dropped. Try again to continue from where it stopped."
        #expect(BuiltInDownloadError.message(for: URLError(.networkConnectionLost)) == expected)
        #expect(BuiltInDownloadError.message(for: URLError(.timedOut)) == expected)
    }

    @Test func serverError() {
        #expect(BuiltInDownloadError.message(for: BuiltInDownloadError.badStatus(503))
            == "The download server answered with error 503. Try again later.")
    }

    @Test func damagedCases() {
        for error in [BuiltInDownloadError.tooLarge, .sizeMismatch, .incomplete] {
            #expect(BuiltInDownloadError.message(for: error) == "The download was damaged. Try again.")
        }
    }

    @Test func unknownErrorsGetAPlainMessage() {
        struct Odd: Error {}
        #expect(BuiltInDownloadError.message(for: Odd()) == "The download failed. Try again.")
    }

    @Test func cancellationIsNotAFailure() {
        #expect(BuiltInDownloadError.isCancellation(CancellationError()))
        #expect(BuiltInDownloadError.isCancellation(URLError(.cancelled)))
        #expect(!BuiltInDownloadError.isCancellation(URLError(.timedOut)))
    }
}
