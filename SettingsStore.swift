import SwiftUI

// MARK: - المظهر والألوان

enum AppearanceMode: String, CaseIterable, Codable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "حسب الجهاز"
        case .light: return "فاتح"
        case .dark: return "داكن"
        }
    }

    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppTheme: String, CaseIterable, Codable, Identifiable {
    case ocean, blue, turquoise
    var id: String { rawValue }

    var title: String {
        switch self {
        case .ocean: return "أزرق وتركوازي"
        case .blue: return "أزرق"
        case .turquoise: return "تركوازي"
        }
    }

    var accent: Color {
        switch self {
        case .ocean, .blue: return Color(light: 0x1A6FE0, dark: 0x6FA8FF)
        case .turquoise: return Color(light: 0x0A9396, dark: 0x4FD1C5)
        }
    }

    /// أعلى الخلفية
    var top: Color {
        switch self {
        case .ocean: return Color(light: 0xD3E6FF, dark: 0x0A1D3B)
        case .blue: return Color(light: 0xE1EBFC, dark: 0x0B1426)
        case .turquoise: return Color(light: 0xD3F3EF, dark: 0x062423)
        }
    }

    /// أسفل الخلفية
    var bottom: Color {
        switch self {
        case .ocean: return Color(light: 0xC9F3EC, dark: 0x0A3A3C)
        case .blue: return Color(light: 0xCFE0FA, dark: 0x102245)
        case .turquoise: return Color(light: 0xC3EAEF, dark: 0x0A3236)
        }
    }

    /// تدرج البطاقة الرئيسية
    var hero: [Color] {
        switch self {
        case .ocean: return [Color(light: 0x1A6FE0, dark: 0x1E4FA8), Color(light: 0x0DA9A2, dark: 0x0D7F7B)]
        case .blue: return [Color(light: 0x2B7DF0, dark: 0x1E4FA8), Color(light: 0x4C5FD7, dark: 0x2E3A91)]
        case .turquoise: return [Color(light: 0x0A9396, dark: 0x0D7F7B), Color(light: 0x12A58F, dark: 0x138A6E)]
        }
    }
}

// MARK: - الإعدادات

struct AppSettings: Codable, Equatable {
    var appearance: AppearanceMode = .system
    var theme: AppTheme = .ocean

    var remindersEnabled = true
    var soundEnabled = true
    var sound: NotifSound = .chime
    var snoozeMinutes = 15
    var lowStockAlerts = true
    var endOfDayReminder = true
    var endOfDayHour = 22
    var endOfDayMinute = 0

    var lockConfirmed = true
    var allowUndoConfirm = true
    var haptics = true
    var requireBiometric = false

    init() {}

    // قراءة مرنة: أي إعداد جديد يضاف مستقبلاً ما يخرب الإعدادات المحفوظة
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? .system
        theme = try c.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .ocean
        remindersEnabled = try c.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? true
        soundEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        sound = try c.decodeIfPresent(NotifSound.self, forKey: .sound) ?? .chime
        snoozeMinutes = try c.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? 15
        lowStockAlerts = try c.decodeIfPresent(Bool.self, forKey: .lowStockAlerts) ?? true
        endOfDayReminder = try c.decodeIfPresent(Bool.self, forKey: .endOfDayReminder) ?? true
        endOfDayHour = try c.decodeIfPresent(Int.self, forKey: .endOfDayHour) ?? 22
        endOfDayMinute = try c.decodeIfPresent(Int.self, forKey: .endOfDayMinute) ?? 0
        lockConfirmed = try c.decodeIfPresent(Bool.self, forKey: .lockConfirmed) ?? true
        allowUndoConfirm = try c.decodeIfPresent(Bool.self, forKey: .allowUndoConfirm) ?? true
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? true
        requireBiometric = try c.decodeIfPresent(Bool.self, forKey: .requireBiometric) ?? false
    }

    private static let key = "jorati.settings.v1"

    static func load() -> AppSettings {
        if let data = UserDefaults.standard.data(forKey: key),
           let s = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return s
        }
        return AppSettings()
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var value: AppSettings {
        didSet {
            value.save()
            NotificationManager.shared.reschedule(Store.shared.meds)
            Store.shared.refreshEndOfDay()
        }
    }

    private init() {
        value = AppSettings.load()
    }
}
