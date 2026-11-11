import SwiftUI
import LocalAuthentication

// ملاحظة: اسم الملف MedsApp.swift عشان يستبدل ملف التطبيق القديم تلقائياً عند الرفع على GitHub.

@main
struct JoratiApp: App {
    @StateObject private var store = Store.shared
    @StateObject private var settings = SettingsStore.shared

    init() {
        SoundLibrary.installAll()
        NotificationManager.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(settings)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.accent, settings.value.theme.accent)
                .tint(settings.value.theme.accent)
                .preferredColorScheme(settings.value.appearance.scheme)
                .task {
                    await NotificationManager.shared.requestAuthorization()
                    NotificationManager.shared.reschedule(store.meds)
                    store.refreshEndOfDay()
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.scenePhase) private var phase
    @State private var locked: Bool
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init() {
        _locked = State(initialValue: AppSettings.load().requireBiometric)
    }

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("اليوم", systemImage: "checklist") }
            CabinetView()
                .tabItem { Label("الخزانة", systemImage: "pills.fill") }
            HistoryView()
                .tabItem { Label("السجل", systemImage: "chart.bar.fill") }
            SettingsView()
                .tabItem { Label("الإعدادات", systemImage: "gearshape.fill") }
        }
        .overlay {
            if locked {
                LockView(unlock: authenticate)
            }
        }
        .onAppear {
            if locked { authenticate() }
        }
        .onReceive(tick) { _ in store.refresh() }
        .onChange(of: phase) { p in
            if p == .active {
                store.appBecameActive()
                if locked { authenticate() }
            } else if p == .background && settings.value.requireBiometric {
                locked = true
            }
        }
    }

    private func authenticate() {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            locked = false
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication,
                           localizedReason: "افتح جرعتي لعرض أدويتك") { ok, _ in
            DispatchQueue.main.async {
                if ok { locked = false }
            }
        }
    }
}

struct LockView: View {
    let unlock: () -> Void

    var body: some View {
        ZStack {
            ThemedBackground().ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill").font(.system(size: 44))
                Text("جرعتي مقفل").font(.title2.bold())
                Button("فتح") { unlock() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
