import SwiftUI
import MarkdownUI

/// Renders a markdown string using MarkdownUI, themed to match the inspector's
/// existing text sections (secondary foreground, relative font scaling,
/// selectable text). The body font scales the whole document; notes/closure use
/// `.caption` so the section reads smaller, as before.
struct MarkdownSection: View {
    let text: String
    var font: Font = .body

    /// Base `em` size for the section. `.caption` scales the whole document down
    /// relative to `.body`. Heading multipliers are applied on top of this base.
    private var baseEm: CGFloat {
        font == .caption ? 0.85 : 1
    }

    var body: some View {
        Markdown(text)
            .markdownTheme(.inspector(baseEm: baseEm))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private extension Theme {
    /// A compact theme tuned for the translucent glass inspector: muted text,
    /// no opaque block backgrounds, and proportional sizing that adapts to the
    /// system text styles already used in the rest of the inspector.
    static func inspector(baseEm: CGFloat) -> Theme {
        Theme()
            .text {
                ForegroundColor(.secondary)
                FontSize(.em(baseEm))
            }
            .strong {
                FontWeight(.semibold)
            }
            .link {
                ForegroundColor(Color.accentColor)
            }
            .heading1 { configuration in
                configuration.label
                    .markdownMargin(top: .em(1.2), bottom: .em(0.4))
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(baseEm * 1.7))
                    }
            }
            .heading2 { configuration in
                configuration.label
                    .markdownMargin(top: .em(1.2), bottom: .em(0.4))
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(baseEm * 1.5))
                    }
            }
            .heading3 { configuration in
                configuration.label
                    .markdownMargin(top: .em(1.1), bottom: .em(0.3))
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(baseEm * 1.25))
                    }
            }
            .heading4 { configuration in
                configuration.label
                    .markdownMargin(top: .em(1.1), bottom: .em(0.3))
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(baseEm))
                    }
            }
            .heading5 { configuration in
                configuration.label
                    .markdownMargin(top: .em(1), bottom: .em(0.3))
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(baseEm * 0.9))
                    }
            }
            .heading6 { configuration in
                configuration.label
                    .markdownMargin(top: .em(1), bottom: .em(0.3))
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        ForegroundColor(Color.secondary.opacity(0.8))
                        FontSize(.em(baseEm * 0.85))
                    }
            }
            .paragraph { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.15))
                    .markdownMargin(top: 0, bottom: 10)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(baseEm * 0.85))
                BackgroundColor(Color.secondary.opacity(0.12))
            }
            .codeBlock { configuration in
                ScrollView(.horizontal) {
                    configuration.label
                        .fixedSize(horizontal: false, vertical: true)
                        .relativeLineSpacing(.em(0.2))
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(.em(baseEm * 0.85))
                        }
                        .padding(8)
                }
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                .markdownMargin(top: 0, bottom: 10)
            }
            .blockquote { configuration in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 2)
                    configuration.label
                        .markdownTextStyle { ForegroundColor(.secondary) }
                        .fixedSize(horizontal: false, vertical: true)
                }
                .markdownMargin(top: 0, bottom: 10)
            }
            .listItem { configuration in
                configuration.label
                    .markdownMargin(top: .em(0.15))
            }
            .thematicBreak {
                Divider()
                    .markdownMargin(top: .em(0.8), bottom: .em(0.8))
            }
    }
}
