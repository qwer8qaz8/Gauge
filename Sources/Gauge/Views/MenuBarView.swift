import SwiftUI

// MARK: - Menu bar label

struct MenuBarLabel: View {
    @EnvironmentObject private var store: UsageStore
    @AppStorage(Prefs.menuBarStyle) private var style = MenuBarStyle.iconAndPercent.rawValue
    @AppStorage(Prefs.pinnedBucket) private var pinned = "auto"

    var body: some View {
        let featured = store.featuredBucket
        HStack(spacing: 4) {
            Image(systemName: symbol(for: featured?.remaining))
            switch MenuBarStyle(rawValue: style) ?? .iconAndPercent {
            case .iconOnly:
                EmptyView()
            case .iconAndPercent:
                if let featured { Text(Format.percent(featured.remaining)).monospacedDigit() }
            case .bothServices:
                Text(bothText).monospacedDigit()
            }
        }
        .id(pinned)
    }

    private var bothText: String {
        let parts = Provider.allCases.compactMap { p -> String? in
            guard let t = store.state(for: p).tightest else { return nil }
            return "\(p.shortName) \(Format.percent(t.remaining))"
        }
        return parts.isEmpty ? "—" : parts.joined(separator: "  ")
    }

    private func symbol(for remaining: Double?) -> String {
        guard let r = remaining else { return "gauge.with.dots.needle.bottom.50percent" }
        switch r {
        case ..<0.05: return "gauge.with.dots.needle.0percent"
        case ..<0.4: return "gauge.with.dots.needle.33percent"
        case ..<0.6: return "gauge.with.dots.needle.50percent"
        case ..<0.9: return "gauge.with.dots.needle.67percent"
        default: return "gauge.with.dots.needle.100percent"
        }
    }
}

// MARK: - Menu bar popover

struct MenuBarView: View {
    @EnvironmentObject private var store: UsageStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            if let featured = store.featuredBucket {
                featuredCard(featured)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                VStack(spacing: 10) {
                    ForEach(Provider.allCases) { provider in
                        providerSection(provider, now: ctx.date)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider().padding(.top, 6)
            footer
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text("Gauge").font(.system(size: 14, weight: .semibold))
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Group {
                        if store.isRefreshing {
                            Text("Refreshing…")
                        } else if let last = store.lastUpdated {
                            Text("Updated \(last.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))")
                        } else {
                            Text("Waiting for data")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await store.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                    .animation(store.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: store.isRefreshing)
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Refresh now")
        }
    }

    private func featuredCard(_ bucket: QuotaBucket) -> some View {
        HStack(spacing: 14) {
            RingGauge(progress: bucket.remaining, colors: bucket.provider.colors, lineWidth: 8) {
                Text(Format.percent(bucket.remaining))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 66, height: 66)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    ProviderBadge(provider: bucket.provider, size: 16)
                    Text(bucket.provider.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text(bucket.group).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text("\(bucket.window.label) limit · \(QuotaLevel.label(for: bucket.remaining))")
                    .font(.system(size: 11))
                    .foregroundStyle(QuotaLevel.color(for: bucket.remaining))
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    Text("Resets in \(Format.countdown(to: bucket.resetTime, now: ctx.date))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: bucket.provider.colors.map { $0.opacity(0.14) }, startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(bucket.provider.tint.opacity(0.18)))
    }

    @ViewBuilder
    private func providerSection(_ provider: Provider, now: Date) -> some View {
        let state = store.state(for: provider)
        if store.isEnabled(provider) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    ProviderBadge(provider: provider, size: 16)
                    Text(provider.displayName.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.6)
                    Spacer()
                    if state.isLoading { ProgressView().controlSize(.mini) }
                }
                .padding(.horizontal, 4)

                VStack(spacing: 2) {
                    if state.buckets.isEmpty {
                        HStack {
                            Text(state.error ?? (state.isLoading ? "Loading…" : "No data"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            if provider == .copilot && !store.hasGitHubToken {
                                Button("Connect") { showSettings() }
                                    .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(state.buckets) { CompactBucketRow(bucket: $0, now: now) }
                        if let error = state.error {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.orange)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            FooterButton(title: "Open Gauge", symbol: "macwindow") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            FooterButton(title: "Settings", symbol: "gearshape") { showSettings() }
            Spacer()
            FooterButton(title: "Quit", symbol: "power") { NSApp.terminate(nil) }
        }
    }

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }
}

private struct FooterButton: View {
    var title: String
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
