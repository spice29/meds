import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    static let category = "DOSE"
    static let takenAction = "TAKEN"
    static let snoozeAction = "SNOOZE"

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

    private func line(for m: Medication) -> String {
        var s = "• \(m.name): \(m.doseText)"
        if m.meal != .unspecified { s += " · \(m.meal.title)" }
        return s
    }

    /// إشعار يومي متكرر لكل وقت، يجمع أدوية ذاك الوقت
    func reschedule(_ meds: [Medication]) {
        var groups: [DoseTime: [Medication]] = [:]
        for m in meds {
            for t in m.times { groups[t, default: []].append(m) }
        }
        let snapshot = groups
        let center = UNUserNotificationCenter.current()

        center.getPendingNotificationRequests { [weak self] pending in
            guard let self = self else { return }
            let old = pending.map { $0.identifier }.filter { $0.hasPrefix("dose-") }
            center.removePendingNotificationRequests(withIdentifiers: old)

            for (time, items) in snapshot {
                let content = UNMutableNotificationContent()
                content.title = "حان وقت جرعتك (\(time.label))"
                content.body = items.map { self.line(for: $0) }.joined(separator: "\n")
                content.sound = .default
                content.categoryIdentifier = Self.category
                content.userInfo = ["time": time.id]
                // content.interruptionLevel = .timeSensitive  // يحتاج Capability: Time Sensitive Notifications

                var comps = DateComponents()
                comps.hour = time.hour
                comps.minute = time.minute
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                center.add(UNNotificationRequest(identifier: "dose-\(time.id)",
                                                 content: content, trigger: trigger))
            }
        }
    }

    /// تنبيه نقص المخزون (فوري)
    func notifyLowStock(_ med: Medication) {
        let content = UNMutableNotificationContent()
        content.title = "مخزون \(med.name) قارب على الانتهاء"
        var body = "المتبقي: \(med.stockText)"
        if let d = med.daysLeft { body += " (يكفي حوالي \(d) يوم)" }
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "low-\(med.id.uuidString)",
                                  content: content, trigger: trigger))
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let original = response.notification.request.content
        guard let timeId = original.userInfo["time"] as? Int else { return }

        switch response.actionIdentifier {
        case Self.takenAction:
            await MainActor.run { Store.shared.markDosesTaken(timeId: timeId) }

        case Self.snoozeAction:
            guard let content = original.mutableCopy() as? UNMutableNotificationContent else { return }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "snooze-\(timeId)",
                                                        content: content, trigger: trigger))
        default:
            break
        }
    }
}
