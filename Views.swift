import SwiftUI
import UIKit

func durationText(_ m: Int) -> String {
    if m < 1 { return "أقل من دقيقة" }
    let h = m / 60
    let r = m % 60
    if h == 0 { return "\(r) دقيقة" }
    if r == 0 { return "\(h) ساعة" }
    return "\(h) س و\(r) د"
}

// MARK: - تبويب اليوم

struct TodayView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    NotificationsBanner()
                    if store.meds.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "pills").font(.largeTitle)
                            Text("ما أضفت أي دواء بعد").font(.headline)
                            Text("افتح تبويب الخزانة وأضف أول دواء")
                                .font(.footnote).foregroundStyle(Color.softText)
                        }
                        .frame(maxWidth: .infinity)
                        .card()
                    } else {
                        SummaryCard()
                        LowStockBanner()
                        ForEach(store.schedule) { g in
                            TimeCard(group: g)
                        }
                        DayConfirmCard()
                    }
                }
                .padding()
            }
            .background(ThemedBackground().ignoresSafeArea())
            .navigationTitle("الجرعات اليومية")
        }
    }
}

struct NotificationsBanner: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var phase
    @State private var ok = true

    var body: some View {
        Group {
            if !ok {
                HStack(spacing: 10) {
                    Image(systemName: "bell.slash.fill").foregroundStyle(Color.orange)
                    Text("الإشعارات مقفلة، فما راح يوصلك تذكير").font(.subheadline)
                    Spacer()
                    Button("الإعدادات") {
                        if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) }
                    }
                    .font(.subheadline.bold())
                }
                .card()
            }
        }
        .task { ok = await NotificationManager.shared.isAuthorized() }
        .onChange(of: phase) { p in
            if p == .active {
                Task { ok = await NotificationManager.shared.isAuthorized() }
            }
        }
    }
}

struct SummaryCard: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        let done = store.doneToday
        let total = store.totalToday
        let finished = total > 0 && done >= total

        VStack(alignment: .leading, spacing: 10) {
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                .environment(\.locale, Locale(identifier: "ar_SA@calendar=gregorian"))
                .font(.subheadline)
                .opacity(0.85)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(done)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                Text("/ \(total)")
                    .font(.title2)
                    .opacity(0.8)
                Spacer()
                Text(finished ? "تم أخذها" : "المتبقي: \(max(total - done, 0))")
                    .font(.headline)
            }

            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .tint(Color.white)

            if finished {
                Label(store.isDayConfirmed ? "تم تأكيد اليوم" : "اكتملت جميع جرعات اليوم",
                      systemImage: "checkmark.seal.fill")
                    .font(.headline)
            } else if let n = store.nextPending {
                Label("القادمة \(n.label) · بعد \(durationText(n.inMinutes))", systemImage: "clock")
                    .font(.subheadline)
            }
        }
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(LinearGradient(colors: settings.value.theme.hero,
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
    }
}

struct LowStockBanner: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let low = store.lowStockMeds
        if !low.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("مخزون قارب على الانتهاء").font(.subheadline.bold())
                    Text(low.map { $0.name }.joined(separator: "، "))
                        .font(.footnote).foregroundStyle(Color.softText)
                }
                Spacer()
            }
            .card()
        }
    }
}

