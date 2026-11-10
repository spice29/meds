import SwiftUI

// MARK: - أدوات مساعدة

func fmt(_ v: Double) -> String {
    v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
}

func minutesNow() -> Int {
    let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
    return (c.hour ?? 0) * 60 + (c.minute ?? 0)
}

// MARK: - شكل الدواء

enum MedForm: String, CaseIterable, Codable, Identifiable {
    case tablet, capsule, liquid, injection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tablet: return "حبة عادية"
        case .capsule: return "كبسولة"
        case .liquid: return "قطرات / شراب"
        case .injection: return "حقنة"
        }
    }

    var icon: String {
        switch self {
        case .tablet: return "pills.fill"
        case .capsule: return "capsule.fill"
        case .liquid: return "drop.fill"
        case .injection: return "syringe.fill"
        }
    }

    var stockUnit: String {
        switch self {
        case .tablet: return "حبة"
        case .capsule: return "كبسولة"
        case .liquid: return "مل"
        case .injection: return "حقنة"
        }
    }

    var step: Double { self == .injection ? 1 : 0.5 }

    /// نص الجرعة: حبة، حبتين، حبة ونصف، 5 مل ...
    func text(_ q: Double) -> String {
        switch self {
        case .tablet: return countable(q, "حبة", "حبتين", "حبات")
        case .capsule: return countable(q, "كبسولة", "كبسولتين", "كبسولات")
        case .injection: return countable(q, "حقنة", "حقنتين", "حقن")
        case .liquid: return "\(fmt(q)) مل"
        }
    }

    private func countable(_ q: Double, _ one: String, _ two: String, _ few: String) -> String {
        let w = Int(q.rounded(.down))
        let half = q - Double(w) >= 0.5
        if w == 0 { return "نصف \(one)" }
        let base = w == 1 ? one : (w == 2 ? two : (w <= 10 ? "\(w) \(few)" : "\(w) \(one)"))
        return half ? "\(base) ونصف" : base
    }
}

// MARK: - علاقة الوجبة

enum MealRelation: String, CaseIterable, Codable, Identifiable {
    case unspecified, onEmpty, beforeMeal, withMeal, afterMeal, beforeSleep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unspecified: return "بدون تحديد"
        case .onEmpty: return "على الريق"
        case .beforeMeal: return "قبل الطعام"
        case .withMeal: return "وسط الوجبة"
        case .afterMeal: return "بعد الطعام"
        case .beforeSleep: return "قبل النوم"
        }
    }
}

// MARK: - الأوقات

enum Period {
    case morning, afternoon, evening, night

    var title: String {
        switch self {
        case .morning: return "الصباح"
        case .afternoon: return "بعد الظهر"
        case .evening: return "المساء"
        case .night: return "الليل"
        }
    }

    var icon: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .night: return "moon.stars.fill"
        }
    }

    var color: Color {
        switch self {
        case .morning: return .orange
        case .afternoon: return .teal
        case .evening: return .indigo
        case .night: return .purple
        }
    }
}

struct DoseTime: Codable, Hashable, Comparable, Identifiable {
    var hour: Int
    var minute: Int

    var id: Int { hour * 60 + minute }
    var minutes: Int { hour * 60 + minute }

    static func < (a: DoseTime, b: DoseTime) -> Bool { a.minutes < b.minutes }

    var label: String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d", h, minute) + (hour < 12 ? " ص" : " م")
    }

    var period: Period {
        switch hour {
        case 4..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        default: return .night
        }
    }
}

// MARK: - الدواء

struct Medication: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String = ""
    var form: MedForm = .tablet
    var dose: Double = 1
    var meal: MealRelation = .unspecified
    var times: [DoseTime] = []
    var note: String = ""
    var tracksStock: Bool = false
    var stock: Double = 0
    var lowStockAt: Double = 5

    static func blank() -> Medication {
        var m = Medication()
        m.times = [DoseTime(hour: 8, minute: 0)]
        return m
    }

    var doseText: String { form.text(dose) }

    var frequencyText: String {
        switch times.count {
        case 0: return "بدون مواعيد"
        case 1: return "مرة يومياً"
        case 2: return "مرتين يومياً"
        default: return "\(times.count) مرات يومياً"
        }
    }

    var isLow: Bool { tracksStock && stock <= lowStockAt }

    var stockText: String { "\(fmt(stock)) \(form.stockUnit)" }

    /// كم يوم يكفي المخزون تقريباً
    var daysLeft: Int? {
        let perDay = dose * Double(times.count)
        guard tracksStock, perDay > 0 else { return nil }
        return Int(stock / perDay)
    }
}
