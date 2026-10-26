import Charts
import SwiftUI

/// Detailed stats from local GitHub Copilot CLI sessions: per-model time, tokens, requests, latency, projects.
struct CLIStatsPage: View {
    @EnvironmentObject private var store: UsageStore
    @AppStorage(Prefs.statsRangeDays) private var rangeDays = 30
    private var metric: Metric {
        get { Metric(rawValue: store.cliMetric) ?? .premium }
        nonmutating set { store.cliMetric = newValue.rawValue }
    }
    private var modelSort: ModelSort {
        get { ModelSort(rawValue: store.cliModelSort) ?? .time }
        nonmutating set { store.cliModelSort = newValue.rawValue }
    }
    private var metricBinding: Binding<Metric> { Binding(get: { metric }, set: { metric = $0 }) }
    private var sortBinding: Binding<ModelSort> { Binding(get: { modelSort }, set: { modelSort = $0 }) }

    enum Metric: String, CaseIterable, Identifiable {
        case premium = "Requests", tokens = "Tokens", sessions = "Sessions"
        var id: String { rawValue }
    }

    enum ModelSort: String, CaseIterable, Identifiable {
        case time = "Time", requests = "Requests", tokens = "Tokens"
        var id: String { rawValue }
    }

    private var since: Date? {
        rangeDays == 0 ? nil : Calendar.current.date(byAdding: .day, value: -(rangeDays - 1), to: Calendar.current.startOfDay(for: .now))
    }

    var body: some View {
        let stats = store.cliStats
        let summary = stats.summary(since: since)
        VStack(alignment: .leading, spacing: 22) {
            header

            if !stats.found {
                ContentUnavailableView(
                    "No Copilot CLI data found",
                    systemImage: "terminal",
                    description: Text("Run a Copilot CLI session, or set the session folder in Settings → Copilot CLI.")
                )
            } else if summary.sessions == 0 {
                ContentUnavailableView("No sessions in this range", systemImage: "calendar.badge.exclamationmark",
                                       description: Text("Try a longer range."))
            } else {
                tiles(summary)
                dailyChart(stats)
                modelSection(stats)
                HStack(alignment: .top, spacing: 14) {
                    breakdown("By project", rows: stats.byProject(since: since), symbol: "folder")
                    breakdown("By client", rows: stats.byClient(since: since), symbol: "app.connected.to.app.below.fill")
                }
                recent(stats)
                Text("Read locally from your Copilot CLI session history. Only counters are used — prompts and responses are never read or stored.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 14) {
            ProviderBadge(provider: .copilot, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Copilot CLI Stats").font(.largeTitle.weight(.bold))
                if let t = store.cliStats.loadedAt {
                    Text("Scanned \(t.formatted(date: .omitted, time: .shortened))")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Picker("Range", selection: $rangeDays) {
                Text("7d").tag(7)
                Text("30d").tag(30)
                Text("90d").tag(90)
                Text("All").tag(0)
            }
            .pickerStyle(.segmented).frame(width: 200).labelsHidden()
            Button {
                Task { await store.refreshCLIStats() }
            } label: {
                if store.isLoadingCLI { ProgressView().controlSize(.small) } else { Label("Rescan", systemImage: "arrow.clockwise") }
            }
        }
    }

    private func tiles(_ s: CLISummary) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
            StatTile(title: "Premium requests", value: Format.number(s.premium), unit: "\(s.sessions) sessions", symbol: "bolt.fill")
            StatTile(title: "Model API time", value: Format.duration(seconds: s.apiSeconds), unit: "waiting on models", symbol: "timer")
            StatTile(title: "Model calls", value: Format.compact(s.requests), unit: "API requests", symbol: "arrow.left.arrow.right")
            StatTile(title: "Tokens", value: Format.compact(s.totalTokens), unit: "\(Format.compact(s.input)) in · \(Format.compact(s.output)) out", symbol: "textformat.123")
            StatTile(title: "Cache hit rate", value: Format.percent(s.cacheHitRate), unit: "\(Format.compact(s.cacheRead)) cached input", symbol: "memorychip")
            StatTile(title: "Reasoning tokens", value: Format.compact(s.reasoning), unit: "thinking output", symbol: "brain")
            StatTile(title: "Code changes", value: "+\(Format.compact(s.linesAdded)) / −\(Format.compact(s.linesRemoved))", unit: "\(s.filesChanged) files touched", symbol: "chevron.left.forwardslash.chevron.right")
            StatTile(title: "Avg per session", value: Format.number((s.avgPremiumPerSession * 10).rounded() / 10), unit: "requests · \(Format.duration(seconds: s.sessions > 0 ? s.apiSeconds / Double(s.sessions) : 0))", symbol: "chart.bar")
        }
    }

    private func dailyChart(_ stats: CLIStats) -> some View {
        let days = rangeDays == 0 ? 90 : rangeDays
        let points = stats.daily(days: days)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Daily activity").font(.title3.weight(.semibold))
                Spacer()
                Picker("Metric", selection: metricBinding) {
                    ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 240).labelsHidden()
            }
            Card {
                Chart(points) { p in
                    BarMark(x: .value("Day", p.day, unit: .day), y: .value(metric.rawValue, value(p)))
                        .foregroundStyle(Provider.copilot.gradient)
                        .cornerRadius(3)
                }
                .frame(height: 200)
            }
        }
    }

