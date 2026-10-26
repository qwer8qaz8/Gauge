import AppKit
import SwiftUI

@main
struct GaugeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var store = UsageStore.shared
    @AppStorage(Prefs.appearance) private var appearance = "system"

    private var scheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    init() {
        Prefs.register()
    }

    var body: some Scene {
        Window("Gauge", id: "main") {
            DashboardView()
                .environmentObject(store)
                .preferredColorScheme(scheme)
        }
        .defaultSize(width: 1000, height: 700)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Refresh Now") { Task { await store.refreshAll() } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
                .preferredColorScheme(scheme)
        } label: {
            MenuBarLabel()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
                .preferredColorScheme(scheme)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.applyDockPolicy(UserDefaults.standard.bool(forKey: Prefs.showInDock))
        Task { @MainActor in
            Notifier.shared.setUp()
            if UserDefaults.standard.bool(forKey: Prefs.notificationsEnabled) {
                _ = await Notifier.shared.requestAuthorization()
            }
            UsageStore.shared.start()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where window.identifier?.rawValue == "main" || window.title == "Gauge" {
                window.makeKeyAndOrderFront(nil)
                return false
            }
        }
        return true
    }

    static func applyDockPolicy(_ showInDock: Bool) {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        if showInDock { NSApp.activate(ignoringOtherApps: true) }
    }
}
