import AppKit
import OverheadCore
import SwiftUI

@main
enum Launcher {
    static func main() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--check") {
            Diagnostics.check(Array(arguments[(index + 1)...]))
        } else if let index = arguments.firstIndex(of: "--snapshot"), arguments.count > index + 1 {
            Diagnostics.snapshot(to: arguments[index + 1])
        } else {
            OverheadApp.main()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, also when run outside an app bundle.
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            AppModel.shared.start()
            if let index = CommandLine.arguments.firstIndex(of: "--self-test"),
               CommandLine.arguments.count > index + 1 {
                await Diagnostics.selfTest(saveTo: CommandLine.arguments[index + 1])
            }
        }
    }
}

extension AppModel {
    static let shared = AppModel()
}

struct OverheadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            CardView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
