import SwiftUI

// ملاحظة: اسم الملف MedsApp.swift عشان يستبدل ملف التطبيق القديم تلقائياً عند الرفع على GitHub.

@main
struct JoratiApp: App {
    @StateObject private var store = Store.shared

    init() {
        NotificationManager.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
                .tint(Color.brand)
                .task {
                    await NotificationManager.shared.requestAuthorization()
                    NotificationManager.shared.reschedule(store.meds)
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var phase
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("اليوم", systemImage: "checklist") }
            CabinetView()
                .tabItem { Label("الخزانة", systemImage: "pills.fill") }
            HistoryView()
                .tabItem { Label("السجل", systemImage: "chart.bar.fill") }
        }
        .onReceive(tick) { _ in store.refresh() }
        .onChange(of: phase) { p in
            if p == .active { store.refresh() }
        }
    }
}