    private func value(_ p: CLIDayPoint) -> Double {
        switch metric {
        case .premium: p.premium
        case .tokens: Double(p.tokens)
        case .sessions: Double(p.sessions)
        }
    }

    private func modelSection(_ stats: CLIStats) -> some View {
        var rows = stats.byModel(since: since)
        switch modelSort {
        case .time: rows.sort { $0.apiSeconds > $1.apiSeconds }
        case .requests: rows.sort { $0.premium > $1.premium }
        case .tokens: rows.sort { $0.tokens > $1.tokens }
        }
        let totalTime = max(rows.reduce(0) { $0 + $1.apiSeconds }, 0.001)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Usage by model").font(.title3.weight(.semibold))
                Spacer()
                Picker("Sort", selection: sortBinding) {
                    ForEach(ModelSort.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 220).labelsHidden()
            }
            Card {
                VStack(spacing: 0) {
                    HStack {
                        Text("Model").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Time").frame(width: 80, alignment: .trailing)
                        Text("Share").frame(width: 60, alignment: .trailing)
                        Text("Reqs").frame(width: 60, alignment: .trailing)
                        Text("Calls").frame(width: 50, alignment: .trailing)
                        Text("Tokens").frame(width: 70, alignment: .trailing)
                        Text("TTFT").frame(width: 66, alignment: .trailing)
                        Text("Tok/s").frame(width: 56, alignment: .trailing)
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                    ForEach(rows) { r in
                        Divider()
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(r.name).font(.callout.weight(.medium)).lineLimit(1)
                                Meter(value: r.apiSeconds / totalTime, height: 4)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(r.apiSeconds > 0 ? Format.duration(seconds: r.apiSeconds) : "—").frame(width: 80, alignment: .trailing)
                            Text(r.apiSeconds > 0 ? Format.percent(r.apiSeconds / totalTime) : "—").frame(width: 60, alignment: .trailing)
                            Text(Format.number(r.premium)).frame(width: 60, alignment: .trailing)
                            Text("\(r.calls > 0 ? r.calls : Int(r.requests))").frame(width: 50, alignment: .trailing)
                            Text(Format.compact(r.tokens)).frame(width: 70, alignment: .trailing)
                            Text(r.avgTTFTms > 0 ? String(format: "%.1fs", r.avgTTFTms / 1000) : "—").frame(width: 66, alignment: .trailing)
                            Text(r.tokensPerSecond > 0 ? String(format: "%.0f", r.tokensPerSecond) : "—").frame(width: 56, alignment: .trailing)
                        }
                        .font(.callout.monospacedDigit())
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private func breakdown(_ title: String, rows: [CLIBreakdownRow], symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.semibold))
            Card {
                VStack(spacing: 8) {
                    ForEach(rows.prefix(6)) { r in
                        HStack {
                            Label(r.name, systemImage: symbol).lineLimit(1)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 0) {
                                Text("\(Format.number(r.premium)) req").font(.callout.monospacedDigit())
                                Text("\(Format.compact(r.tokens)) tok · \(Format.duration(seconds: r.apiSeconds))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func recent(_ stats: CLIStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent sessions").font(.title3.weight(.semibold))
            Card {
                VStack(spacing: 0) {
                    ForEach(Array(stats.sessions(since: since).prefix(12).enumerated()), id: \.element.id) { idx, s in
                        if idx > 0 { Divider() }
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.project).font(.callout.weight(.medium)).lineLimit(1)
                                Text(s.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(s.models.first?.name ?? "—").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text(Format.duration(seconds: s.apiSeconds)).frame(width: 70, alignment: .trailing)
                            Text("\(Format.number(s.premium)) req").frame(width: 60, alignment: .trailing)
                            Text("\(Format.compact(s.input + s.output)) tok").frame(width: 80, alignment: .trailing)
                        }
                        .font(.callout.monospacedDigit())
                        .padding(.vertical, 7)
                    }
                }
            }
        }
    }
}
