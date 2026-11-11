import UserNotifications

struct PendingInfo: Identifiable {
    let id: String
    let title: String
    let next: Date?
}

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    static let doseCategory = "DOSE"
    static let eodCategory = "EOD"
    static let takenAction = "TAKEN"
    static let snoozeAction = "SNOOZE"
    static let confirmDayAction = "CONFIRM_DAY"

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let taken = UNNotificationAction(identifier: Self.takenAction,
                                         title: "أخذتها ✅", options: [])
        let snooze = UNNotificationAction(identifier: Self.snoozeAction,
                                          title: "ذكّرني لاحقاً ⏰", options: [])
        let dose = UNNotificationCategory(identifier: Self.doseCategory,
                                          actions: [taken, snooze],
                                          intentIdentifiers: [], options: [])

        let confirm = UNNotificationAction(identifier: Self.confirmDayAction,
                                           title: "تأكيد اليوم ✅", options: [.foreground])
        let eod = UNNotificationCategory(identifier: Self.eodCategory,
                                         actions: [confirm],
                                         intentIdentifiers: [], options: [])
        center.setNotificationCategories([dose, eod])
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

    func authStatusText() async -> String {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        switch s.authorizationStatus {
        case .authorized: return "مسموح"
        case .provisional: return "مسموح (هادئ)"
        case .denied: return "مرفوض"
        case .notDetermined: return "لم يُطلب بعد"
        default: return "غير معروف"
        }
    }

    private func sound(for s: AppSettings) -> UNNotificationSound? {
        guard s.soundEnabled else { return nil }
        if let name = s.sound.fileName {
            return UNNotificationSound(named: UNNotificationSoundName(name))
        }
        return .default
    }

    private func line(for m: Medication) -> String {
        var s = "• \(m.name): \(m.doseText)"
        if m.meal != .unspecified { s += " · \(m.meal.title)" }
        return s
    }

    // MARK: - تذكيرات الجرعات (يومية متكررة)

    func reschedule(_ meds: [Medication]) {
        let s = AppSettings.load()
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
            guard s.remindersEnabled else { return }

            for (time, items) in snapshot {
                let content = UNMutableNotificationContent()
                content.title = "حان وقت جرعتك (\(time.label))"
                content.body = items.map { self.line(for: $0) }.joined(separator: "\n")
                content.sound = self.sound(for: s)
                content.categoryIdentifier = Self.doseCategory
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

    // MARK: - تذكير تأكيد نهاية اليوم (14 يوم قدّام، ويُلغى اليوم لو تأكد)

    func scheduleEndOfDay(todayDone: Bool) {
        let s = AppSettings.load()
        let center = UNUserNotificationCenter.current()

        center.getPendingNotificationRequests { [weak self] pending in
            guard let self = self else { return }
            let old = pending.map { $0.identifier }.filter { $0.hasPrefix("eod-") }
            center.removePendingNotificationRequests(withIdentifiers: old)
            guard s.endOfDayReminder else { return }

            let cal = Calendar.current
            let now = Date()
            for offset in 0..<14 {
                if offset == 0 && todayDone { continue }
                guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
                var comps = cal.dateComponents([.year, .month, .day], from: day)
                comps.hour = s.endOfDayHour
                comps.minute = s.endOfDayMinute
                guard let fire = cal.date(from: comps), fire > now else { continue }

                let content = UNMutableNotificationContent()
                content.title = "تأكيد جرعات اليوم"
                content.body = "راجع أدويتك وأكّد إتمام جرعات اليوم عشان ينحفظ في السجل."
                content.sound = self.sound(for: s)
                content.categoryIdentifier = Self.eodCategory

                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let id = "eod-\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
                center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }
    }

    // MARK: - إشعارات أخرى

    func notifyLowStock(_ med: Medication) {
        let s = AppSettings.load()
        guard s.lowStockAlerts else { return }
        let content = UNMutableNotificationContent()
        content.title = "مخزون \(med.name) قارب على الانتهاء"
        var body = "المتبقي: \(med.stockText)"
        if let d = med.daysLeft { body += " (يكفي حوالي \(d) يوم)" }
        content.body = body
        content.sound = sound(for: s)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "low-\(med.id.uuidString)",
                                  content: content, trigger: trigger))
    }

    func sendTest() {
        let s = AppSettings.load()
        let content = UNMutableNotificationContent()
        content.title = "إشعار تجريبي من جرعتي"
        content.body = "إذا وصلك هذا الإشعار فكل شي شغال ✅"
        content.sound = sound(for: s)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "test-\(Int(Date().timeIntervalSince1970))",
                                  content: content, trigger: trigger))
    }

    func pendingInfo() async -> [PendingInfo] {
        let reqs = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let list = reqs.map { r -> PendingInfo in
            var next: Date?
            if let t = r.trigger as? UNCalendarNotificationTrigger {
                next = t.nextTriggerDate()
            } else if let t = r.trigger as? UNTimeIntervalNotificationTrigger {
                next = t.nextTriggerDate()
            }
            return PendingInfo(id: r.identifier, title: r.content.title, next: next)
        }
        return list.sorted { ($0.next ?? Date.distantFuture) < ($1.next ?? Date.distantFuture) }
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

        switch response.actionIdentifier {
        case Self.takenAction:
            guard let timeId = original.userInfo["time"] as? Int else { return }
            await MainActor.run { Store.shared.markDosesTaken(timeId: timeId) }

        case Self.snoozeAction:
            guard let timeId = original.userInfo["time"] as? Int,
                  let content = original.mutableCopy() as? UNMutableNotificationContent else { return }
            let minutes = max(1, AppSettings.load().snoozeMinutes)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(minutes) * 60, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "snooze-\(timeId)",
                                                        content: content, trigger: trigger))

        case Self.confirmDayAction:
            await MainActor.run { Store.shared.confirmDayIfComplete() }

        default:
            break
        }
    }
}
