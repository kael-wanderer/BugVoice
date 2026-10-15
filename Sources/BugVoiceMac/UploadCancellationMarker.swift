import Foundation

public enum UploadCancellationMarker {
    public static func sync(_ directory: URL) throws {
        try MeetingAACWriter.syncDirectory(directory)
    }
}
