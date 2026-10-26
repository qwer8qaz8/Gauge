import Foundation

/// Per-model totals inside one Copilot CLI session.
struct CLIModelUsage: Hashable {
    var name: String
    var requests: Double = 0
    var premium: Double = 0
    var input: Int = 0
    var output: Int = 0
    var cacheRead: Int = 0
    var reasoning: Int = 0
    /// Time spent waiting on the model API, from per-call usage records.
    var apiSeconds: Double = 0
    var ttftSumMs: Double = 0
    var calls: Int = 0
}

/// One finished GitHub Copilot CLI session, read from `~/.copilot/session-state/*/events.jsonl`.
/// Only aggregate counters are kept — never prompts, responses or file contents.
struct CLISession: Identifiable, Hashable {
    let id: String
    let date: Date
    /// Last path component of the working directory (full path is never stored).
    let project: String
    /// App that launched the session (e.g. "copilot-cli", "vscode", or a third-party ACP client).
    let client: String
    var premium: Double
    var requests: Int
    var input: Int
    var output: Int
    var cacheRead: Int
    var cacheWrite: Int
    var reasoning: Int
    var apiSeconds: Double
    var credits: Double
    var linesAdded: Int
    var linesRemoved: Int
    var filesChanged: Int
    var models: [CLIModelUsage]
}

/// Aggregate over a set of sessions.
struct CLISummary {
    var sessions = 0
    var premium = 0.0
    var requests = 0
    var input = 0
    var output = 0
    var cacheRead = 0
    var reasoning = 0
    var apiSeconds = 0.0
    var credits = 0.0
    var linesAdded = 0
    var linesRemoved = 0
    var filesChanged = 0

    init(_ list: [CLISession] = []) {
        for s in list {
            sessions += 1
            premium += s.premium
            requests += s.requests
            input += s.input
            output += s.output
            cacheRead += s.cacheRead
            reasoning += s.reasoning
            apiSeconds += s.apiSeconds
            credits += s.credits
            linesAdded += s.linesAdded
            linesRemoved += s.linesRemoved
            filesChanged += s.filesChanged
        }
    }

    var totalTokens: Int { input + output }
    /// Share of input tokens served from cache.
    var cacheHitRate: Double { input > 0 ? Double(cacheRead) / Double(input) : 0 }
    var avgPremiumPerSession: Double { sessions > 0 ? premium / Double(sessions) : 0 }
}

struct CLIDayPoint: Identifiable {
    let day: Date
    let premium: Double
    let tokens: Int
    let sessions: Int
    var id: Date { day }
}

struct CLIBreakdownRow: Identifiable {
    let name: String
    let premium: Double
    let requests: Double
    let tokens: Int
    var apiSeconds: Double = 0
    var calls: Int = 0
    var avgTTFTms: Double = 0
    var id: String { name }
    /// Output tokens per second of API time (generation speed estimate).
    var outputTokens: Int = 0
    var tokensPerSecond: Double { apiSeconds > 0 ? Double(outputTokens) / apiSeconds : 0 }
}

struct CLIStats {
    var sessions: [CLISession] = []
    var loadedAt: Date?
    var found = false

    func sessions(since: Date?) -> [CLISession] {
        guard let since else { return sessions }
        return sessions.filter { $0.date >= since }
    }

    func summary(since: Date?) -> CLISummary { CLISummary(sessions(since: since)) }

    func daily(days: Int, calendar: Calendar = .current) -> [CLIDayPoint] {
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        var buckets: [Date: (Double, Int, Int)] = [:]
        for s in sessions where s.date >= start {
            let d = calendar.startOfDay(for: s.date)
            let cur = buckets[d] ?? (0, 0, 0)
            buckets[d] = (cur.0 + s.premium, cur.1 + s.input + s.output, cur.2 + 1)
        }
        return (0..<days).compactMap { offset in
            guard let d = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let v = buckets[d] ?? (0, 0, 0)
            return CLIDayPoint(day: d, premium: v.0, tokens: v.1, sessions: v.2)
        }
    }

    func byModel(since: Date?) -> [CLIBreakdownRow] {
        var map: [String: CLIModelUsage] = [:]
        for s in sessions(since: since) {
            for m in s.models {
                var cur = map[m.name] ?? CLIModelUsage(name: m.name)
                cur.requests += m.requests
                cur.premium += m.premium
                cur.input += m.input
                cur.output += m.output
                cur.apiSeconds += m.apiSeconds
                cur.ttftSumMs += m.ttftSumMs
                cur.calls += m.calls
                map[m.name] = cur
            }
        }
        return map.values
            .map {
                CLIBreakdownRow(name: $0.name, premium: $0.premium, requests: $0.requests, tokens: $0.input + $0.output,
                                apiSeconds: $0.apiSeconds, calls: $0.calls,
                                avgTTFTms: $0.calls > 0 ? $0.ttftSumMs / Double($0.calls) : 0, outputTokens: $0.output)
            }
            .sorted { ($0.apiSeconds, $0.premium) > ($1.apiSeconds, $1.premium) }
    }

    func byProject(since: Date?) -> [CLIBreakdownRow] { group(since: since) { $0.project } }
    func byClient(since: Date?) -> [CLIBreakdownRow] { group(since: since) { $0.client } }

    private func group(since: Date?, key: (CLISession) -> String) -> [CLIBreakdownRow] {
        var map: [String: (Double, Double, Int, Double)] = [:]
        for s in sessions(since: since) {
            let k = key(s)
            let cur = map[k] ?? (0, 0, 0, 0)
            map[k] = (cur.0 + s.premium, cur.1 + Double(s.requests), cur.2 + s.input + s.output, cur.3 + s.apiSeconds)
        }
        return map
            .map { CLIBreakdownRow(name: $0.key, premium: $0.value.0, requests: $0.value.1, tokens: $0.value.2, apiSeconds: $0.value.3) }
            .sorted { ($0.premium, $0.tokens) > ($1.premium, $1.tokens) }
    }
}

extension Format {
    /// 12_345 -> "12.3K", 1_200_000 -> "1.2M".
    static func compact(_ value: Int) -> String {
        let v = Double(value)
        switch abs(v) {
        case 1_000_000_000...: return String(format: "%.1fB", v / 1_000_000_000)
        case 1_000_000...: return String(format: "%.1fM", v / 1_000_000)
        case 10_000...: return String(format: "%.0fK", v / 1_000)
        case 1_000...: return String(format: "%.1fK", v / 1_000)
        default: return "\(value)"
        }
    }

    static func duration(seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s >= 3600 { return "\(s / 3600)h \((s % 3600) / 60)m" }
        if s >= 60 { return "\(s / 60)m \(s % 60)s" }
        return "\(s)s"
    }
}
