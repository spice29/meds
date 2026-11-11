import Foundation

struct DoseGroup: Identifiable {
    let time: DoseTime
    let meds: [Medication]
    var id: Int { time.id }
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var meds: [Medication] = []
    /// مفتاح اليوم -> الجرعات المأخوذة ("medID|timeID")
    @Published private(set) var log: [String: Set<String>] = [:]
    /// مفتاح اليوم -> إجمالي جرعات ذاك اليوم (للسجل)
    @Published private(set) var totals: [String: Int] = [:]
    /// مفتاح اليوم -> (رقم الوقت -> لحظة التأكيد)
    @Published private(set) var confirms: [String: [String: Double]] = [:]
    /// مفتاح اليوم -> لحظة تأكيد إتمام اليوم
    @Published private(set) var dayConfirmed: [String: Double] = [:]

    private struct Saved: Codable {
        var meds: [Medication]
        var log: [String: Set<String>]
        var totals: [String: Int]
        var confirms: [String: [String: Double]]?
        var dayConfirmed: [String: Double]?
    }

    private let storeKey = "jorati.v2"

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func key(for date: Date) -> String { dayFormatter.string(from: date) }
    private var todayKey: String { Self.key(for: Date()) }

    private init() {
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let s = try? JSONDecoder().decode(Saved.self, from: data) {
            meds = s.meds
            log = s.log
            totals = s.totals
            confirms = s.confirms ?? [:]
            dayConfirmed = s.dayConfirmed ?? [:]
        } else {
            meds = Self.seed
            persist()
        }
    }

    // MARK: - القراءة

    var schedule: [DoseGroup] {
        var dict: [DoseTime: [Medication]] = [:]
        for m in meds {
            for t in m.times { dict[t, default: []].append(m) }
        }
        return dict.keys.sorted().map { DoseGroup(time: $0, meds: dict[$0] ?? []) }
    }

    private func key(_ med: Medication, _ time: DoseTime) -> String {
        "\(med.id.uuidString)|\(time.id)"
    }

    func isTaken(_ med: Medication, _ time: DoseTime) -> Bool {
        log[todayKey]?.contains(key(med, time)) ?? false
    }

    var totalToday: Int { meds.reduce(0) { $0 + $1.times.count } }

    var doneToday: Int {
        var n = 0
        for g in schedule {
            for m in g.meds where isTaken(m, g.time) { n += 1 }
        }
        return n
    }

    var lowStockMeds: [Medication] { meds.filter { $0.isLow } }

    /// أول جرعة قادمة لسه ما انأخذت (أو متأخرة أقل من ساعة)
    var nextPendingTimeId: Int? {
        let now = minutesNow()
        for g in schedule {
            let pending = g.meds.contains { !isTaken($0, g.time) }
            if pending && g.time.minutes + 60 >= now { return g.id }
        }
        return nil
    }

    /// الجرعة القادمة ومتى (بالدقائق)
    var nextPending: (label: String, inMinutes: Int)? {
        let now = minutesNow()
        for g in schedule {
            let pending = g.meds.contains { !isTaken($0, g.time) }
            if pending && g.time.minutes >= now {
                return (g.time.label, g.time.minutes - now)
            }
        }
        return nil
    }

    func summary(daysAgo i: Int) -> (done: Int, total: Int?) {
        let d = Calendar.current.date(byAdding: .day, value: -i, to: Date()) ?? Date()
        let k = Self.key(for: d)
        let done = i == 0 ? doneToday : (log[k]?.count ?? 0)
        let total = i == 0 ? totalToday : totals[k]
        return (done, (total ?? 0) == 0 ? nil : total)
    }

    func dayConfirmedDate(daysAgo i: Int) -> Date? {
        let d = Calendar.current.date(byAdding: .day, value: -i, to: Date()) ?? Date()
        if let t = dayConfirmed[Self.key(for: d)] { return Date(timeIntervalSince1970: t) }
        return nil
    }

    /// يُستدعى كل دقيقة، عشان الشاشة تتحدث
    func refresh() { objectWillChange.send() }

    /// يُستدعى لما يفتح التطبيق
    func appBecameActive() {
        refresh()
        refreshEndOfDay()
    }

    func refreshEndOfDay() {
        NotificationManager.shared.scheduleEndOfDay(todayDone: isDayConfirmed || totalToday == 0)
    }

    // MARK: - التأكيدات

    func slotConfirmDate(_ timeId: Int) -> Date? {
        if let t = confirms[todayKey]?[String(timeId)] { return Date(timeIntervalSince1970: t) }
        return nil
    }

    func isSlotConfirmed(_ timeId: Int) -> Bool { slotConfirmDate(timeId) != nil }

    var dayConfirmDate: Date? {
        if let t = dayConfirmed[todayKey] { return Date(timeIntervalSince1970: t) }
        return nil
    }

    var isDayConfirmed: Bool { dayConfirmDate != nil }

    /// هل الجرعات مقفلة (بعد التأكيد)؟
    func isLocked(_ timeId: Int) -> Bool {
        guard SettingsStore.shared.value.lockConfirmed else { return false }
        return isDayConfirmed || isSlotConfirmed(timeId)
    }

