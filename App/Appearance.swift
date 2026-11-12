import SwiftUI
import UIKit

/// Light, Dark (Evening Hearth) or System. System follows the phone; Light or Dark locks the
/// app, because a dim kitchen at 7 pm and a bright one at noon don't always match the phone.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var style: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Applies the choice to every window, so sheets, Cook Mode and the UIKit fold views all
    /// follow it. (SwiftUI's preferredColorScheme doesn't reliably return to System.)
    @MainActor static func apply(_ appearance: Appearance) {
        for scene in UIApplication.shared.connectedScenes {
            guard let windows = (scene as? UIWindowScene)?.windows else { continue }
            for window in windows { window.overrideUserInterfaceStyle = appearance.style }
        }
    }

    /// UI tests start from System, or from the appearance named after `-startAppearance`.
    static func prepareForLaunch() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-uitesting") else { return }
        var value = Appearance.system.rawValue
        if let index = arguments.firstIndex(of: "-startAppearance"), index + 1 < arguments.count {
            value = arguments[index + 1]
        }
        UserDefaults.standard.set(value, forKey: storageKey)
    }
}

/// The Light / Dark / System switch, as a small menu in the library.
struct AppearanceMenu: View {
    @AppStorage(Appearance.storageKey) private var stored = Appearance.system.rawValue

    private var current: Appearance { Appearance(rawValue: stored) ?? .system }

    var body: some View {
        Menu {
            ForEach(Appearance.allCases) { option in
                Button {
                    stored = option.rawValue
                } label: {
                    Label(option.title, systemImage: option == current ? "checkmark" : option.symbol)
                }
                .accessibilityIdentifier("appearance_\(option.rawValue)")
            }
        } label: {
            Image(systemName: current.symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.navy)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Appearance")
        .accessibilityValue(current.title)
        .accessibilityIdentifier("appearanceMenu")
    }
}
