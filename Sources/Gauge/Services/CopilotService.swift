import Foundation

/// Reads Copilot premium request / AI credit usage from GitHub's documented billing REST API:
/// `GET /users/{username}/settings/billing/premium_request/usage`
/// Requires a fine-grained personal access token with the **Plan (read)** user permission.
enum CopilotService {
    enum ServiceError: LocalizedError {
        case noToken
        case http(Int, String)
        case decoding(String)

        var errorDescription: String? {
            switch self {
            case .noToken:
                "Add a GitHub token in Settings to track Copilot usage."
            case .http(401, _):
                "GitHub rejected the token (401). Check that it hasn't expired."
            case .http(403, _), .http(404, _):
                "GitHub billing API not accessible. Use a fine-grained token with “Plan” (read), or run `gh auth refresh -h github.com -s user`."
            case .http(let code, let msg):
                "GitHub API error \(code): \(msg)"
            case .decoding(let msg):
                "Couldn't read GitHub response: \(msg)"
            }
        }
    }

    private struct User: Decodable { let login: String }

    private struct UsageReport: Decodable {
        let usageItems: [Item]?
    }

    private struct Item: Decodable {
        let product: String?
        let sku: String?
        let model: String?
        let unitType: String?
        let quantity: Double?
        let grossQuantity: Double?
        let netAmount: Double?

        var amount: Double { grossQuantity ?? quantity ?? 0 }
    }

    private static let api = URL(string: "https://api.github.com")!

    private static func request(_ path: String, query: [URLQueryItem] = [], token: String) async throws -> Data {
        var comps = URLComponents(url: api.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("Gauge-macOS", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw ServiceError.http(code, msg ?? HTTPURLResponse.localizedString(forStatusCode: code))
        }
        return data
    }

    /// Token from Keychain, else (optionally) from the signed-in GitHub CLI.
    static func resolveToken() async -> String? {
        if let t = Keychain.read(Keychain.githubToken), !t.isEmpty { return t }
        guard Prefs.defaults.bool(forKey: Prefs.useGhToken) else { return nil }
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        guard let gh = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }),
              let out = try? await ProcessRunner.run(gh, arguments: ["auth", "token"], timeout: 10) else { return nil }
        let t = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static func fetch(allowance: Double) async throws -> CopilotReport {
        guard let token = await resolveToken() else { throw ServiceError.noToken }

        let user: User
        do {
            user = try JSONDecoder().decode(User.self, from: try await request("user", token: token))
        } catch let e as ServiceError { throw e } catch {
            throw ServiceError.decoding(error.localizedDescription)
        }

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()
        let parts = utc.dateComponents([.year, .month, .day], from: now)
        let path = "users/\(user.login)/settings/billing/premium_request/usage"
        let monthQuery = [
            URLQueryItem(name: "year", value: "\(parts.year!)"),
            URLQueryItem(name: "month", value: "\(parts.month!)"),
        ]

        async let monthData = request(path, query: monthQuery, token: token)
        async let dayData = try? request(path, query: monthQuery + [URLQueryItem(name: "day", value: "\(parts.day!)")], token: token)

        let month: UsageReport
        do {
            month = try JSONDecoder().decode(UsageReport.self, from: try await monthData)
        } catch let e as ServiceError { throw e } catch {
            throw ServiceError.decoding(error.localizedDescription)
        }
        let day = (await dayData).flatMap { try? JSONDecoder().decode(UsageReport.self, from: $0) }

        let items = (month.usageItems ?? []).filter { ($0.product ?? "copilot").lowercased().contains("copilot") }
        let used = items.reduce(0) { $0 + $1.amount }
        let overage = items.reduce(0) { $0 + ($1.netAmount ?? 0) }
        let todayUsed = day.map { ($0.usageItems ?? []).filter { ($0.product ?? "copilot").lowercased().contains("copilot") }.reduce(0) { $0 + $1.amount } }

        var byModel: [String: (Double, Double)] = [:]
        for item in items {
            let key = item.model ?? item.sku ?? "Other"
            let cur = byModel[key] ?? (0, 0)
            byModel[key] = (cur.0 + item.amount, cur.1 + (item.netAmount ?? 0))
        }
        let models = byModel
            .map { ModelUsage(model: $0.key, quantity: $0.value.0, netAmount: $0.value.1) }
            .sorted { $0.quantity > $1.quantity }

        let unitRaw = items.first?.unitType?.lowercased() ?? "requests"
        let unit = unitRaw.contains("credit") ? "credits" : "requests"

        let startOfMonth = utc.date(from: DateComponents(year: parts.year, month: parts.month, day: 1))!
        let reset = utc.date(byAdding: .month, value: 1, to: startOfMonth)!

        return CopilotReport(
            login: user.login,
            used: used,
            allowance: allowance,
            today: todayUsed,
            overageCost: overage,
            unit: unit,
            models: models,
            resetTime: reset
        )
    }

    /// Estimate built from local Copilot CLI sessions when the billing API isn't reachable.
    static func localReport(from stats: CLIStats, allowance: Double) -> CopilotReport? {
        guard stats.found else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let comps = utc.dateComponents([.year, .month], from: .now)
        let start = utc.date(from: comps)!
        let reset = utc.date(byAdding: .month, value: 1, to: start)!
        let month = stats.sessions(since: start)
        let used = month.reduce(0) { $0 + $1.premium }
        let today = stats.sessions(since: Calendar.current.startOfDay(for: .now)).reduce(0) { $0 + $1.premium }
        let models = stats.byModel(since: start).map { ModelUsage(model: $0.name, quantity: $0.premium, netAmount: 0) }
            .sorted { $0.quantity > $1.quantity }
        return CopilotReport(login: "local", used: used, allowance: allowance, today: today,
                             overageCost: max(0, used - allowance) * 0.04, unit: "requests",
                             models: models, resetTime: reset, isEstimate: true)
    }

    static func buckets(from report: CopilotReport) -> [QuotaBucket] {
        let allowance = max(report.allowance, 1)
        let remaining = max(0, 1 - report.used / allowance)
        return [QuotaBucket(
            id: "cp.monthly",
            provider: .copilot,
            group: "Premium Requests",
            groupDetail: "Monthly allowance for premium models in Copilot Chat, agent mode, CLI and code review.",
            name: "Monthly",
            detail: report.isEstimate
                ? "Estimated from local Copilot CLI sessions only (other Copilot surfaces not counted). Resets on the 1st (UTC)."
                : "Signed in as @\(report.login). Allowance resets on the 1st (UTC).",
            window: .monthly,
            remaining: remaining,
            resetTime: report.resetTime,
            usageText: "\(Format.number(report.used)) / \(Format.number(report.allowance)) \(report.unit)"
        )]
    }
}
