import Foundation

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var meds: [Medication] = []
    /// مفتاح اليوم -> مجموعة "medID_slot" للجرعات المأخوذة
    @Published private(set) var log: [String: Set<String>] = [:]

    private let medsKey = "meds.v1"
    private let logKey = "log.v1"

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var todayKey: String { Self.dayFormatter.string(from: Date()) }

    private init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: medsKey),
           let v = try? JSONDecoder().decode([Medication].self, from: data) {
            meds = v
        } else {
            // أول تشغيل: نحمّل الأدوية الأولية من SeedData.swift ونحفظها
            meds = Self.seed
            if let data = try? JSONEncoder().encode(meds) { d.set(data, forKey: medsKey) }
        }
        if let data = d.data(forKey: logKey),
           let v = try? JSONDecoder().decode([String: Set<String>].self, from: data) { log = v }
    }

    // MARK: - القراءة

    func meds(for slot: Slot) -> [Medication] {
        meds.filter { $0.slots.contains(slot) }
    }

    private func key(_ med: Medication, _ slot: Slot) -> String {
        "\(med.id.uuidString)_\(slot.rawValue)"
    }

    func isTaken(_ med: Medication, _ slot: Slot) -> Bool {
        log[todayKey]?.contains(key(med, slot)) ?? false
    }

    func doneCount(_ slot: Slot) -> Int {
        meds(for: slot).filter { isTaken($0, slot) }.count
    }

    var totalToday: Int { Slot.allCases.reduce(0) { $0 + meds(for: $1).count } }
    var doneToday: Int { Slot.allCases.reduce(0) { $0 + doneCount($1) } }

    // MARK: - التعديل

    func toggle(_ med: Medication, _ slot: Slot) {
        var s = log[todayKey] ?? []
        let k = key(med, slot)
        if s.contains(k) { s.remove(k) } else { s.insert(k) }
        log[todayKey] = s
        saveLog()
    }

    /// يُستدعى من زر "أخذتها" في الإشعار
    func markSlotTaken(_ slot: Slot) {
        var s = log[todayKey] ?? []
        for m in meds(for: slot) { s.insert(key(m, slot)) }
        log[todayKey] = s
        saveLog()
    }

    func upsert(_ med: Medication) {
        if let i = meds.firstIndex(where: { $0.id == med.id }) {
            meds[i] = med
        } else {
            meds.append(med)
        }
        saveMeds()
    }

    func delete(at offsets: IndexSet) {
        meds.remove(atOffsets: offsets)
        saveMeds()
    }

    // MARK: - الحفظ

    private func saveMeds() {
        if let data = try? JSONEncoder().encode(meds) {
            UserDefaults.standard.set(data, forKey: medsKey)
        }
        NotificationManager.shared.reschedule(meds)
    }

    private func saveLog() {
        if log.count > 14 {
            for k in log.keys.sorted().dropLast(14) { log[k] = nil }
        }
        if let data = try? JSONEncoder().encode(log) {
            UserDefaults.standard.set(data, forKey: logKey)
        }
    }
}
