import SwiftUI
import UIKit
import UserNotifications

// MARK: - الإعدادات

struct SettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var store: Store
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var phase
    @State private var notifOK = true
    @State private var showBackup = false

    private var eodDate: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: settingsStore.value.endOfDayHour,
                                      minute: settingsStore.value.endOfDayMinute,
                                      second: 0, of: Date()) ?? Date()
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                settingsStore.value.endOfDayHour = c.hour ?? 22
                settingsStore.value.endOfDayMinute = c.minute ?? 0
            })
    }

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                remindersSection
                soundSection
                confirmSection
                privacySection
                dataSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(ThemedBackground().ignoresSafeArea())
            .navigationTitle("الإعدادات")
            .task { notifOK = await NotificationManager.shared.isAuthorized() }
            .onChange(of: phase) { p in
                if p == .active {
                    Task { notifOK = await NotificationManager.shared.isAuthorized() }
                }
            }
            .sheet(isPresented: $showBackup) {
                BackupView()
                    .environmentObject(store)
                    .environmentObject(settingsStore)
                    .environment(\.accent, settingsStore.value.theme.accent)
                    .environment(\.layoutDirection, .rightToLeft)
                    .tint(settingsStore.value.theme.accent)
                    .preferredColorScheme(settingsStore.value.appearance.scheme)
            }
        }
    }

    // MARK: المظهر

    private var appearanceSection: some View {
        Section {
            Picker("الوضع", selection: $settingsStore.value.appearance) {
                ForEach(AppearanceMode.allCases) { m in
                    Text(m.title).tag(m)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 14) {
                ForEach(AppTheme.allCases) { t in
                    let selected = settingsStore.value.theme == t
                    VStack(spacing: 6) {
                        Circle()
                            .fill(LinearGradient(colors: t.hero,
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 46, height: 46)
                            .overlay {
                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.headline)
                                        .foregroundStyle(Color.white)
                                }
                            }
                            .overlay {
                                Circle()
                                    .stroke(selected ? t.accent : Color.clear, lineWidth: 3)
                                    .padding(-4)
                            }
                        Text(t.title).font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture { settingsStore.value.theme = t }
                }
            }
        } header: {
            Text("المظهر والألوان")
        }
    }

    // MARK: التذكيرات

    private var remindersSection: some View {
        Section {
            if !notifOK {
                HStack(spacing: 10) {
                    Image(systemName: "bell.slash.fill").foregroundStyle(Color.orange)
                    Text("الإشعارات مقفلة من إعدادات الجهاز").font(.subheadline)
                    Spacer()
                    Button("فتح") {
                        if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) }
                    }
                    .buttonStyle(.borderless)
                }
            }

            Toggle("تذكيرات الجرعات", isOn: $settingsStore.value.remindersEnabled)

            if settingsStore.value.remindersEnabled {
                Picker("مدة التأجيل", selection: $settingsStore.value.snoozeMinutes) {
                    ForEach([5, 10, 15, 20, 30], id: \.self) { m in
                        Text("\(m) دقيقة").tag(m)
                    }
                }
            }

            Toggle("تنبيه نقص المخزون", isOn: $settingsStore.value.lowStockAlerts)

            Toggle("تذكير تأكيد نهاية اليوم", isOn: $settingsStore.value.endOfDayReminder)
            if settingsStore.value.endOfDayReminder {
                DatePicker("وقت التذكير", selection: eodDate, displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("التذكيرات والإشعارات")
        } footer: {
            Text("تذكير نهاية اليوم يوصلك فقط لو ما أكّدت إتمام جرعات اليوم.")
        }
    }

    // MARK: الصوت

    private var soundSection: some View {
        Section {
            Toggle("تشغيل صوت الإشعارات", isOn: $settingsStore.value.soundEnabled)

            if settingsStore.value.soundEnabled {
                ForEach(NotifSound.allCases) { s in
                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(Color.softText)
                        Text(s.title)
                        Spacer()
                        if settingsStore.value.sound == s {
                            Image(systemName: "checkmark").foregroundStyle(settingsStore.value.theme.accent)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        settingsStore.value.sound = s
                        SoundPlayer.shared.preview(s)
                    }
                }
            }
        } header: {
            Text("الصوت")
        } footer: {
            Text("اضغط على النغمة لتسمعها وتختارها. الصوت يتبع إعدادات جهازك (الصامت ووضع التركيز).")
        }
    }

    // MARK: التأكيدات

    private var confirmSection: some View {
        Section {
            Toggle("قفل الجرعات بعد التأكيد", isOn: $settingsStore.value.lockConfirmed)
            if settingsStore.value.lockConfirmed {
                Toggle("السماح بالتراجع عن التأكيد", isOn: $settingsStore.value.allowUndoConfirm)
            }
            Toggle("اهتزاز عند التأكيد", isOn: $settingsStore.value.haptics)
        } header: {
            Text("التأكيدات")
        } footer: {
            Text("بعد ما تأكّد جرعات وقت معيّن تنقفل علامات الصح فيه، فما تنشال بالغلط. التراجع يحتاج ضغطة مقصودة على زر مخصص.")
        }
    }

    // MARK: الخصوصية

    private var privacySection: some View {
        Section {
            Toggle("قفل التطبيق (Face ID أو رمز الجهاز)", isOn: $settingsStore.value.requireBiometric)
        } header: {
            Text("الخصوصية")
        } footer: {
            Text("يحمي بيانات أدويتك لو أحد فتح جوالك أو آيبادك.")
        }
    }

    // MARK: البيانات

    private var dataSection: some View {
        Section {
            Button {
                showBackup = true
            } label: {
                Label("نسخة احتياطية واستعادة", systemImage: "externaldrive.fill.badge.checkmark")
            }
        } header: {
            Text("البيانات")
        }
    }

    // MARK: عن التطبيق

    private var aboutSection: some View {
        Section {
            NavigationLink {
                DeveloperView()
            } label: {
                Label("صفحة المطور", systemImage: "person.crop.circle.badge.checkmark")
            }
        } header: {
            Text("عن التطبيق")
        }
    }
}

