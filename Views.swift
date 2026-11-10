import SwiftUI
import UIKit

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
                    }
                }
                .padding()
            }
            .background(Color.appBG.ignoresSafeArea())
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

    var body: some View {
        let done = store.doneToday
        let total = store.totalToday
        let finished = total > 0 && done >= total

        VStack(alignment: .leading, spacing: 10) {
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                .environment(\.locale, Locale(identifier: "ar_SA@calendar=gregorian"))
                .font(.subheadline)
                .foregroundStyle(Color.softText)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(done)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                Text("/ \(total)")
                    .font(.title2)
                    .foregroundStyle(Color.softText)
                Spacer()
                Text(finished ? "تم أخذها" : "المتبقي: \(max(total - done, 0))")
                    .font(.headline)
                    .foregroundStyle(finished ? Color.green : Color.softText)
            }

            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .tint(finished ? Color.green : Color.brand)

            if finished {
                Label("اكتملت جميع جرعات اليوم", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(Color.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
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
    let group: DoseGroup

    var body: some View {
        let p = group.time.period
        let doneCount = group.meds.filter { store.isTaken($0, group.time) }.count
        let allDone = doneCount == group.meds.count

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
                DoseRow(med: med, time: group.time)
            }
        }
        .card()
    }
}

struct StatusTag: View {
    @EnvironmentObject var store: Store
    let group: DoseGroup
    let allDone: Bool

    private var tag: (String, Color)? {
        if allDone { return nil }
        if group.time.minutes + 60 < minutesNow() { return ("متأخرة", Color.red) }
        if store.nextPendingTimeId == group.id { return ("التالي", Color.brand) }
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
    let med: Medication
    let time: DoseTime

    var body: some View {
        let taken = store.isTaken(med, time)

        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                .opacity(taken ? 0.5 : 1)

                Spacer()
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - خزانة الأدوية

struct CabinetView: View {
    @EnvironmentObject var store: Store
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
            .background(Color.appBG.ignoresSafeArea())
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
                    .environment(\.layoutDirection, .rightToLeft)
            }
        }
    }
}

struct CabinetCard: View {
    let med: Medication

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: med.form.icon)
                    .font(.title3)
                    .foregroundStyle(Color.brand)
                    .frame(width: 36, height: 36)
                    .background(Color.brand.opacity(0.12), in: Circle())
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
            .background(Color.appBG.ignoresSafeArea())
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

struct HistoryView: View {
    @EnvironmentObject var store: Store

    private var stats: [DayStat] {
        (0..<14).map { i in
            let s = store.summary(daysAgo: i)
            let d = Calendar.current.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            return DayStat(offset: i, date: d, done: s.done, total: s.total)
        }
    }

    private func streak(_ stats: [DayStat]) -> Int {
        var n = 0
        for s in stats {
            if s.complete { n += 1 }
            else if s.offset == 0 { continue }   // اليوم لسه ما خلص، ما يكسر السلسلة
            else { break }
        }
        return n
    }

    var body: some View {
        let stats = self.stats
        let fullDays = stats.filter { $0.complete }.count

        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(fullDays)")
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                            Text("/ 14 يوم مكتمل").foregroundStyle(Color.softText)
                            Spacer()
                            let s = streak(stats)
                            if s > 1 {
                                Label("\(s) أيام متتالية", systemImage: "flame.fill")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(Color.orange)
                            }
                        }

                        HStack(alignment: .bottom, spacing: 6) {
                            ForEach(stats) { s in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(s.total == nil ? Color.gray.opacity(0.25)
                                          : (s.complete ? Color.green : Color.brand))
                                    .frame(height: 6 + 54 * s.ratio)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 62, alignment: .bottom)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                    ForEach(stats) { s in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                dayLabel(s)
                                    .font(.headline)
                                if s.complete {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
                                }
                                Spacer()
                                if let t = s.total {
                                    Text("\(s.done)/\(t)").monospacedDigit().foregroundStyle(Color.softText)
                                } else {
                                    Text("لا يوجد تسجيل").font(.footnote).foregroundStyle(Color.softText)
                                }
                            }
                            if s.total != nil {
                                ProgressView(value: s.ratio)
                                    .tint(s.complete ? Color.green : Color.brand)
                            }
                        }
                        .card()
                    }
                }
                .padding()
            }
            .background(Color.appBG.ignoresSafeArea())
            .navigationTitle("السجل")
        }
    }

    @ViewBuilder
    private func dayLabel(_ s: DayStat) -> some View {
        if s.offset == 0 {
            Text("اليوم")
        } else if s.offset == 1 {
            Text("أمس")
        } else {
            Text(s.date, format: .dateTime.weekday(.wide).day().month(.wide))
                .environment(\.locale, Locale(identifier: "ar_SA@calendar=gregorian"))
        }
    }
}
