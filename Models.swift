import SwiftUI

enum Slot: String, CaseIterable, Codable, Identifiable {
    case morning, afternoon, evening

    var id: String { rawValue }

    var hour: Int {
        switch self {
        case .morning: return 8
        case .afternoon: return 14
        case .evening: return 20
        }
    }

    var title: String {
        switch self {
        case .morning: return "الصباح"
        case .afternoon: return "بعد الظهر"
        case .evening: return "المساء"
        }
    }

    var timeLabel: String {
        switch self {
        case .morning: return "8 ص"
        case .afternoon: return "2 م"
        case .evening: return "8 م"
        }
    }

    var color: Color {
        switch self {
        case .morning: return .orange
        case .afternoon: return .teal
        case .evening: return .indigo
        }
    }

    /// الفترة الحالية حسب ساعة اليوم
    static var current: Slot {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 11 ? .morning : (h < 17 ? .afternoon : .evening)
    }
}

struct Medication: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String = ""
    var note: String = ""
    var qty: Double = 1            // عدد الحبات في الجرعة (يقبل أنصاف)
    var slots: Set<Slot> = []

    var sortedSlots: [Slot] { Slot.allCases.filter { slots.contains($0) } }

    var qtyText: String {
        let w = Int(qty.rounded(.down))
        let half = qty.truncatingRemainder(dividingBy: 1) >= 0.5
        if w == 0 { return "نصف حبة" }
        let base = w == 1 ? "حبة" : (w == 2 ? "حبتين" : "\(w) حبات")
        return half ? "\(base) ونصف" : base
    }

    var frequencyText: String {
        switch slots.count {
        case 0: return "اختر وقتاً واحداً على الأقل"
        case 1: return "مرة يومياً"
        case 2: return "مرتين يومياً"
        default: return "3 مرات يومياً"
        }
    }
}
