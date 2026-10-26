import Charts
import SwiftUI

enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
    case antigravity, overview, copilot, cli, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .antigravity: "Antigravity"
        case .copilot: "GitHub Copilot"
        case .cli: "Copilot CLI Stats"
        case .history: "History"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .antigravity: Provider.antigravity.symbol
        case .copilot: Provider.copilot.symbol
        case .cli: "terminal"
        case .history: "chart.xyaxis.line"
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var store: UsageStore
    @AppStorage(Prefs.showBadges) private var showBadges = true

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(SidebarItem.allCases) { item in
                        let selected = store.sidebarSelection == item
                        Button {
                            store.sidebarSelection = item
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.symbol).frame(width: 20)
                                Text(item.title)
                                Spacer()
                                if showBadges, let b = badge(for: item) {
                                    b.font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(selected ? Color.accentColor.opacity(0.22) : Color.clear)
                            )
                            .foregroundStyle(selected ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
            }
            sidebarFooter
            }
            .frame(width: 220)
            .background(.regularMaterial)
            Divider()
            ZStack {
                AmbientBackground()
                ScrollView {
                    Group {
                        switch store.sidebarSelection {
                        case .overview: OverviewPage()
                        case .antigravity: ProviderPage(provider: .antigravity)
                        case .copilot: ProviderPage(provider: .copilot)
                        case .cli: CLIStatsPage()
                        case .history: HistoryPage()
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 980)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(store.sidebarSelection.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await store.refreshAll() }
                    } label: {
                        if store.isRefreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Refresh now (⌘R)")
                }
            }
        }
        .frame(minWidth: 860, minHeight: 560)
    }

    private func badge(for item: SidebarItem) -> Text? {
        let provider: Provider
        switch item {
        case .antigravity: provider = .antigravity
        case .copilot: provider = .copilot
        default: return nil
        }
        guard let t = store.state(for: provider).tightest else { return nil }
        return Text(Format.percent(t.remaining))
    }

    private var sidebarFooter: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            HStack(spacing: 6) {
                Circle()
                    .fill(store.isRefreshing ? Color.orange : Color.green)
                    .frame(width: 7, height: 7)
                if let last = store.lastUpdated {
                    Text("Updated \(last.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))")
                } else {
                    Text(store.isRefreshing ? "Refreshing…" : "Not updated yet")
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(12)
            .id(ctx.date)
        }
    }
}

// MARK: - Overview

struct OverviewPage: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 16) {
                HeroCard(provider: .antigravity)
                HeroCard(provider: .copilot)
                    .scaleEffect(0.98)
                    .opacity(0.92)
            }

            ForEach(Provider.allCases) { provider in
                let state = store.state(for: provider)
                if !state.buckets.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(provider: provider)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                            ForEach(state.buckets) { BucketCard(bucket: $0) }
                        }
                    }
                }
            }

            if !store.history.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Last 24 hours").font(.title3.weight(.semibold))
                    Card { HistoryChart(since: .now.addingTimeInterval(-86_400)).frame(height: 220) }
                }
            }
        }
    }
}

struct SectionHeader: View {
    var provider: Provider

    var body: some View {
        HStack(spacing: 10) {
            ProviderBadge(provider: provider, size: 24)
            Text(provider.displayName).font(.title3.weight(.semibold))
        }
    }
}

struct HeroCard: View {
    @EnvironmentObject private var store: UsageStore
    @Environment(\.openSettings) private var openSettings
    var provider: Provider

