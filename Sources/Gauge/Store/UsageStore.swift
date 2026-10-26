import Foundation
import Combine
import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published var antigravity = ProviderState()
    @Published var copilot = ProviderState()
    @Published var copilotReport: CopilotReport?
    @Published var history: [HistoryPoint] = []
    @Published var cliStats = CLIStats()
    @Published var isLoadingCLI = false
    @Published var cliMetric = "Requests"
    @Published var cliModelSort = "Time"
    @Published var tokenRevision = 0

    // UI Navigation & settings states kept in store
    @Published var sidebarSelection: SidebarItem = .overview
    @Published var historyRange: Int = 1
    @Published var copilotInputToken: String = ""
    @Published var isEditingToken: Bool = false
    @Published var launchAtLogin: Bool = false
    @Published var loginError: String?

    private var loopTask: Task<Void, Never>?
    private let historyURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gauge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    init() {
        loadHistory()
    }

    var allBuckets: [QuotaBucket] { antigravity.buckets + copilot.buckets }

    var isRefreshing: Bool { antigravity.isLoading || copilot.isLoading }

    var lastUpdated: Date? {
        [antigravity.lastUpdated, copilot.lastUpdated].compactMap { $0 }.max()
    }

    var hasGitHubToken: Bool {
        _ = tokenRevision
        return !(Keychain.read(Keychain.githubToken) ?? "").isEmpty
    }

    func state(for provider: Provider) -> ProviderState {
        provider == .antigravity ? antigravity : copilot
    }

    func isEnabled(_ provider: Provider) -> Bool {
        let key = provider == .antigravity ? Prefs.antigravityEnabled : Prefs.copilotEnabled
        return UserDefaults.standard.bool(forKey: key)
    }

    var featuredBucket: QuotaBucket? {
        let pinned = UserDefaults.standard.string(forKey: Prefs.pinnedBucket) ?? "auto"
        if pinned != "auto", let b = allBuckets.first(where: { $0.id == pinned }) { return b }
        return allBuckets.min { $0.remaining < $1.remaining }
    }

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAll()
                let minutes = max(1, UserDefaults.standard.integer(forKey: Prefs.refreshMinutes))
                try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            }
        }
    }

    func restartLoop() {
        loopTask?.cancel()
        loopTask = nil
        start()
    }

    func refreshAll() async {
        async let a: Void = refreshAntigravity()
        async let c: Void = refreshCopilot()
        _ = await (a, c)
        recordHistory()
        Notifier.shared.evaluate(allBuckets)
    }

    func refreshAntigravity() async {
        guard isEnabled(.antigravity) else {
            antigravity = ProviderState()
            return
        }
        antigravity.isLoading = true
        defer { antigravity.isLoading = false }
        do {
            let result = try await AntigravityService.fetch()
            antigravity.buckets = result.buckets
            antigravity.summary = result.summary
            antigravity.error = nil
            antigravity.lastUpdated = .now
        } catch {
            antigravity.error = error.localizedDescription
        }
    }

    func refreshCopilot() async {
        guard isEnabled(.copilot) else {
            copilot = ProviderState()
            copilotReport = nil
            return
        }
        copilot.isLoading = true
        defer { copilot.isLoading = false }
        await refreshCLIStats()
        let allowance = UserDefaults.standard.double(forKey: Prefs.copilotAllowance)
        let allow = allowance > 0 ? allowance : 300
        do {
            let report = try await CopilotService.fetch(allowance: allow)
            copilotReport = report
            copilot.buckets = CopilotService.buckets(from: report)
            copilot.error = nil
            copilot.lastUpdated = .now
        } catch {
            if let local = CopilotService.localReport(from: cliStats, allowance: allow) {
                copilotReport = local
                copilot.buckets = CopilotService.buckets(from: local)
                copilot.lastUpdated = .now
                copilot.error = "Showing local Copilot CLI estimate. " + error.localizedDescription
            } else {
                copilot.error = error.localizedDescription
                copilot.buckets = []
                copilotReport = nil
            }
        }
    }

    func refreshCLIStats() async {
        guard UserDefaults.standard.bool(forKey: Prefs.cliStatsEnabled) else {
            cliStats = CLIStats()
            return
        }
        isLoadingCLI = true
        defer { isLoadingCLI = false }
        let dir = CopilotCLIService.directory()
        cliStats = await Task.detached(priority: .utility) { CopilotCLIService.load(from: dir) }.value
    }

    func setGitHubToken(_ token: String) {
        Keychain.save(token.trimmingCharacters(in: .whitespacesAndNewlines), for: Keychain.githubToken)
        tokenRevision += 1
        Task { await refreshCopilot(); recordHistory() }
    }

    func points(for bucketID: String, since: Date) -> [HistoryPoint] {
        history.filter { $0.bucketID == bucketID && $0.date >= since }
    }

    private func recordHistory() {
        let now = Date()
        for b in allBuckets {
            if let last = history.last(where: { $0.bucketID == b.id }), now.timeIntervalSince(last.date) < 240 {
                continue
            }
            history.append(HistoryPoint(date: now, bucketID: b.id, label: b.title, provider: b.provider, remaining: b.remaining))
        }
        let days = max(1, UserDefaults.standard.integer(forKey: Prefs.historyDays))
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        history.removeAll { $0.date < cutoff }
        saveHistory()
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        history = (try? dec.decode([HistoryPoint].self, from: data)) ?? []
    }

    private func saveHistory() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(history) { try? data.write(to: historyURL, options: .atomic) }
    }
}
