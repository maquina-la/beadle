import SwiftUI

/// The background for Beadle's real windows — Dolt Health and Settings.
///
/// Three-way, like `DashboardBackground`: Liquid Glass on macOS 26, a material
/// underneath that, and an opaque window background when Reduce Transparency
/// is on. Pair it with `WindowTransparencyConfigurator`, or the window stays
/// opaque and glass has nothing behind it to sample, which renders as flat
/// grey fill.
struct BeadleWindowBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    var body: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: Rectangle())
        } else {
            Rectangle()
                .fill(.thinMaterial)
        }
    }
}

/// Glass background plus the window configuration it needs, including a
/// transparent title bar so the standard chrome does not sit as an opaque
/// slab above the glass.
extension View {
    func beadleWindowSurface() -> some View {
        background {
            ZStack {
                BeadleWindowBackground()
                WindowTransparencyConfigurator(stylesTitleBar: true)
                    .allowsHitTesting(false)
            }
        }
    }
}
