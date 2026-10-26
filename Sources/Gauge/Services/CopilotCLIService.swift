import Foundation

/// Reads usage counters that GitHub Copilot CLI records locally when a session ends
/// (`session.shutdown` events in `~/.copilot/session-state/<id>/events.jsonl`).
/// Works offline and needs no token. Only numbers are extracted — conversation content is ignored.
enum CopilotCLIService {
    static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".copilot/session-state", isDirectory: true)
    }

    static func directory() -> URL {
        let custom = (Prefs.defaults.string(forKey: Prefs.copilotCLIDir) ?? "").trimmingCharacters(in: .whitespaces)
        return custom.isEmpty ? defaultDirectory() : URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
    }

    static func load(from dir: URL) -> CLIStats {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return CLIStats(sessions: [], loadedAt: .now, found: false)
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()

        var sessions: [CLISession] = []
        for entry in entries {
            let events = entry.appendingPathComponent("events.jsonl")
            guard let data = try? Data(contentsOf: events, options: .mappedIfSafe) else { continue }
            let meta = readMeta(entry.appendingPathComponent("workspace.yaml"))
            let marker = Data("\"session.shutdown\"".utf8)

            let usageMarker = Data("\"session.usage_record\"".utf8)
            var index = 0
            var calls: [String: CLIModelUsage] = [:]
            var lastCall: Date?
            var shutdowns: [CLISession] = []
            for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
                let isShutdown = line.range(of: marker) != nil
                let isUsage = !isShutdown && line.range(of: usageMarker) != nil
                guard isShutdown || isUsage,
                      let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      let d = obj["data"] as? [String: Any] else { continue }
                let stamp = obj["timestamp"] as? String ?? ""
                guard let date = iso.date(from: stamp) ?? isoPlain.date(from: stamp) else { continue }
                if isUsage, obj["type"] as? String == "session.usage_record", let u = d["usage"] as? [String: Any] {
                    func n(_ k: String) -> Double { (u[k] as? NSNumber)?.doubleValue ?? 0 }
                    let name = (u["modelDisplayName"] as? String) ?? (u["model"] as? String) ?? "Unknown"
                    var m = calls[name] ?? CLIModelUsage(name: name)
                    m.calls += 1
                    m.requests += 1
                    m.premium += n("cost")
                    m.input += Int(n("inputTokens"))
                    m.output += Int(n("outputTokens"))
                    m.cacheRead += Int(n("cacheReadTokens"))
                    m.reasoning += Int(n("reasoningTokens"))
                    m.apiSeconds += n("duration") / 1000
                    m.ttftSumMs += n("timeToFirstTokenMs")
                    calls[name] = m
                    lastCall = date
                } else if isShutdown, obj["type"] as? String == "session.shutdown" {
                    shutdowns.append(parse(d, id: "\(entry.lastPathComponent)#\(index)", date: date, meta: meta))
                    index += 1
                }
            }
            if shutdowns.isEmpty {
                // Session still running (or crashed): build it from per-call records.
                if let last = lastCall {
                    let list = Array(calls.values)
                    sessions.append(CLISession(
                        id: entry.lastPathComponent, date: last, project: meta.project, client: meta.client,
                        premium: list.reduce(0) { $0 + $1.premium }, requests: list.reduce(0) { $0 + Int($1.requests) },
                        input: list.reduce(0) { $0 + $1.input }, output: list.reduce(0) { $0 + $1.output },
                        cacheRead: list.reduce(0) { $0 + $1.cacheRead }, cacheWrite: 0,
                        reasoning: list.reduce(0) { $0 + $1.reasoning },
                        apiSeconds: list.reduce(0) { $0 + $1.apiSeconds }, credits: 0,
                        linesAdded: 0, linesRemoved: 0, filesChanged: 0,
                        models: list.sorted { $0.apiSeconds > $1.apiSeconds }
                    ))
                }
            } else {
                // Attach per-model latency from the call records to the (usually single) shutdown summary.
                for var s in shutdowns {
                    s.models = s.models.map { m in
                        var m = m
                        if let c = calls[m.name] { m.apiSeconds = c.apiSeconds; m.ttftSumMs = c.ttftSumMs; m.calls = c.calls }
                        return m
                    }
                    sessions.append(s)
                }
            }
        }
        sessions.sort { $0.date > $1.date }
        return CLIStats(sessions: sessions, loadedAt: .now, found: true)
    }

    // MARK: - Parsing

    private static func parse(_ d: [String: Any], id: String, date: Date, meta: (project: String, client: String)) -> CLISession {
        func num(_ any: Any?) -> Double { (any as? NSNumber)?.doubleValue ?? 0 }
        let snapshot = d["accountingSnapshot"] as? [String: Any] ?? [:]
        let changes = (d["codeChanges"] as? [String: Any]) ?? (snapshot["codeChanges"] as? [String: Any]) ?? [:]
        let metrics = (d["modelMetrics"] as? [String: Any]) ?? (snapshot["modelMetrics"] as? [String: Any]) ?? [:]

        // Friendly model names, when the CLI provides them.
        var display: [String: String] = [:]
        for p in (d["providerModelMetrics"] as? [[String: Any]]) ?? [] {
            if let id = p["modelId"] as? String, let name = p["modelDisplayName"] as? String { display[id] = name }
        }

        var models: [CLIModelUsage] = []
        var input = 0, output = 0, cacheRead = 0, cacheWrite = 0, reasoning = 0, requests = 0
        for (name, value) in metrics {
            guard let m = value as? [String: Any] else { continue }
            let req = m["requests"] as? [String: Any] ?? [:]
            let use = m["usage"] as? [String: Any] ?? [:]
            var u = CLIModelUsage(name: display[name] ?? name)
            u.requests = num(req["count"])
            u.premium = num(req["cost"])
            u.input = Int(num(use["inputTokens"]))
            u.output = Int(num(use["outputTokens"]))
            u.cacheRead = Int(num(use["cacheReadTokens"]))
            u.reasoning = Int(num(use["reasoningTokens"]))
            input += u.input; output += u.output; cacheRead += u.cacheRead
            cacheWrite += Int(num(use["cacheWriteTokens"]))
            reasoning += u.reasoning
            requests += Int(u.requests)
            models.append(u)
        }

        let premium = d["totalPremiumRequests"] != nil
            ? num(d["totalPremiumRequests"])
            : (snapshot["totalPremiumRequestCost"] != nil ? num(snapshot["totalPremiumRequestCost"]) : models.reduce(0) { $0 + $1.premium })
        let nano = d["totalNanoAiu"] != nil ? num(d["totalNanoAiu"]) : num(snapshot["totalNanoAiu"])
        let apiMs = d["totalApiDurationMs"] != nil ? num(d["totalApiDurationMs"]) : num(snapshot["totalApiDurationMs"])

        return CLISession(
            id: id, date: date, project: meta.project, client: meta.client,
            premium: premium, requests: requests,
            input: input, output: output, cacheRead: cacheRead, cacheWrite: cacheWrite, reasoning: reasoning,
            apiSeconds: apiMs / 1000, credits: nano / 1_000_000_000,
            linesAdded: Int(num(changes["linesAdded"])), linesRemoved: Int(num(changes["linesRemoved"])),
            filesChanged: Int(num(changes["filesModifiedCount"])),
            models: models.sorted { $0.premium > $1.premium }
        )
    }

    /// Reads only `cwd` and `client_name` from workspace.yaml (the session `name` there can hold prompt text, so it is ignored).
    private static func readMeta(_ url: URL) -> (project: String, client: String) {
        var project = "Unknown", client = "copilot-cli"
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return (project, client) }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("cwd:") {
                let path = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
                if path == NSHomeDirectory() { project = "~ (home)" }
                else if !path.isEmpty { project = (path as NSString).lastPathComponent }
            } else if line.hasPrefix("client_name:") {
                let c = line.dropFirst(12).trimmingCharacters(in: .whitespaces)
                if !c.isEmpty { client = c }
            }
        }
        return (project, client)
    }
}