// MARK: - النسخ الاحتياطي

struct BackupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: Store
    @State private var text = ""
    @State private var message: String?
    @State private var askImport = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ShareLink(item: store.exportBackup()) {
                        Label("مشاركة النسخة الاحتياطية", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        UIPasteboard.general.string = store.exportBackup()
                        message = "تم نسخ النسخة الاحتياطية للحافظة ✅"
                    } label: {
                        Label("نسخ للحافظة", systemImage: "doc.on.doc")
                    }
                } header: {
                    Text("تصدير")
                } footer: {
                    Text("تحفظ كل شي: الأدوية والسجل والتأكيدات. احفظها في الملاحظات أو أرسلها لنفسك.")
                }

                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                        .font(.system(.footnote, design: .monospaced))
                    Button("استيراد من النص") { askImport = true }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("استيراد")
                } footer: {
                    Text("الصق نسخة احتياطية سابقة. الاستيراد يستبدل بيانات التطبيق الحالية.")
                }

                if let m = message {
                    Section { Text(m) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ThemedBackground().ignoresSafeArea())
            .navigationTitle("نسخة احتياطية")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
            .confirmationDialog("استبدال البيانات الحالية؟", isPresented: $askImport,
                                titleVisibility: .visible) {
                Button("استيراد", role: .destructive) {
                    if store.importBackup(text) {
                        message = "تم الاستيراد بنجاح ✅"
                        text = ""
                    } else {
                        message = "النص غير صالح، تأكد إنك نسخته كامل."
                    }
                }
                Button("إلغاء", role: .cancel) {}
            }
        }
    }
}

// MARK: - صفحة المطور

struct DeveloperView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: SettingsStore
    @State private var authText = "..."
    @State private var pending: [PendingInfo] = []
    @State private var message: String?

    // غيّر الاسم من هنا
    private let developerName = "أبو ريماس"

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
    }

    private var bundleId: String {
        Bundle.main.bundleIdentifier ?? "-"
    }

    private func reload() async {
        authText = await NotificationManager.shared.authStatusText()
        pending = await NotificationManager.shared.pendingInfo()
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "pills.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Color.white)
                        .frame(width: 76, height: 76)
                        .background(LinearGradient(colors: settings.value.theme.hero,
                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Text("جرعتي").font(.title2.bold())
                    Text("تطوير \(developerName)").foregroundStyle(.secondary)
                    Text("بياناتك محفوظة على جهازك فقط، والتطبيق ما يتصل بأي إنترنت.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("معلومات التطبيق") {
                LabeledContent("الإصدار", value: "\(version) (\(build))")
                LabeledContent("معرّف الحزمة", value: bundleId)
                LabeledContent("الجهاز", value: UIDevice.current.model)
                LabeledContent("نظام iOS", value: UIDevice.current.systemVersion)
                LabeledContent("عدد الأدوية", value: "\(store.meds.count)")
                LabeledContent("جرعات اليوم", value: "\(store.doneToday)/\(store.totalToday)")
            }

            Section {
                LabeledContent("إذن الإشعارات", value: authText)
                LabeledContent("إشعارات مجدولة", value: "\(pending.count)")
                ForEach(pending) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.title).font(.subheadline)
                        if let d = p.next {
                            Text(d.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("حالة الإشعارات")
            } footer: {
                Text("هذي قائمة الإشعارات المجدولة فعلياً في جهازك، مفيدة للتأكد إن التذكيرات شغالة.")
            }

            Section("أدوات") {
                Button {
                    NotificationManager.shared.sendTest()
                    message = "راح يوصلك إشعار تجريبي بعد 5 ثواني ⏱️"
                } label: {
                    Label("إرسال إشعار تجريبي", systemImage: "bell.badge")
                }

                Button {
                    NotificationManager.shared.reschedule(store.meds)
                    store.refreshEndOfDay()
                    message = "تمت إعادة جدولة الإشعارات ✅"
                    Task {
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        await reload()
                    }
                } label: {
                    Label("إعادة جدولة الإشعارات", systemImage: "arrow.triangle.2.circlepath")
                }

                Button {
                    SoundPlayer.shared.preview(settings.value.sound)
                } label: {
                    Label("تجربة النغمة الحالية", systemImage: "speaker.wave.2")
                }

                if let m = message {
                    Text(m).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(ThemedBackground().ignoresSafeArea())
        .navigationTitle("صفحة المطور")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
    }
}
