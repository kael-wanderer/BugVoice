import Testing
@testable import VoiceCore

struct ListPagingTests {
    @Test func splitsIntoPagesOfFive() {
        let paging = ListPaging(count: 12, pageSize: 5)
        #expect(paging.pageCount == 3)
        #expect(paging.range(page: 0) == 0..<5)
        #expect(paging.range(page: 2) == 10..<12)
    }

    @Test func emptyListHasOneEmptyPage() {
        let paging = ListPaging(count: 0, pageSize: 5)
        #expect(paging.pageCount == 1)
        #expect(paging.range(page: 0) == 0..<0)
    }

    @Test func outOfRangePageClampsToLastPage() {
        let paging = ListPaging(count: 6, pageSize: 5)
        #expect(paging.clamp(4) == 1)
        #expect(paging.clamp(-1) == 0)
        #expect(paging.range(page: 9) == 5..<6)
    }

    @Test func zeroPageSizeShowsEverythingOnOnePage() {
        let paging = ListPaging(count: 3, pageSize: 0)
        #expect(paging.pageCount == 1)
        #expect(paging.range(page: 0) == 0..<3)
    }
}
