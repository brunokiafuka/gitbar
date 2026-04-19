import SwiftUI

struct StatsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.colorScheme) private var colorScheme
    @State private var range: StatsRange = .today

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                Link(destination: remoteGithubURL) {
                    HStack(spacing: 5) {
                        LucideRepoIconView(icon: .gitPullRequest, size: 12, color: Theme.blue)
                        Text("View on GitHub in the browser")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.blue)

                if let err = store.statsError, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.red)
                }

                if store.statsLoading && store.statsSnapshot == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    kpiGrid
                    activitySection
                    bottomRows
                }

                if let last = store.lastRefreshed {
                    Text("Lists updated \(RelativeTime.short(last)) ago")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.meta)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
        }
        // Stats are not polled with PR lists — load when opening this tab, changing range, or updating the token.
        .onAppear {
            Task { await store.loadStats(range: range) }
        }
        .onChange(of: range) { _, new in
            Task { await store.loadStats(range: new) }
        }
        .onChange(of: store.token) { _, _ in
            Task { await store.loadStats(range: range) }
        }
    }

    /// Opens your profile when logged in; otherwise the GitHub home page.
    private var remoteGithubURL: URL {
        if let login = store.viewer?.login ?? store.myLogin,
           let u = URL(string: "https://github.com/\(login)") {
            return u
        }
        return URL(string: "https://github.com")!
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("YOUR PACE")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)

            Spacer()

            Picker("", selection: $range) {
                ForEach(StatsRange.allCases) { r in
                    Text(r.title).tag(r)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
    }

    @ViewBuilder
    private var kpiGrid: some View {
        let s = store.statsSnapshot
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ], spacing: 10) {
            PaceTile(
                title: "PRS MERGED",
                value: s.map { "\($0.prsMerged)" } ?? "—",
                trend: s?.prsMergedTrend,
                icon: .circleCheck,
                tint: Theme.green
            )
            PaceTile(
                title: "PRS REVIEWED",
                value: s.map { "\($0.prsReviewed)" } ?? "—",
                trend: s?.prsReviewedTrend,
                icon: .eye,
                tint: Theme.blue
            )
            PaceTile(
                title: "ISSUES CLOSED",
                value: s.map { "\($0.issuesClosed)" } ?? "—",
                trend: s?.issuesClosedTrend,
                icon: .circleDot,
                tint: Theme.lilac
            )
            PaceTile(
                title: "COMMITS",
                value: s.map { "\($0.commits)" } ?? "—",
                trend: s?.commitsTrend,
                icon: .gitCommitHorizontal,
                tint: Theme.slate
            )
        }
        .opacity(store.statsLoading ? 0.55 : 1)
    }

    @ViewBuilder
    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Activity")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Last 24 hours")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.meta)
            }

            if let s = store.statsSnapshot {
                ActivityBarRow(buckets: s.activityBuckets, labels: s.activityBucketLabels)
            } else {
                Text("Sign in and refresh to load activity.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.meta)
            }
        }
        .padding(14)
        .background(Theme.surface(colorScheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline(colorScheme), lineWidth: 0.5))
    }

    @ViewBuilder
    private var bottomRows: some View {
        let s = store.statsSnapshot
        VStack(spacing: 10) {
            PaceBanner(
                title: "Avg merge time",
                subtitle: "Your merged PRs · open → merge",
                value: formatMergeMinutes(s?.avgMergeMinutes),
                rightText: mergeTrendText(s),
                icon: .timer,
                rightPositiveGreen: (s?.avgMergePercentVsPrior ?? 1) <= 0
            )
            PaceBanner(
                title: "Commit streak",
                subtitle: nil,
                value: s.map { "\($0.commitStreakDays) days" } ?? "—",
                rightText: nil,
                icon: .flame,
                streakDots: s?.lastSevenDaysCommitted
            )
        }
        .opacity(store.statsLoading ? 0.55 : 1)
    }

    private func formatMergeMinutes(_ m: Int?) -> String {
        guard let m else { return "—" }
        if m < 60 { return "\(m)m" }
        let h = m / 60
        let r = m % 60
        return r == 0 ? "\(h)h" : "\(h)h \(r)m"
    }

    private func mergeTrendText(_ s: StatsSnapshot?) -> String? {
        guard let p = s?.avgMergePercentVsPrior else { return nil }
        return String(format: "%+.0f%% vs prior", p)
    }
}

// MARK: - Tiles

private struct PaceTile: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: String
    let trend: Int?
    let icon: LucideRepoIcon
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                LucideRepoIconView(icon: icon, size: 13, color: tint)
                    .frame(width: 22, height: 22)
                    .background(tint.opacity(0.14), in: Circle())
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.35)
                    .foregroundStyle(.secondary)
                Spacer()
                CountTrend(delta: trend)
            }
            Text(value)
                .font(.system(size: 28, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface(colorScheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline(colorScheme), lineWidth: 0.5))
    }
}

private struct CountTrend: View {
    let delta: Int?

    var body: some View {
        Group {
            if let d = delta {
                if d == 0 {
                    Text("—")
                        .foregroundStyle(Theme.faint)
                } else if d > 0 {
                    Text("↑ \(d)")
                        .foregroundStyle(Theme.green)
                } else {
                    Text("↓ \(-d)")
                        .foregroundStyle(Theme.red)
                }
            } else {
                Text("—")
                    .foregroundStyle(Theme.faint)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .monospacedDigit()
    }
}

// MARK: - Activity

private struct ActivityBarRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let buckets: [Int]
    let labels: [String]

    private var maxBar: CGFloat {
        let m = buckets.max() ?? 0
        return CGFloat(max(m, 1))
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(buckets.enumerated()), id: \.offset) { i, v in
                let h = 22 + CGFloat(v) / maxBar * 44
                VStack(spacing: 5) {
                    Text("\(v)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(height: 14)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(i == buckets.count - 1 ? Theme.mint : Theme.barInactive(colorScheme))
                        .frame(width: 26, height: h)
                    Text(label(at: i))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.meta)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 4)
    }

    private func label(at i: Int) -> String {
        guard i >= 0, i < labels.count else { return "" }
        return labels[i]
    }
}

// MARK: - Banners

private struct PaceBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String?
    let value: String
    let rightText: String?
    let icon: LucideRepoIcon
    var rightPositiveGreen: Bool = true
    var streakDots: [Bool]?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            LucideRepoIconView(icon: icon, size: 18, color: Theme.amber)
                .frame(width: 36, height: 36)
                .background(Theme.amber.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.meta)
                }
                Text(value)
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            if let streakDots {
                HStack(spacing: 5) {
                    ForEach(Array(streakDots.enumerated()), id: \.offset) { _, on in
                        Circle()
                            .fill(on ? Theme.amber : Theme.barInactive(colorScheme))
                            .frame(width: 8, height: 8)
                    }
                }
            } else if let rightText {
                Text(rightText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(rightPositiveGreen ? Theme.green : Theme.red)
            }
        }
        .padding(14)
        .background(Theme.surface(colorScheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline(colorScheme), lineWidth: 0.5))
    }
}