struct TimeCard: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: SettingsStore
    let group: DoseGroup
    @State private var askConfirm = false
    @State private var askUndo = false

    var body: some View {
        let p = group.time.period
        let doneCount = group.meds.filter { store.isTaken($0, group.time) }.count
        let allDone = doneCount == group.meds.count
        let confirmedAt = store.slotConfirmDate(group.id)
        let locked = store.isLocked(group.id)

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: p.icon).foregroundStyle(p.color)
                Text(group.time.label).font(.title3.bold()).foregroundStyle(p.color)
                Text(p.title).font(.headline)
                StatusTag(group: group, allDone: allDone)
                Spacer()
                Text("\(doneCount)/\(group.meds.count)")
                    .monospacedDigit()
                    .foregroundStyle(Color.softText)
            }

            ForEach(group.meds) { med in
                DoseRow(med: med, time: group.time, locked: locked)
            }

            if let at = confirmedAt {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.green)
                    Text("تم التأكيد \(at.formatted(date: .omitted, time: .shortened))")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.green)
                    Spacer()
                    if settings.value.allowUndoConfirm {
                        Button("تراجع") { askUndo = true }
                            .font(.footnote)
                    }
                }
                .padding(.top, 6)
            } else if allDone {
                Button { askConfirm = true } label: {
                    Label("تأكيد أخذ جرعات \(group.time.label)", systemImage: "checkmark.shield.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)
            }
        }
        .card()
        .confirmationDialog("تأكيد جرعات \(group.time.label)",
                            isPresented: $askConfirm, titleVisibility: .visible) {
            Button("نعم، أخذتها كلها") {
                if settings.value.haptics {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                store.confirmSlot(group.id)
            }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("بعد التأكيد تنقفل الجرعات عشان ما تنشال علامة الصح بالغلط.")
        }
        .confirmationDialog("إلغاء التأكيد؟", isPresented: $askUndo, titleVisibility: .visible) {
            Button("إلغاء التأكيد", role: .destructive) { store.undoConfirmSlot(group.id) }
            Button("رجوع", role: .cancel) {}
        } message: {
            Text("راح تنفتح الجرعات من جديد ويسقط تأكيد اليوم لو كان مؤكد.")
        }
    }
}

struct StatusTag: View {
    @EnvironmentObject var store: Store
    @Environment(\.accent) private var accent
    let group: DoseGroup
    let allDone: Bool

    private var tag: (String, Color)? {
        if allDone { return nil }
        if group.time.minutes + 60 < minutesNow() { return ("متأخرة", Color.red) }
        if store.nextPendingTimeId == group.id { return ("التالي", accent) }
        return nil
    }

    var body: some View {
        if let t = tag {
            Text(t.0)
                .font(.caption.bold())
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(t.1.opacity(0.15), in: Capsule())
                .foregroundStyle(t.1)
        }
    }
}

struct DoseRow: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: SettingsStore
    let med: Medication
    let time: DoseTime
    let locked: Bool

    var body: some View {
        let taken = store.isTaken(med, time)

        Button {
            if settings.value.haptics {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            store.toggle(med, time)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: taken ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(taken ? Color.green : time.period.color)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: med.form.icon)
                            .font(.caption)
                            .foregroundStyle(Color.softText)
                        Text(med.name)
                            .font(.body.weight(.semibold))
                            .strikethrough(taken)
                    }
                    Text(med.doseText)
                        .font(.subheadline.bold())
                        .foregroundStyle(time.period.color)
                    if med.meal != .unspecified {
                        Text(med.meal.title).font(.caption).foregroundStyle(Color.softText)
                    }
                    if !med.note.isEmpty {
                        Text(med.note).font(.caption).foregroundStyle(Color.softText)
                    }
                }
                .opacity(taken ? 0.55 : 1)

                Spacer()

                if locked {
                    Image(systemName: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.softText)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!locked)
    }
}

