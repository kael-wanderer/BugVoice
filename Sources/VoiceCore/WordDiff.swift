import Foundation

public enum WordDiffPiece: Equatable, Sendable {
    case same(String)
    case removed(String)
    case added(String)
}

/// Word-level diff for the Transform preview. Each piece keeps the
/// whitespace that followed its words, so line breaks survive.
public enum WordDiff {
    public static let maxWords = 1_500

    struct Token: Equatable {
        let word: String
        let text: String
    }

    static func tokens(_ text: String) -> [Token] {
        let ns = text as NSString
        let regex = try! NSRegularExpression(pattern: #"\S+\s*"#)
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            let piece = ns.substring(with: match.range)
            return Token(word: piece.trimmingCharacters(in: .whitespacesAndNewlines), text: piece)
        }
    }

    public static func diff(_ old: String, _ new: String) -> [WordDiffPiece] {
        let a = tokens(old), b = tokens(new)
        if a.count > maxWords || b.count > maxWords {
            return (old.isEmpty ? [] : [.removed(old)]) + (new.isEmpty ? [] : [.added(new)])
        }
        // lengths[i][j] = LCS of a[i...] and b[j...]
        var lengths = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lengths[i][j] = a[i].word == b[j].word
                    ? lengths[i + 1][j + 1] + 1
                    : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }
        var pieces: [WordDiffPiece] = []
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if a[i].word == b[j].word {
                pieces.append(.same(b[j].text))
                i += 1
                j += 1
            } else if lengths[i + 1][j] >= lengths[i][j + 1] {
                pieces.append(.removed(a[i].text))
                i += 1
            } else {
                pieces.append(.added(b[j].text))
                j += 1
            }
        }
        pieces += a[i...].map { .removed($0.text) }
        pieces += b[j...].map { .added($0.text) }
        return merge(pieces)
    }

    static func merge(_ pieces: [WordDiffPiece]) -> [WordDiffPiece] {
        var result: [WordDiffPiece] = []
        for piece in pieces {
            switch (result.last, piece) {
            case (.same(let x)?, .same(let y)): result[result.count - 1] = .same(x + y)
            case (.removed(let x)?, .removed(let y)): result[result.count - 1] = .removed(x + y)
            case (.added(let x)?, .added(let y)): result[result.count - 1] = .added(x + y)
            default: result.append(piece)
            }
        }
        return result
    }
}
