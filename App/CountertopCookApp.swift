import SwiftUI
import SwiftData
import UserNotifications

@main
struct CountertopCookApp: App {
    @State private var timers = TimerStore()
    private let container: ModelContainer

    init() {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-uitesting")
        // On-device only: no CloudKit in v1. UI tests get a fresh in-memory store every launch.
        let config = ModelConfiguration(isStoredInMemoryOnly: isUITesting, cloudKitDatabase: .none)
        do {
            container = try ModelContainer(for: Recipe.self, Ingredient.self, RecipeStep.self, configurations: config)
        } catch {
            fatalError("Could not open the recipe store: \(error)")
        }
        SeedData.seedIfNeeded(container.mainContext, force: isUITesting)
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RecipeListView()
                .environment(timers)
        }
        .modelContainer(container)
    }
}

/// Shows timer-done notifications as banners with sound even while the app is open.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