struct DayConfirmCard: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: SettingsStore
    @State private var ask = false
    @State private var askUndo = false

    var body: some View {
        let total = store.totalToday
        let done = store.doneToday

        VStack(alignment: .leading, spacing: 10) {
            if let at = store.dayConfirmDate {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(Color.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("تم تأكيد إتمام اليوم").font(.headline)
                        Text("انحفظ في السجل الساعة \(at.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote).foregroundStyle(Color.softText)
                    }
                    Spacer()
                    if settings.value.allowUndoConfirm {
                        Button("تراجع") { askUndo = true }.font(.footnote)
                    }
                }
            } else if total > 0 && done >= total {
                Text("خلّصت كل جرعات اليوم 🎉").font(.headline)
                Text("أكّد إتمام اليوم عشان ينحفظ في السجل.")
                    .font(.footnote).foregroundStyle(Color.softText)
                Button { ask = true } label: {
                    Label("تأكيد إتمام جرعات اليوم", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Label("أكمل كل الجرعات لتأكيد اليوم · المتبقي \(max(total - done, 0))",
                      systemImage: "lock.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.softText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .confirmationDialog("هل أخذت جميع أدويتك اليوم؟", isPresented: $ask, titleVisibility: .visible) {
            Button("نعم، أكّد اليوم") {
                if settings.value.haptics {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                store.confirmDay()
            }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("ينحفظ اليوم في السجل كيوم مؤكد.")
        }
        .confirmationDialog("إلغاء تأكيد اليوم؟", isPresented: $askUndo, titleVisibility: .visible) {
            Button("إلغاء التأكيد", role: .destructive) { store.undoConfirmDay() }
            Button("رجوع", role: .cancel) {}
        }
    }
}

// MARK: - خزانة الأدوية

struct CabinetView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.accent) private var accent
    @State private var editing: Medication?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if store.meds.isEmpty {
                        Text("الخزانة فاضية، اضغط + لإضافة دواء")
                            .foregroundStyle(Color.softText)
                            .frame(maxWidth: .infinity)
                            .card()
                    }
                    ForEach(store.meds) { med in
                        Button { editing = med } label: { CabinetCard(med: med) }
                            .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(ThemedBackground().ignoresSafeArea())
            .navigationTitle("خزانة الأدوية")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { editing = Medication.blank() } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                }
            }
            .sheet(item: $editing) { med in
                MedEditor(med: med)
                    .environmentObject(store)
                    .environmentObject(settings)
                    .environment(\.accent, accent)
                    .environment(\.layoutDirection, .rightToLeft)
                    .tint(accent)
                    .preferredColorScheme(settings.value.appearance.scheme)
            }
        }
    }
}

