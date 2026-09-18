import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

enum Theme {
    static let bg = Color(light: UIColor(hex: 0xF2F2F4), dark: UIColor(hex: 0x0A0A0B))
    static let surface = Color(light: UIColor(hex: 0xFFFFFF), dark: UIColor(hex: 0x151517))
    static let raised = Color(light: UIColor(hex: 0xE6E6EA), dark: UIColor(hex: 0x232327))
    static let line = Color(light: UIColor(hex: 0x000000, alpha: 0.07), dark: UIColor(hex: 0xFFFFFF, alpha: 0.07))
    static let text = Color(light: UIColor(hex: 0x0E0E10), dark: UIColor(hex: 0xF5F5F7))
    static let muted = Color(light: UIColor(hex: 0x6E6E76), dark: UIColor(hex: 0x8C8C94))
}

enum Accent: String, CaseIterable, Identifiable {
    case ember, crimson, volt, ocean, mint, mono

    var id: String { rawValue }
    var name: String {
        switch self {
        case .ember: "Ember"
        case .crimson: "Crimson"
        case .volt: "Volt"
        case .ocean: "Ocean"
        case .mint: "Mint"
        case .mono: "Mono"
        }
    }
    var color: Color {
        switch self {
        case .ember: Color(hex: 0xFF5A1F)
        case .crimson: Color(hex: 0xE5484D)
        case .volt: Color(hex: 0xC4F03A)
        case .ocean: Color(hex: 0x3E8BFF)
        case .mint: Color(hex: 0x3DD68C)
        case .mono: Color(light: UIColor(hex: 0x111113), dark: UIColor(hex: 0xF5F5F7))
        }
    }
    /// Text and icons drawn on top of the accent.
    var ink: Color {
        switch self {
        case .volt, .mint: Color(hex: 0x0A0A0B)
        case .mono: Color(light: UIColor(hex: 0xF5F5F7), dark: UIColor(hex: 0x0A0A0B))
        default: .white
        }
    }

    static func from(_ s: HardState) -> Accent { Accent(rawValue: s.settings.accent) ?? .ember }
}

/// The 75 mark: a heavy italic numeral in an accent tile, then the word.
struct LogoMark: View {
    var size: CGFloat = 28
    var accent: Accent = .ember
    var word = true

    var body: some View {
        HStack(spacing: size * 0.28) {
            Text("75")
                .font(.system(size: size * 0.62, weight: .black))
                .italic()
                .fontWidth(.condensed)
                .foregroundStyle(accent.ink)
                .frame(width: size * 1.18, height: size)
                .background(accent.color, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            if word {
                Text("HARD")
                    .font(.system(size: size * 0.56, weight: .black))
                    .italic()
                    .fontWidth(.condensed)
                    .tracking(size * 0.03)
            }
        }
    }
}
