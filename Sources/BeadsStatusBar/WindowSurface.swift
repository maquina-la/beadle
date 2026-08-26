import SwiftUI

/// A standard content-layer material for Beadle's real windows.
///
/// Liquid Glass belongs to controls and navigation, not app backgrounds. A
/// window container background also lets SwiftUI manage translucency, title-bar
/// integration, and active/inactive appearance instead of mutating `NSWindow`.
private struct BeadleWindowSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            if reduceTransparency {
                content.containerBackground(
                    Color(nsColor: .windowBackgroundColor),
                    for: .window
                )
            } else {
                content.containerBackground(.thickMaterial, for: .window)
            }
        } else if reduceTransparency {
            content.background(Color(nsColor: .windowBackgroundColor))
        } else {
            content.background(.thickMaterial)
        }
    }
}

extension View {
    func beadleWindowSurface() -> some View {
        modifier(BeadleWindowSurface())
    }
}