    var body: some View {
        let state = store.state(for: provider)
        Card(padding: 20) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ProviderBadge(provider: provider, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(provider.displayName).font(.headline)
                            Text(subtitle(state)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if let t = state.tightest {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tightest limit").font(.caption).foregroundStyle(.secondary)
                            Text(t.title).font(.callout.weight(.medium)).lineLimit(1)
                            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                                Text("Resets in \(Format.countdown(to: t.resetTime, now: ctx.date))")
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    } else if let error = state.error {
                        Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        if provider == .copilot && !store.hasGitHubToken {
                            Button("Connect GitHub…") { openSettings() }
                                .controlSize(.small)
                        }
                    } else if state.isLoading {
                        ProgressView().controlSize(.small)
                    } else if !store.isEnabled(provider) {
                        Text("Disabled in Settings").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                let value = state.tightest?.remaining ?? 0
                RingGauge(progress: value, colors: state.tightest == nil ? [.gray.opacity(0.3)] : provider.colors, lineWidth: 13) {
                    VStack(spacing: 0) {
                        Text(state.tightest.map { Format.percent($0.remaining) } ?? "—")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("available").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 124, height: 124)
            }
            .frame(minHeight: 124)
        }
        .overlay(alignment: .topTrailing) {
            if state.isLoading {
                ProgressView().controlSize(.mini).padding(10)
            }
        }
    }

    private func subtitle(_ state: ProviderState) -> String {
        switch provider {
        case .antigravity:
            let groups = Set(state.buckets.map(\.group)).count
            return groups > 0 ? "\(groups) model groups" : "Gemini, Claude & GPT"
        case .copilot:
            if let r = store.copilotReport { return "@\(r.login)" }
            return "Premium requests"
        }
    }
}

// MARK: - Provider detail page

struct ProviderPage: View {
    @EnvironmentObject private var store: UsageStore
    @Environment(\.openSettings) private var openSettings
    var provider: Provider

    var body: some View {
        let state = store.state(for: provider)
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                ProviderBadge(provider: provider, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName).font(.largeTitle.weight(.bold))
                    if let last = state.lastUpdated {
                        Text("Updated \(last.formatted(date: .omitted, time: .shortened))")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    Task {
                        if provider == .antigravity { await store.refreshAntigravity() } else { await store.refreshCopilot() }
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(state.isLoading)
            }

            if let error = state.error {
                ProviderMessage(
                    provider: provider,
                    message: error,
                    actionTitle: "Open Settings",
                    action: { openSettings() }
                )
            }

            if let note = state.note, state.error == nil {
                Label(note, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let summary = state.summary {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if provider == .copilot, let report = store.copilotReport {
                CopilotDetail(report: report)
            }

            let groups = Dictionary(grouping: state.buckets, by: \.group)
            let order = state.buckets.map(\.group).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            ForEach(order, id: \.self) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(group).font(.title3.weight(.semibold))
                    if let detail = groups[group]?.first?.groupDetail {
                        Text(detail).font(.callout).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                        ForEach(groups[group] ?? []) { BucketCard(bucket: $0) }
                    }
                }
            }

            if !state.buckets.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Trend · 7 days").font(.title3.weight(.semibold))
                    Card { HistoryChart(since: .now.addingTimeInterval(-7 * 86_400), provider: provider).frame(height: 240) }
                }
            }
        }
    }
}

struct CopilotDetail: View {
    var report: CopilotReport

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            StatTile(title: "Used this month", value: Format.number(report.used), unit: report.unit, symbol: "sum")
            StatTile(title: "Today", value: report.today.map(Format.number) ?? "—", unit: report.unit, symbol: "sun.max")
            StatTile(title: "Remaining", value: Format.number(max(0, report.allowance - report.used)), unit: "of \(Format.number(report.allowance))", symbol: "battery.75percent")
            StatTile(title: "Overage cost", value: Format.currency(report.overageCost), unit: "this month", symbol: "dollarsign.circle")
        }

        if !report.models.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("By model").font(.headline)
                    Chart(report.models.prefix(8)) { m in
                        BarMark(x: .value("Requests", m.quantity), y: .value("Model", m.model))
                            .foregroundStyle(Provider.copilot.gradient)
                            .cornerRadius(5)
                            .annotation(position: .trailing) {
                                Text(Format.number(m.quantity)).font(.caption).foregroundStyle(.secondary)
                            }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: CGFloat(min(report.models.count, 8)) * 32 + 10)
                }
            }
        }
    }
}

struct StatTile: View {
    var title: String
    var value: String
    var unit: String
    var symbol: String

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - History

struct HistoryPage: View {
    @EnvironmentObject private var store: UsageStore

    private var since: Date {
        switch store.historyRange {
        case 0: .now.addingTimeInterval(-86_400)
        case 1: .now.addingTimeInterval(-7 * 86_400)
        default: .now.addingTimeInterval(-30 * 86_400)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Remaining quota over time").font(.title2.weight(.semibold))
                Spacer()
                Picker("Range", selection: Binding(
                    get: { store.historyRange },
                    set: { store.historyRange = $0 }
                )) {
                    Text("24h").tag(0)
                    Text("7d").tag(1)
                    Text("30d").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .labelsHidden()
            }
            ForEach(Provider.allCases) { provider in
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(provider: provider)
                    Card { HistoryChart(since: since, provider: provider).frame(height: 230) }
                }
            }
            Text("Gauge samples your quotas each refresh while it's running. History is kept for 30 days.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct HistoryChart: View {
    @EnvironmentObject private var store: UsageStore
    var since: Date
    var provider: Provider? = nil

    var body: some View {
        let points = store.history.filter { $0.date >= since && (provider == nil || $0.provider == provider) }
        if points.count < 2 {
            ContentUnavailableView(
                "Not enough data yet",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("Keep Gauge running and the chart will fill in.")
            )
        } else {
            Chart(points) { p in
                LineMark(
                    x: .value("Time", p.date),
                    y: .value("Remaining", p.remaining)
                )
                .foregroundStyle(by: .value("Limit", p.label))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
            }
            .chartYScale(domain: 0...1)
            .chartYAxis {
                AxisMarks(values: [0, 0.25, 0.5, 0.75, 1]) { v in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel { Text(Format.percent(v.as(Double.self) ?? 0)) }
                }
            }
            .chartLegend(position: .bottom, alignment: .leading)
        }
    }
}
