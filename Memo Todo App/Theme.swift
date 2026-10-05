import SwiftUI

/// Colors and metrics for the menu panel, matched to the design mock (always dark).
enum Theme {
    static let panelBackground = Color(hex: 0x252527)
    static let panelBorder = Color.white.opacity(0.12)
    static let primaryText = Color(hex: 0xE4E4E5)
    static let secondaryText = Color(hex: 0x909097)
    static let completedText = Color(hex: 0x6B6B70)
    static let placeholderText = Color(hex: 0x72727A)
    static let checkboxStroke = Color(hex: 0x535359)
    static let checkboxFill = Color(hex: 0x353539)
    static let checkmark = Color(hex: 0x8B8B96)
    static let rule = Color(hex: 0x3B3B3D)
    static let hover = Color.white.opacity(0.05)

    static let panelWidth: CGFloat = 351
    static let panelCornerRadius: CGFloat = 12
    static let arrowHeight: CGFloat = 8
    static let arrowWidth: CGFloat = 16
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
