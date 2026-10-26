import ServiceManagement
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            AccountsSettings()
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
            CLISettings()
                .tabItem { Label("Copilot CLI", systemImage: "terminal") }
            NotificationSettings()
                .tabItem { Label("Notifications", systemImage: "bell.badge") }
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @EnvironmentObject private var store: UsageStore
    @AppStorage(Prefs.refreshMinutes) private var refreshMinutes = 5
    @AppStorage(Prefs.showInDock) private var showInDock = true
    @AppStorage(Prefs.menuBarStyle) private var menuBarStyle = MenuBarStyle.iconAndPercent.rawValue
    @AppStorage(Prefs.pinnedBucket) private var pinned = "auto"
    @AppStorage(Prefs.appearance) private var appearance = "system"
    @AppStorage(Prefs.showBadges) private var showBadges = true
    @AppStorage(Prefs.historyDays) private var historyDays = 30
    @AppStorage(Prefs.statsRangeDays) private var statsRangeDays = 30

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            store.launchAtLogin = on
                            store.loginError = nil
                        } catch {
                            store.loginError = error.localizedDescription
                            store.launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                ))
                if let err = store.loginError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                Toggle("Show icon in Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { _, on in AppDelegate.applyDockPolicy(on) }
            }

            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                Toggle("Show percent badges in sidebar", isOn: $showBadges)
            }

            Section("Data") {
                Picker("Keep quota history", selection: $historyDays) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("1 year").tag(365)
                }
                Picker("Default stats range", selection: $statsRangeDays) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("All time").tag(0)
                }
            }

            Section("Menu bar") {
                Picker("Display", selection: $menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("Featured limit", selection: $pinned) {
                    Text("Automatic (lowest remaining)").tag("auto")
                    if !store.allBuckets.isEmpty { Divider() }
                    ForEach(store.allBuckets) { b in
                        Text("\(b.provider.shortName) · \(b.title)").tag(b.id)
                    }
                }
            }

            Section("Refresh") {
                Picker("Check every", selection: $refreshMinutes) {
                    Text("1 minute").tag(1)
                    Text("2 minutes").tag(2)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                }
                .onChange(of: refreshMinutes) { _, _ in store.restartLoop() }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            store.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Accounts

private struct AccountsSettings: View {
    @EnvironmentObject private var store: UsageStore
    @AppStorage(Prefs.antigravityEnabled) private var agEnabled = true
    @AppStorage(Prefs.copilotEnabled) private var cpEnabled = true
    @AppStorage(Prefs.agyPath) private var agyPath = ""
    @AppStorage(Prefs.copilotAllowance) private var allowance = 300.0

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $agEnabled) {
                    HStack(spacing: 10) {
                        ProviderBadge(provider: .antigravity, size: 22)
                        VStack(alignment: .leading) {
                            Text("Antigravity")
                            Text("Uses `agy /quota` from your signed-in Antigravity CLI")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onChange(of: agEnabled) { _, _ in Task { await store.refreshAll() } }
                if agEnabled {
                    LabeledContent("CLI") {
                        if let found = AntigravityService.locateCLI() {
                            Text(found).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        } else {
                            Text("Not found").foregroundStyle(.red)
                        }
                    }
                    TextField("Custom agy path", text: $agyPath, prompt: Text("Auto-detect"))
                }
            }

            Section {
                Toggle(isOn: $cpEnabled) {
                    HStack(spacing: 10) {
                        ProviderBadge(provider: .copilot, size: 22)
                        VStack(alignment: .leading) {
                            Text("GitHub Copilot")
                            Text("Uses GitHub's billing API for premium request usage")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onChange(of: cpEnabled) { _, _ in Task { await store.refreshAll() } }

                if cpEnabled {
                    if store.hasGitHubToken && !store.isEditingToken {
                        LabeledContent("Token") {
                            HStack {
                                Label(store.copilotReport.map { "Connected as @\($0.login)" } ?? "Saved in Keychain",
                                      systemImage: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                Button("Change") { store.isEditingToken = true }
                                Button("Remove", role: .destructive) { store.setGitHubToken("") }
                            }
                        }
                    } else {
                        SecureField("Personal access token", text: Binding(
                            get: { store.copilotInputToken },
                            set: { store.copilotInputToken = $0 }
                        ), prompt: Text("github_pat_…"))
                        HStack {
                            Link("Create a fine-grained token ↗",
                                 destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
                                .font(.caption)
                            Spacer()
                            if store.isEditingToken {
                                Button("Cancel") {
                                    store.isEditingToken = false
                                    store.copilotInputToken = ""
                                }
                            }
                            Button("Save") {
                                store.setGitHubToken(store.copilotInputToken)
                                store.copilotInputToken = ""
                                store.isEditingToken = false
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.copilotInputToken.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        Text("Under **Account permissions**, set **Plan** to *Read-only*. The token is stored in your macOS Keychain.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Monthly allowance", selection: $allowance) {
                        Text("Copilot Free · 50").tag(50.0)
                        Text("Copilot Pro / Business · 300").tag(300.0)
                        Text("Copilot Enterprise · 1000").tag(1000.0)
                        Text("Copilot Pro+ · 1500").tag(1500.0)
                    }
                    .onChange(of: allowance) { _, _ in Task { await store.refreshCopilot() } }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Copilot CLI

private struct CLISettings: View {
    @EnvironmentObject private var store: UsageStore
    @AppStorage(Prefs.cliStatsEnabled) private var enabled = true
    @AppStorage(Prefs.copilotCLIDir) private var dir = ""
    @AppStorage(Prefs.useGhToken) private var useGh = true

    var body: some View {
        Form {
            Section {
                Toggle("Track Copilot CLI sessions locally", isOn: $enabled)
                    .onChange(of: enabled) { _, _ in Task { await store.refreshCLIStats() } }
                Text("Per-model time, tokens and requests are read from ~/.copilot/session-state. Nothing leaves your Mac; prompts and responses are never read.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if enabled {
                Section("Session folder") {
                    TextField("Folder", text: $dir, prompt: Text("~/.copilot/session-state"))
                        .onSubmit { Task { await store.refreshCLIStats() } }
                    LabeledContent("Sessions found") {
                        Text("\(store.cliStats.sessions.count)").monospacedDigit()
                    }
                    HStack {
                        Spacer()
                        Button("Rescan Now") { Task { await store.refreshCLIStats() } }
                    }
                }
            }
            Section("GitHub billing") {
                Toggle("Use token from `gh` CLI when no token is saved", isOn: $useGh)
                    .onChange(of: useGh) { _, _ in Task { await store.refreshCopilot() } }
                Text("Needs the `user` scope: run `gh auth refresh -h github.com -s user`. Without billing access Gauge falls back to local CLI usage.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Notifications

private struct NotificationSettings: View {
    @AppStorage(Prefs.notificationsEnabled) private var enabled = true
    @AppStorage(Prefs.notify50) private var n50 = false
    @AppStorage(Prefs.notify25) private var n25 = true
    @AppStorage(Prefs.notify10) private var n10 = true
    @AppStorage(Prefs.notifyEmpty) private var nEmpty = true
    @AppStorage(Prefs.notifyReset) private var nReset = true

    var body: some View {
        Form {
            Section {
                Toggle("Enable notifications", isOn: $enabled)
                    .onChange(of: enabled) { _, on in
                        if on { Task { _ = await Notifier.shared.requestAuthorization() } }
                    }
            }

            Section("Alert me when a limit drops below") {
                Toggle("50% remaining", isOn: $n50)
                Toggle("25% remaining", isOn: $n25)
                Toggle("10% remaining", isOn: $n10)
                Toggle("Fully used", isOn: $nEmpty)
            }
            .disabled(!enabled)

            Section {
                Toggle("When a limit refreshes", isOn: $nReset)
                HStack {
                    Spacer()
                    Button("Send Test Notification") { Notifier.shared.sendTest() }
                }
            }
            .disabled(!enabled)
        }
        .formStyle(.grouped)
    }
}
