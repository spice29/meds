import SwiftUI

// MARK: - تبويب اليوم

struct TodayView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            List {
                if store.totalToday == 0 {
                    Text("ما أضفت أي دواء بعد. أضف أول دواء من تبويب أدويتي.")
                        .foregroundStyle(.secondary)
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(store.doneToday)/\(store.totalToday)")
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                            Text(store.doneToday == store.totalToday
                                 ? "خلصت كل جرعات اليوم" : "جرعات اليوم")
                                .foregroundStyle(.secondary)
                            ProgressView(value: Double(store.doneToday),
                                         total: Double(max(store.totalToday, 1)))
                                .tint(.green)
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                            .environment(\.locale, Locale(identifier: "ar_SA@calendar=gregorian"))
                    }

                    ForEach(Slot.allCases) { slot in
                        let items = store.meds(for: slot)
                        if !items.isEmpty {
                            Section {
                                ForEach(items) { med in
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        store.toggle(med, slot)
                                    } label: {
                                        DoseRow(med: med, slot: slot,
                                                taken: store.isTaken(med, slot))
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                SlotHeader(slot: slot,
                                           done: store.doneCount(slot),
                                           total: items.count)
                            }
                        }
                    }
                }
            }
            .navigationTitle("جدول أدويتي")
        }
    }
}

struct SlotHeader: View {
    let slot: Slot
    let done: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(slot.timeLabel).font(.title3.bold()).foregroundStyle(slot.color)
            Text(slot.title).font(.headline)
            if slot == Slot.current {
                Text("الآن")
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(slot.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(slot.color)
            }
            Spacer()
            Text("\(done)/\(total)").foregroundStyle(.secondary).monospacedDigit()
        }
        .textCase(nil)
        .foregroundStyle(.primary)
    }
}

struct DoseRow: View {
    let med: Medication
    let slot: Slot
    let taken: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: taken ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(taken ? Color.green : slot.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(med.name).font(.body.weight(.semibold))
                    .strikethrough(taken)
                Text(med.qtyText).font(.subheadline.bold()).foregroundStyle(slot.color)
                if !med.note.isEmpty {
                    Text(med.note).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .opacity(taken ? 0.5 : 1)
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - تبويب أدويتي

struct MedsListView: View {
    @EnvironmentObject var store: Store
    @Environment(\.openURL) private var openURL
    @State private var editing: Medication?
    @State private var notificationsOK = true

    var body: some View {
        NavigationStack {
            List {
                if !notificationsOK {
                    Section {
                        Text("الإشعارات مقفلة، فما راح يوصلك تذكير.")
                        Button("فتح الإعدادات") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                    }
                }

                if store.meds.isEmpty {
                    Text("قائمة أدويتك فاضية.").foregroundStyle(.secondary)
                }

                ForEach(store.meds) { med in
                    Button { editing = med } label: { MedRow(med: med) }
                        .buttonStyle(.plain)
                }
                .onDelete { store.delete(at: $0) }
            }
            .navigationTitle("أدويتي")
            .toolbar {
                Button { editing = Medication() } label: { Image(systemName: "plus") }
            }
            .sheet(item: $editing) { med in
                MedEditor(med: med)
            }
            .task { notificationsOK = await NotificationManager.shared.isAuthorized() }
        }
    }
}

struct MedRow: View {
    let med: Medication

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(med.name).font(.body.weight(.semibold))
            Text("\(med.qtyText) في كل جرعة · \(med.frequencyText)")
                .font(.subheadline).foregroundStyle(.secondary)
            if !med.note.isEmpty {
                Text(med.note).font(.footnote).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(med.sortedSlots) { s in
                    Text(s.timeLabel)
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(s.color.opacity(0.15), in: Capsule())
                        .foregroundStyle(s.color)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

// MARK: - إضافة / تعديل

struct MedEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: Store
    @State private var med: Medication

    init(med: Medication) { _med = State(initialValue: med) }

    private var isNew: Bool { !store.meds.contains { $0.id == med.id } }
    private var canSave: Bool {
        !med.name.trimmingCharacters(in: .whitespaces).isEmpty && !med.slots.isEmpty
    }

    private func binding(_ slot: Slot) -> Binding<Bool> {
        Binding(
            get: { med.slots.contains(slot) },
            set: { on in
                if on { med.slots.insert(slot) } else { med.slots.remove(slot) }
            })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("الدواء") {
                    TextField("اسم الدواء", text: $med.name)
                    TextField("ملاحظة (مثل: بعد الأكل)", text: $med.note)
                }
                Section("عدد الحبات في كل جرعة") {
                    Stepper(value: $med.qty, in: 0.5...10, step: 0.5) {
                        Text(med.qtyText).bold()
                    }
                }
                Section {
                    ForEach(Slot.allCases) { slot in
                        Toggle(isOn: binding(slot)) {
                            Text("\(slot.timeLabel) · \(slot.title)")
                        }
                        .tint(slot.color)
                    }
                } header: {
                    Text("أوقات الأخذ")
                } footer: {
                    Text(med.frequencyText)
                }
            }
            .navigationTitle(isNew ? "إضافة دواء" : "تعديل الدواء")
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
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
