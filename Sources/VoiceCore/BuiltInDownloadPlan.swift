import Foundation

public enum DownloadStep: Equatable, Sendable {
    case start
    case resume(rangeHeader: String)
    case verify
    case restart
}

/// Pure decisions for downloading a built-in model: where files live and
/// what to do with a `.part` file left by an earlier attempt.
public enum BuiltInDownloadPlan {
    public static func partialURL(for model: BuiltInModel, in dir: URL) -> URL {
        dir.appendingPathComponent(model.fileName + ".part")
    }

    public static func finalURL(for model: BuiltInModel, in dir: URL) -> URL {
        dir.appendingPathComponent(model.fileName)
    }

    public static func next(partialBytes: Int64?, expected: Int64) -> DownloadStep {
        guard let have = partialBytes, have > 0 else { return .start }
        if have == expected { return .verify }
        if have > expected { return .restart }
        return .resume(rangeHeader: "bytes=\(have)-")
    }
}
