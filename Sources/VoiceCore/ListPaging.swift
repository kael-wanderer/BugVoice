import Foundation

/// Splits a list into fixed-size pages. A list always has at least one page,
/// and page numbers outside the list clamp to the nearest page.
public struct ListPaging: Equatable, Sendable {
    public let count: Int
    public let pageSize: Int

    public init(count: Int, pageSize: Int) {
        self.count = max(0, count)
        self.pageSize = pageSize
    }

    public var pageCount: Int {
        guard pageSize > 0, count > 0 else { return 1 }
        return (count + pageSize - 1) / pageSize
    }

    public func clamp(_ page: Int) -> Int {
        min(max(0, page), pageCount - 1)
    }

    public func range(page: Int) -> Range<Int> {
        guard pageSize > 0 else { return 0..<count }
        let start = clamp(page) * pageSize
        return start..<min(start + pageSize, count)
    }
}
