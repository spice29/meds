import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    static let category = "DOSE"
    static let takenAction = "TAKEN"
    static let snoozeAction = "SNOOZE"

    /// يُستدعى مرة وحدة عند تشغيل التطبيق
    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let taken = UNNotificationAction(identifier: Self.takenAction,
                                         title: "أخذتها ✅", options: [])
        let snooze = UNNotificationAction(identifier: Self.snoozeAction,
                                          title: "ذكّرني بعد 15 دقيقة", options: [])
        let cat = UNNotificationCategory(identifier: Self.category,
                                         actions: [taken, snooze],
                                         intentIdentifiers: [], options: [])
        center.setNotificationCategories([cat])
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func isAuthorized() async -> Bool {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        return s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    /// إشعار واحد متكرر يومياً لكل وقت (٨ ص، ٢ م، ٨ م) يجمع أدوية ذاك الوقت
    func reschedule(_ meds: [Medication]) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(
            withIdentifiers: Slot.allCases.map { "slot-\($0.rawValue)" })

        for slot in Slot.allCases {
            let items = meds.filter { $0.slots.contains(slot) }
            guard !items.isEmpty else { continue }

            let content = UNMutableNotificationContent()
            content.title = "وقت أدوية \(slot.title) (\(slot.timeLabel))"
            content.body = items.map { "• \($0.name): \($0.qtyText)" }.joined(separator: "\n")
            content.sound = .default
            content.categoryIdentifier = Self.category
            content.userInfo = ["slot": slot.rawValue]
            // content.interruptionLevel = .timeSensitive  // يحتاج تفعيل Time Sensitive Notifications في Capabilities

            var comps = DateComponents()
            comps.hour = slot.hour
            comps.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            center.add(UNNotificationRequest(identifier: "slot-\(slot.rawValue)",
                                             content: content, trigger: trigger))
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// يظهر الإشعار حتى لو التطبيق مفتوح
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let original = response.notification.request.content
        guard let raw = original.userInfo["slot"] as? String,
              let slot = Slot(rawValue: raw) else { return }

        switch response.actionIdentifier {
        case Self.takenAction:
            await MainActor.run { Store.shared.markSlotTaken(slot) }

        case Self.snoozeAction:
            guard let content = original.mutableCopy() as? UNMutableNotificationContent else { return }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "snooze-\(slot.rawValue)",
                                                        content: content, trigger: trigger))
        default:
            break
        }
    }
}
