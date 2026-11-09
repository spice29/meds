import SwiftUI

@main
struct MedsApp: App {
    @StateObject private var store = Store.shared

    init() {
        NotificationManager.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
                .task {
                    await NotificationManager.shared.requestAuthorization()
                    NotificationManager.shared.reschedule(store.meds)
                }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("اليوم", systemImage: "checklist") }
            MedsListView()
                .tabItem { Label("أدويتي", systemImage: "pills") }
        }
    }
}
