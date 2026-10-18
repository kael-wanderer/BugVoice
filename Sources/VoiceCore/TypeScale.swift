import Foundation

public enum TokenWeight: Sendable, Equatable {
    case regular, semibold, bold
}

public enum TextToken: String, CaseIterable, Sendable {
    case largeTitle, title1, title2, title3, reading, body, bodyStrong, footnote, caption, stat

    public var baseSize: Double {
        switch self {
        case .largeTitle: 28
        case .title1: 22
        case .title2: 18
        case .title3: 15
        case .reading: 15
        case .body: 13
        case .bodyStrong: 13
        case .footnote: 12
        case .caption: 11
        case .stat: 26
        }
    }

    public var weight: TokenWeight {
        switch self {
        case .largeTitle, .title1, .title2, .title3, .bodyStrong: .semibold
        case .stat: .bold
        default: .regular
        }
    }
}

public enum TypeScale {
    public static func size(_ token: TextToken, scale: Int) -> Double {
        scaled(token.baseSize, scale: scale)
    }

    public static func scaled(_ points: Double, scale: Int) -> Double {
        (points * Double(scale) / 100 * 2).rounded() / 2
    }
}

public enum LayoutTokens {
    public static let spacing: [Double] = [4, 8, 12, 16, 24, 32]
    public static let controlRadius = 6.0
    public static let cardRadius = 10.0
    public static let largeCardRadius = 14.0

    public static func usesLargeControls(scale: Int) -> Bool {
        scale >= 130
    }
}
