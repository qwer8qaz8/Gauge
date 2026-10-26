import Foundation

/// Reads Antigravity quota using the official CLI: `agy -p /quota --output-format json`.
/// The `/quota` slash command runs locally against your signed-in account and consumes no tokens.
enum AntigravityService {
    enum ServiceError: LocalizedError {
        case cliNotFound
        case failed(String)
        case badOutput(String)

        var errorDescription: String? {
            switch self {
            case .cliNotFound:
                "Couldn't find the Antigravity CLI (agy). Install it or set its path in Settings."
            case .failed(let msg): "agy failed: \(msg)"
            case .badOutput(let msg): "Unexpected agy output: \(msg)"
            }
        }
    }

    // MARK: JSON shape

    private struct Envelope: Decodable {
        let status: String?
        let response: String?
        let command: Command?
    }

    private struct Command: Decodable {
        let name: String?
        let data: DataBlock?
    }

    private struct DataBlock: Decodable {
        let description: String?
        let groups: [Group]?
    }

    private struct Group: Decodable {
        let name: String
        let description: String?
        let buckets: [Bucket]
    }

    private struct Bucket: Decodable {
        let id: String
        let name: String
        let description: String?
        let window: String?
        let remaining_fraction: Double?
        let reset_time: String?
    }

    // MARK: Locate CLI

    static func locateCLI() -> String? {
        let custom = (Prefs.defaults.string(forKey: Prefs.agyPath) ?? "").trimmingCharacters(in: .whitespaces)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            custom,
            "\(home)/.local/bin/agy",
            "/opt/homebrew/bin/agy",
            "/usr/local/bin/agy",
            "\(home)/.gemini/antigravity-cli/bin/agy",
        ].filter { !$0.isEmpty }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: Fetch

    static func fetch() async throws -> (buckets: [QuotaBucket], summary: String?) {
        guard let cli = locateCLI() else { throw ServiceError.cliNotFound }
        let output = try await ProcessRunner.run(
            cli,
            arguments: ["-p", "/quota", "--output-format", "json", "--print-timeout", "45s"],
            timeout: 60
        )
        return try parse(output)
    }

    static func parse(_ output: Data) throws -> (buckets: [QuotaBucket], summary: String?) {
        // The CLI may print a log line before the JSON; find the first '{'.
        guard let start = output.firstIndex(of: UInt8(ascii: "{")) else {
            throw ServiceError.badOutput(String(decoding: output.prefix(200), as: UTF8.self))
        }
        let json = output[start...]
        let env: Envelope
        do {
            env = try JSONDecoder().decode(Envelope.self, from: json)
        } catch {
            throw ServiceError.badOutput(error.localizedDescription)
        }
        if let status = env.status, status != "SUCCESS" {
            throw ServiceError.failed(env.response ?? status)
        }

        let iso = ISO8601DateFormatter()
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let groups = env.command?.data?.groups, !groups.isEmpty {
            var buckets: [QuotaBucket] = []
            for g in groups {
                for b in g.buckets {
                    let reset = b.reset_time.flatMap { iso.date(from: $0) ?? isoFrac.date(from: $0) }
                    buckets.append(QuotaBucket(
                        id: "ag.\(b.id)",
                        provider: .antigravity,
                        group: g.name,
                        groupDetail: g.description,
                        name: cleanName(b.name, group: g.name),
                        detail: b.description,
                        window: QuotaWindow(raw: b.window),
                        remaining: min(max(b.remaining_fraction ?? 0, 0), 1),
                        resetTime: reset
                    ))
                }
            }
            return (buckets, env.command?.data?.description)
        }

        // Fallback: parse the tab separated text table in `response`.
        guard let text = env.response else { throw ServiceError.badOutput("empty response") }
        return (parseTable(text, iso: iso), nil)
    }

    static func parseTable(_ text: String, iso: ISO8601DateFormatter) -> [QuotaBucket] {
        text.split(separator: "\n").enumerated().compactMap { idx, line in
            let cols = line.split(separator: "\t").map(String.init)
            guard cols.count >= 3 else { return nil }
            let pct = Double(cols[2].replacingOccurrences(of: "%", with: "")) ?? 0
            let window: QuotaWindow = cols[1].lowercased().contains("five hour") ? .fiveHour
                : cols[1].lowercased().contains("week") ? .weekly : .other
            return QuotaBucket(
                id: "ag.row\(idx).\(cols[0])",
                provider: .antigravity,
                group: cols[0],
                name: cleanName(cols[1], group: cols[0]),
                window: window,
                remaining: pct / 100,
                resetTime: cols.count > 3 ? iso.date(from: cols[3]) : nil
            )
        }
    }

    /// "Gemini 4 Argon Weekly Limit" in group "Gemini 4 Argon" -> "Weekly Limit".
    private static func cleanName(_ name: String, group: String) -> String {
        var n = name
        if n.hasPrefix(group) { n = String(n.dropFirst(group.count)).trimmingCharacters(in: .whitespaces) }
        n = n.replacingOccurrences(of: " Remaining", with: "")
        return n.isEmpty ? name : n
    }
}

// MARK: - Process runner

enum ProcessRunner {
    static func run(_ path: String, arguments: [String], timeout: TimeInterval) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                process.currentDirectoryURL = FileManager.default.temporaryDirectory
                var env = ProcessInfo.processInfo.environment
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                env["NO_COLOR"] = "1"
                env["TERM"] = "dumb"
                process.environment = env

                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err
                process.standardInput = FileHandle.nullDevice

                var outData = Data()
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    outData = out.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    errData = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                do {
                    try process.run()
                } catch {
                    cont.resume(throwing: error)
                    return
                }

                let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                process.waitUntilExit()
                timer.cancel()
                group.wait()

                if process.terminationStatus == 0 || !outData.isEmpty {
                    cont.resume(returning: outData)
                } else {
                    let msg = String(decoding: errData.isEmpty ? outData : errData, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    cont.resume(throwing: AntigravityService.ServiceError.failed(
                        msg.isEmpty ? "exit code \(process.terminationStatus)" : String(msg.prefix(300))
                    ))
                }
            }
        }
    }
}
