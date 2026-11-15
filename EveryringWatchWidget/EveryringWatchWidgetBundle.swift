import SwiftUI
import WidgetKit

/// Apple Watch complications. The watch app computes progress from the watch's own Health data and caches it in the
/// watch's App Group; the complications draw from that cache.
@main
struct EveryringWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        RingsWidget()
    }
}
