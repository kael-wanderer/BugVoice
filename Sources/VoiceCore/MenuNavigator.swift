import Foundation

/// Keyboard highlight for the menu popover. `ids` is the enabled controls in reading order.
public struct MenuNavigator<ID: Hashable & Sendable>: Equatable, Sendable {
    public private(set) var highlighted: ID?

    public init(highlighted: ID? = nil) { self.highlighted = highlighted }

    /// Down or Tab: next control, wrapping; starts at the first.
    public mutating func next(in ids: [ID]) {
        guard !ids.isEmpty else { highlighted = nil; return }
        if let current = highlighted, let i = ids.firstIndex(of: current) {
            highlighted = ids[(i + 1) % ids.count]
        } else {
            highlighted = ids[0]
        }
    }

    /// Up or Shift-Tab: previous control, wrapping; starts at the last.
    public mutating func previous(in ids: [ID]) {
        guard !ids.isEmpty else { highlighted = nil; return }
        if let current = highlighted, let i = ids.firstIndex(of: current) {
            highlighted = ids[(i - 1 + ids.count) % ids.count]
        } else {
            highlighted = ids[ids.count - 1]
        }
    }

    public mutating func hover(_ id: ID) { highlighted = id }

    public mutating func clear() { highlighted = nil }
}
