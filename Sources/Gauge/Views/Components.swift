import SwiftUI

// MARK: - Ring gauge

struct RingGauge<Center: View>: View {
    var progress: Double
    var colors: [Color]
    var lineWidth: CGFloat = 10
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(CGFloat(progress), 0.001))
                .stroke(
                    AngularGradient(
                        colors: colors + [colors.first ?? .accentColor],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * max(progress, 0.01))
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: (colors.last ?? .clear).opacity(0.35), radius: lineWidth * 0.6)
                .animation(.spring(response: 0.7, dampingFraction: 0.85), value: progress)
            center()
        }
    }
}

extension RingGauge where Center == EmptyView {
    init(progress: Double, colors: [Color], lineWidth: CGFloat = 10) {
        self.init(progress: progress, colors: colors, lineWidth: lineWidth) { EmptyView() }
    }
}

/// Ring colors driven by how much quota is left.
func levelColors(_ remaining: Double) -> [Color] {
    let c = QuotaLevel.color(for: remaining)
    return [c.opacity(0.75), c]
}

// MARK: - Linear meter

struct Meter: View {
    var value: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: levelColors(value), startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * value))
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: value)
    }
}

// MARK: - Pills & badges

struct Pill: View {
    var text: String
    var symbol: String? = nil
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.12), in: Capsule())
    }
}

struct ProviderBadge: View {
    var provider: Provider
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(provider.gradient)
            Image(systemName: provider.symbol)
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: provider.tint.opacity(0.35), radius: 4, y: 2)
    }
}

// MARK: - Card container

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07))
            )
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}

// MARK: - Bucket card (dashboard)

struct BucketCard: View {
    var bucket: QuotaBucket

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 16) {
                RingGauge(progress: bucket.remaining, colors: levelColors(bucket.remaining), lineWidth: 9) {
                    VStack(spacing: 0) {
                        Text(Format.percent(bucket.remaining))
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("left")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 78, height: 78)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(bucket.group)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Pill(text: QuotaLevel.label(for: bucket.remaining), color: QuotaLevel.color(for: bucket.remaining))
                    }
                    HStack(spacing: 6) {
                        Pill(text: bucket.window.label, symbol: bucket.window.symbol, color: bucket.provider.tint)
                        if let usage = bucket.usageText {
                            Text(usage).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Resets in \(Format.countdown(to: bucket.resetTime, now: ctx.date))")
                                .monospacedDigit()
                            if bucket.resetTime != nil {
                                Text("· \(Format.resetDate(bucket.resetTime))")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .help(bucket.detail ?? bucket.title)
    }
}

// MARK: - Compact row (menu bar)

struct CompactBucketRow: View {
    var bucket: QuotaBucket
    var now: Date

    var body: some View {
        HStack(spacing: 10) {
            RingGauge(progress: bucket.remaining, colors: levelColors(bucket.remaining), lineWidth: 3.5)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(bucket.group)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text("\(bucket.window.label) · resets in \(Format.countdown(to: bucket.resetTime, now: now))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            Text(Format.percent(bucket.remaining))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(QuotaLevel.color(for: bucket.remaining))
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .help(bucket.detail ?? bucket.title)
    }
}

// MARK: - Error / empty states

struct ProviderMessage: View {
    var provider: Provider
    var message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Background

struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Circle()
                .fill(Provider.antigravity.tint.opacity(0.16))
                .frame(width: 520)
                .blur(radius: 120)
                .offset(x: -260, y: -220)
            Circle()
                .fill(Provider.copilot.colors[1].opacity(0.13))
                .frame(width: 480)
                .blur(radius: 120)
                .offset(x: 320, y: 260)
        }
        .ignoresSafeArea()
    }
}
