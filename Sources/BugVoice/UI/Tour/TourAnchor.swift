import SwiftUI
import VoiceCore

/// Frames of the views that carry `tourAnchor`, collected up to the main window.
struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [TourStop: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourStop: Anchor<CGRect>], nextValue: () -> [TourStop: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Marks this view as the target of a tour stop. A nil stop marks nothing.
    @ViewBuilder func tourAnchor(_ stop: TourStop?) -> some View {
        if let stop {
            anchorPreference(key: TourAnchorKey.self, value: .bounds) { [stop: $0] }
        } else {
            self
        }
    }
}

extension TourStop {
    /// The main-window page the stop is shown on.
    var page: Page {
        switch self {
        case .menuBar, .dictation: .dictation
        case .recordMeeting: .meetings
        case .scratchpad: .notes
        case .dictionary: .dictionary
        case .style: .style
        }
    }
}
