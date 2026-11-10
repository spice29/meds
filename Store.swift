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

    private struct Saved: Codable {
        var meds: [Medication]
        var log: [String: Set<String>]
        var totals: [String: Int]
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

    func summary(daysAgo i: Int) -> (done: Int, total: Int?) {
        let d = Calendar.current.date(byAdding: .day, value: -i, to: Date()) ?? Date()
        let k = Self.key(for: d)
        let done = i == 0 ? doneToday : (log[k]?.count ?? 0)
        let total = i == 0 ? totalToday : totals[k]
        return (done, (total ?? 0) == 0 ? nil : total)
    }

    /// يُستدعى كل دقيقة وعند فتح التطبيق، عشان ينتقل ليوم جديد لحاله
    func refresh() { objectWillChange.send() }

    // MARK: - التعديل

    func toggle(_ med: Medication, _ time: DoseTime) {
        guard let i = meds.firstIndex(where: { $0.id == med.id }) else { return }
        let k = key(med, time)
        var s = log[todayKey] ?? []
        if s.contains(k) {
            s.remove(k)
            if meds[i].tracksStock { meds[i].stock += meds[i].dose }
        } else {
            s.insert(k)
            consume(i)
        }
        log[todayKey] = s
        persist()
    }

    /// زر "أخذتها" في الإشعار: يعلّم كل أدوية هذا الوقت
    func markDosesTaken(timeId: Int) {
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

    private func persist() {
        totals[todayKey] = totalToday
        if log.count > 60 {
            for k in log.keys.sorted().dropLast(60) { log[k] = nil }
        }
        if totals.count > 60 {
            for k in totals.keys.sorted().dropLast(60) { totals[k] = nil }
        }
        let s = Saved(meds: meds, log: log, totals: totals)
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }
}
