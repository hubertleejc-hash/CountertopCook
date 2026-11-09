import Foundation
import Observation
import UIKit
import AudioToolbox
import UserNotifications
import CookCore

/// App-wide timers. Lives above Cook Mode, so timers keep running across step changes
/// (and even after leaving Cook Mode).
@Observable
final class TimerStore {
    private(set) var timers: [CookTimer] = []
    /// Ticks several times a second; views read it to redraw countdowns.
    private(set) var now = Date()
    /// Names of timers that just finished, shown as an in-app alert.
    var finishedNames: [String] = []

    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var askedForNotifications = false
    @ObservationIgnored private let notificationsEnabled = !ProcessInfo.processInfo.arguments.contains("-uitesting")

    init() {
        let ticker = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    deinit { ticker?.invalidate() }

    func add(name: String, minutes: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let timer = CookTimer(name: uniqueName(trimmed.isEmpty ? "\(minutes) min" : trimmed),
                              duration: TimeInterval(minutes * 60), start: Date())
        timers.append(timer)
        now = Date()  // the clock is idle while there are no timers, so bring it up to date
        requestNotificationPermissionIfNeeded()
        scheduleNotification(for: timer)
    }

    func togglePause(_ id: UUID) {
        update(id) { timer, now in
            if timer.isPaused { timer.resume(at: now) } else { timer.pause(at: now) }
        }
    }

    func addMinute(_ id: UUID) {
        update(id) { timer, now in timer.addMinute(at: now) }
    }

    func cancel(_ id: UUID) {
        timers.removeAll { $0.id == id }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    func dismissAlert() {
        if !finishedNames.isEmpty { finishedNames.removeFirst() }
    }

    // MARK: Private

    private func uniqueName(_ name: String) -> String {
        guard timers.contains(where: { $0.name == name }) else { return name }
        var n = 2
        while timers.contains(where: { $0.name == "\(name) \(n)" }) { n += 1 }
        return "\(name) \(n)"
    }

    private func update(_ id: UUID, _ change: (inout CookTimer, Date) -> Void) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        let now = Date()
        change(&timers[index], now)
        self.now = now
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        if !timers[index].isPaused { scheduleNotification(for: timers[index]) }
    }

    private func tick() {
        // No timers, nothing to redraw: avoids re-rendering the whole app four times a second.
        guard !timers.isEmpty else { return }
        let now = Date()
        self.now = now
        for index in timers.indices where timers[index].isFinished(at: now) && !timers[index].hasAlerted {
            timers[index].hasAlerted = true
            finishedNames.append(timers[index].name)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            AudioServicesPlayAlertSound(SystemSoundID(1005))
        }
    }

    private func requestNotificationPermissionIfNeeded() {
        guard notificationsEnabled, !askedForNotifications else { return }
        askedForNotifications = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Backup alert for when the app is in the background or the screen is off.
    private func scheduleNotification(for timer: CookTimer) {
        guard notificationsEnabled else { return }
        let remaining = timer.remaining(at: Date())
        guard remaining > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(timer.name) is done"
        content.body = "Your Countertop Cook timer finished."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: timer.id.uuidString, content: content, trigger: trigger))
    }
}