    func isSlotComplete(_ g: DoseGroup) -> Bool {
        g.meds.allSatisfy { isTaken($0, g.time) }
    }

    func confirmSlot(_ timeId: Int) {
        guard let g = schedule.first(where: { $0.id == timeId }), isSlotComplete(g) else { return }
        confirms[todayKey, default: [:]][String(timeId)] = Date().timeIntervalSince1970
        persist()
    }

    func undoConfirmSlot(_ timeId: Int) {
        confirms[todayKey]?[String(timeId)] = nil
        dayConfirmed[todayKey] = nil
        persist()
        refreshEndOfDay()
    }

    func confirmDay() {
        guard totalToday > 0, doneToday >= totalToday else { return }
        let now = Date().timeIntervalSince1970
        for g in schedule where !isSlotConfirmed(g.id) {
            confirms[todayKey, default: [:]][String(g.id)] = now
        }
        dayConfirmed[todayKey] = now
        persist()
        refreshEndOfDay()
    }

    /// من زر "تأكيد اليوم" في الإشعار
    func confirmDayIfComplete() { confirmDay() }

    func undoConfirmDay() {
        dayConfirmed[todayKey] = nil
        persist()
        refreshEndOfDay()
    }

    // MARK: - التعديل

    func toggle(_ med: Medication, _ time: DoseTime) {
        guard !isLocked(time.id) else { return }
        guard let i = meds.firstIndex(where: { $0.id == med.id }) else { return }
        let k = key(med, time)
        var s = log[todayKey] ?? []
        if s.contains(k) {
            s.remove(k)
            if meds[i].tracksStock { meds[i].stock += meds[i].dose }
            // لو التأكيد مفتوح (القفل مطفي) وشلت علامة، يسقط التأكيد
            confirms[todayKey]?[String(time.id)] = nil
        } else {
            s.insert(k)
            consume(i)
        }
        log[todayKey] = s
        if doneToday < totalToday { dayConfirmed[todayKey] = nil }
        persist()
    }

    /// زر "أخذتها" في إشعار الجرعة: يعلّم كل أدوية الوقت ويؤكده
    func markDosesTaken(timeId: Int) {
        if isSlotConfirmed(timeId) { return }
        var s = log[todayKey] ?? []
        for i in meds.indices {
            guard let t = meds[i].times.first(where: { $0.id == timeId }) else { continue }
            let k = key(meds[i], t)
            if !s.contains(k) {
                s.insert(k)
                consume(i)
            }
        }
        log[todayKey] = s
        confirms[todayKey, default: [:]][String(timeId)] = Date().timeIntervalSince1970
        persist()
    }

    private func consume(_ i: Int) {
        guard meds[i].tracksStock else { return }
        let wasLow = meds[i].isLow
        meds[i].stock = max(0, meds[i].stock - meds[i].dose)
        if !wasLow && meds[i].isLow {
            NotificationManager.shared.notifyLowStock(meds[i])
        }
    }

    func upsert(_ med: Medication) {
        var m = med
        m.times = Array(Set(m.times)).sorted()
        if let i = meds.firstIndex(where: { $0.id == m.id }) {
            meds[i] = m
        } else {
            meds.append(m)
        }
        pruneToday()
        persist()
        NotificationManager.shared.reschedule(meds)
    }

    func delete(_ id: UUID) {
        meds.removeAll { $0.id == id }
        let prefix = id.uuidString + "|"
        log = log.mapValues { set in set.filter { !$0.hasPrefix(prefix) } }
        persist()
        NotificationManager.shared.reschedule(meds)
    }

    private func pruneToday() {
        var valid = Set<String>()
        for m in meds {
            for t in m.times { valid.insert(key(m, t)) }
        }
        if let s = log[todayKey] {
            log[todayKey] = s.filter { valid.contains($0) }
        }
    }

    // MARK: - نسخة احتياطية

    func exportBackup() -> String {
        let s = Saved(meds: meds, log: log, totals: totals,
                      confirms: confirms, dayConfirmed: dayConfirmed)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let d = try? enc.encode(s), let str = String(data: d, encoding: .utf8) else { return "" }
        return str
    }

    func importBackup(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let s = try? JSONDecoder().decode(Saved.self, from: data) else { return false }
        meds = s.meds
        log = s.log
        totals = s.totals
        confirms = s.confirms ?? [:]
        dayConfirmed = s.dayConfirmed ?? [:]
        persist()
        NotificationManager.shared.reschedule(meds)
        refreshEndOfDay()
        return true
    }

    // MARK: - الحفظ

    private func persist() {
        totals[todayKey] = totalToday
        if log.count > 60 {
            for k in log.keys.sorted().dropLast(60) { log[k] = nil }
        }
        if totals.count > 60 {
            for k in totals.keys.sorted().dropLast(60) { totals[k] = nil }
        }
        if confirms.count > 60 {
            for k in confirms.keys.sorted().dropLast(60) { confirms[k] = nil }
        }
        if dayConfirmed.count > 60 {
            for k in dayConfirmed.keys.sorted().dropLast(60) { dayConfirmed[k] = nil }
        }
        let s = Saved(meds: meds, log: log, totals: totals,
                      confirms: confirms, dayConfirmed: dayConfirmed)
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }
}
