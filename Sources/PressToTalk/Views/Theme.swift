import SwiftUI

/// Colours for the two-tone main window: a dark sidebar against light content.
///
/// The floating control bar and toast keep their own dark glass palette — they
/// sit over arbitrary desktop content, not over this window.
enum Theme {

    // MARK: Content (light)

    static let contentBackground = Color(red: 0.965, green: 0.965, blue: 0.972)
    static let contentBackgroundAlt = Color(red: 0.94, green: 0.94, blue: 0.95)

    /// Cards sit slightly above the page, so they are pure white with a hairline.
    static let card = Color.white
    static let cardBorder = Color.black.opacity(0.08)
    static let divider = Color.black.opacity(0.07)

    /// Low-contrast fill for inputs, chips and inactive tracks.
    static let subtleFill = Color.black.opacity(0.045)
    static let subtleFillStrong = Color.black.opacity(0.08)

    private static let ink = Color(red: 0.105, green: 0.11, blue: 0.13)
    static let textPrimary = ink
    static let textSecondary = ink.opacity(0.62)
    static let textTertiary = ink.opacity(0.42)
    static let textQuaternary = ink.opacity(0.28)

    /// Accents are darkened for legibility: the saturated system colours that
    /// read well on near-black wash out on a light background.
    static let accentPurple = Color(red: 0.42, green: 0.24, blue: 0.82)
    static let accentBlue = Color(red: 0.11, green: 0.42, blue: 0.86)
    static let accentGreen = Color(red: 0.11, green: 0.55, blue: 0.28)
    static let accentOrange = Color(red: 0.78, green: 0.42, blue: 0.05)
    static let accentRed = Color(red: 0.80, green: 0.18, blue: 0.16)
    static let accentPink = Color(red: 0.83, green: 0.20, blue: 0.44)
    static let accentCyan = Color(red: 0.05, green: 0.47, blue: 0.60)
    static let accentYellow = Color(red: 0.68, green: 0.50, blue: 0.02)

    // MARK: Sidebar (dark)

    static let sidebarBackground = Color(red: 0.075, green: 0.078, blue: 0.105)
    static let sidebarText = Color.white
    static let sidebarTextDim = Color.white.opacity(0.5)
    static let sidebarTextFaint = Color.white.opacity(0.3)
    static let sidebarSelection = Color.white.opacity(0.13)
    static let sidebarHover = Color.white.opacity(0.06)
    static let sidebarDivider = Color.white.opacity(0.08)
}
