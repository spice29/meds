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

    // ====== غيّر ألوان التطبيق من هنا فقط ======
    static let appBG = Color(light: 0xEAF1FB, dark: 0x0B1220)     // خلفية الصفحات
    static let cardBG = Color(light: 0xFFFFFF, dark: 0x172033)    // خلفية البطاقات
    static let brand = Color(light: 0x1A6FE0, dark: 0x6FA8FF)     // اللون الأساسي
    static let softText = Color(light: 0x5B6E86, dark: 0x9FB0C8)  // النصوص الثانوية
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Color.cardBG, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}