struct CabinetCard: View {
    @Environment(\.accent) private var accent
    let med: Medication

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: med.form.icon)
                    .font(.title3)
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .background(accent.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(med.name).font(.headline)
                    Text("\(med.doseText) · \(med.frequencyText)")
                        .font(.subheadline).foregroundStyle(Color.softText)
                }
                Spacer()
                Image(systemName: "chevron.left").font(.footnote).foregroundStyle(Color.softText)
            }

            if med.meal != .unspecified || !med.note.isEmpty {
                let extra = [med.meal == .unspecified ? "" : med.meal.title, med.note]
                    .filter { !$0.isEmpty }.joined(separator: " · ")
                Text(extra).font(.footnote).foregroundStyle(Color.softText)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84))], alignment: .leading, spacing: 6) {
                ForEach(med.times) { t in
                    Text(t.label)
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(t.period.color.opacity(0.15), in: Capsule())
                        .foregroundStyle(t.period.color)
                }
            }

            if med.tracksStock {
                HStack(spacing: 6) {
                    Image(systemName: med.isLow ? "exclamationmark.triangle.fill" : "shippingbox.fill")
                    Text(stockLine)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(med.isLow ? Color.orange : Color.softText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var stockLine: String {
        var s = "المتوفر: \(med.stockText)"
        if let d = med.daysLeft { s += " · يكفي حوالي \(d) يوم" }
        return s
    }
}

// MARK: - إضافة / تعديل دواء

struct MedEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: Store
    @State private var med: Medication
    @State private var pickerDate: Date =
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var confirmDelete = false

    private static let presets = [DoseTime(hour: 8, minute: 0),
                                  DoseTime(hour: 14, minute: 0),
                                  DoseTime(hour: 20, minute: 0)]

    init(med: Medication) { _med = State(initialValue: med) }

    private var isNew: Bool { !store.meds.contains { $0.id == med.id } }

    private var canSave: Bool {
        !med.name.trimmingCharacters(in: .whitespaces).isEmpty && !med.times.isEmpty
    }

    private var allTimes: [DoseTime] {
        Array(Set(Self.presets + med.times)).sorted()
    }

    private func toggleTime(_ t: DoseTime) {
        if let i = med.times.firstIndex(of: t) {
            med.times.remove(at: i)
        } else {
            med.times.append(t)
            med.times.sort()
        }
    }

    private func addPicked() {
        let c = Calendar.current.dateComponents([.hour, .minute], from: pickerDate)
        let t = DoseTime(hour: c.hour ?? 8, minute: c.minute ?? 0)
        if !med.times.contains(t) {
            med.times.append(t)
            med.times.sort()
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("بيانات الدواء") {
                    TextField("اسم الدواء", text: $med.name)

                    Picker("شكل الدواء", selection: $med.form) {
                        ForEach(MedForm.allCases) { f in
                            Label(f.title, systemImage: f.icon).tag(f)
                        }
                    }

                    Stepper(value: $med.dose, in: 0.5...20, step: med.form.step) {
                        HStack {
                            Text("جرعة واحدة")
                            Spacer()
                            Text(med.doseText).bold()
                        }
                    }

                    TextField("ملاحظات إضافية", text: $med.note, axis: .vertical)
                }

                Section("التعليمات والمواعيد") {
                    Picker("علاقة الوجبة", selection: $med.meal) {
                        ForEach(MealRelation.allCases) { m in
                            Text(m.title).tag(m)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("أوقات الأخذ").font(.subheadline).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92))], spacing: 8) {
                            ForEach(allTimes) { t in
                                let on = med.times.contains(t)
                                Text(t.label)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(on ? t.period.color.opacity(0.18) : Color.gray.opacity(0.12),
                                                in: Capsule())
                                    .foregroundStyle(on ? t.period.color : Color.secondary)
                                    .onTapGesture { toggleTime(t) }
                            }
                        }
                    }

                    HStack {
                        DatePicker("وقت آخر", selection: $pickerDate,
                                   displayedComponents: .hourAndMinute)
                        Button("إضافة") { addPicked() }
                            .buttonStyle(.borderless)
                    }
                }

                Section {
                    Toggle("تتبع الحبات المتبقية", isOn: $med.tracksStock)
                    if med.tracksStock {
                        Stepper(value: $med.stock, in: 0...5000,
                                step: med.form == .liquid ? 10 : 1) {
                            HStack {
                                Text("العدد المتوفر حالياً:")
                                Spacer()
                                Text(fmt(med.stock)).bold()
                            }
                        }
                        Stepper(value: $med.lowStockAt, in: 0...500, step: 1) {
                            HStack {
                                Text("تنبيه النقص عند:")
                                Spacer()
                                Text(fmt(med.lowStockAt)).bold()
                            }
                        }
                    }
                } header: {
                    Text("إدارة المخزون")
                } footer: {
                    if med.tracksStock {
                        Text("ينقص المخزون تلقائياً كل ما علّمت جرعة، ويجيك إشعار لما يوصل حد التنبيه.")
                    }
                }

                if !isNew {
                    Section {
                        Button("حذف الدواء", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ThemedBackground().ignoresSafeArea())
            .navigationTitle(isNew ? "دواء جديد" : "بيانات الدواء")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") {
                        med.name = med.name.trimmingCharacters(in: .whitespaces)
                        store.upsert(med)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onChange(of: med.form) { f in
                if f == .injection { med.dose = max(1, med.dose.rounded()) }
            }
            .confirmationDialog("حذف هذا الدواء؟", isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("حذف", role: .destructive) {
                    store.delete(med.id)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - السجل

struct DayStat: Identifiable {
    let offset: Int
    let date: Date
    let done: Int
    let total: Int?
    let confirmedAt: Date?

    var id: Int { offset }

    var complete: Bool {
        if let t = total { return done >= t }
        return false
    }

    var ratio: Double {
        if let t = total, t > 0 { return min(1, Double(done) / Double(t)) }
        return 0
    }
}

struct StatBox: View {
    let value: String
    let title: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 26, weight: .bold, design: .rounded))
            Text(title).font(.caption).foregroundStyle(Color.softText)
        }
        .frame(maxWidth: .infinity)
    }
}

struct HistoryView: View {
    @EnvironmentObject var store: Store
    @Environment(\.accent) private var accent

    private var stats: [DayStat] {
        (0..<14).map { i in
            let s = store.summary(daysAgo: i)
            let d = Calendar.current.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            return DayStat(offset: i, date: d, done: s.done, total: s.total,
                           confirmedAt: store.dayConfirmedDate(daysAgo: i))
        }
    }

    private func streak(_ stats: [DayStat]) -> Int {
        var n = 0
        for s in stats {
            if s.complete { n += 1 }
            else if s.offset == 0 { continue }
            else { break }
        }
        return n
    }

    private func adherence(_ stats: [DayStat]) -> Int? {
        var done = 0
        var total = 0
        for s in stats {
            guard let t = s.total else { continue }
            if s.offset == 0 && s.done < t { continue }
            done += min(s.done, t)
            total += t
        }
        if total == 0 { return nil }
        return Int((Double(done) / Double(total) * 100).rounded())
    }

    private func barColor(_ s: DayStat) -> Color {
        if s.total == nil { return Color.gray.opacity(0.25) }
        if s.confirmedAt != nil { return Color.green }
        if s.complete { return Color.turquoise }
        return accent
    }

    var body: some View {
        let stats = self.stats
        let fullDays = stats.filter { $0.complete }.count
        let confirmedDays = stats.filter { $0.confirmedAt != nil }.count
        let pct = adherence(stats)
        let run = streak(stats)

        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            StatBox(value: pct.map { "\($0)%" } ?? "—", title: "الالتزام")
                            StatBox(value: "\(fullDays)", title: "أيام مكتملة")
                            StatBox(value: "\(confirmedDays)", title: "أيام مؤكدة")
                        }

                        if run > 1 {
                            Label("\(run) أيام متتالية", systemImage: "flame.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(Color.orange)
                        }

                        HStack(alignment: .bottom, spacing: 6) {
                            ForEach(stats) { s in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(barColor(s))
                                    .frame(height: 6 + 54 * s.ratio)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 62, alignment: .bottom)

                        Text("الأخضر = يوم مؤكد · التركوازي = مكتمل بدون تأكيد")
                            .font(.caption2).foregroundStyle(Color.softText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                    ForEach(stats) { s in
                        HistoryRow(stat: s)
                    }
                }
                .padding()
            }
            .background(ThemedBackground().ignoresSafeArea())
            .navigationTitle("السجل")
        }
    }
}

struct HistoryRow: View {
    @Environment(\.accent) private var accent
    let stat: DayStat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                dayLabel
                    .font(.headline)
                if stat.confirmedAt != nil {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.green)
                } else if stat.complete {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.turquoise)
                }
                Spacer()
                if let t = stat.total {
                    Text("\(stat.done)/\(t)").monospacedDigit().foregroundStyle(Color.softText)
                } else {
                    Text("لا يوجد تسجيل").font(.footnote).foregroundStyle(Color.softText)
                }
            }
            if let at = stat.confirmedAt {
                Text("مؤكد الساعة \(at.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(Color.green)
            }
            if stat.total != nil {
                ProgressView(value: stat.ratio)
                    .tint(stat.confirmedAt != nil ? Color.green : accent)
            }
        }
        .card()
    }

    @ViewBuilder
    private var dayLabel: some View {
        if stat.offset == 0 {
            Text("اليوم")
        } else if stat.offset == 1 {
            Text("أمس")
        } else {
            Text(stat.date, format: .dateTime.weekday(.wide).day().month(.wide))
                .environment(\.locale, Locale(identifier: "ar_SA@calendar=gregorian"))
        }
    }
}
