import Foundation

public struct UploadRecoveryPlan: Sendable {
  public let discard: [MeetingID]
  public let resume: [MeetingManifest]
  public let ready: [MeetingManifest]

  public init(_ manifests: [MeetingManifest]) {
    let uploads = manifests.filter { $0.source == .upload }.sorted {
      $0.id.rawValue < $1.id.rawValue
    }
    discard = uploads.filter { $0.state == .interrupted }.map(\.id)
    resume = uploads.filter { $0.state == .transcribing }
    ready = uploads.filter { $0.state == .ready }
  }
}
