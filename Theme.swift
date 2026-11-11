import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Color {
    /// لون يتغير تلقائياً بين الوضع الفاتح والداكن
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    static let cardBG = Color(light: 0xFFFFFF, dark: 0x12263A)
    static let softText = Color(light: 0x56697F, dark: 0xA3B4C9)
    static let turquoise = Color(light: 0x0FA3A3, dark: 0x4FD1C5)
}

// اللون الأساسي للثيم الحالي، يوصل لكل الشاشات عبر الـ Environment
private struct AccentKey: EnvironmentKey {
    static let defaultValue: Color = Color(light: 0x1A6FE0, dark: 0x6FA8FF)
}

extension EnvironmentValues {
    var accent: Color {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}

/// خلفية متدرجة (أزرق/تركوازي) حسب الثيم المختار
struct ThemedBackground: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        LinearGradient(colors: [settings.value.theme.top, settings.value.theme.bottom],
                       startPoint: .top, endPoint: .bottom)
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Color.cardBG.opacity(0.94),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.07), radius: 8, x: 0, y: 3)
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}
