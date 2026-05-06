import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var store: Store
    let onClose: () -> Void

    @State private var tokenField: String = ""
    @State private var tokenVisible = false
    @State private var showCLISignIn = false
    @State private var cliBusy = false
    @AppStorage("gitbar.notify.reviewRequests") private var notifyReviews = true
    @AppStorage("gitbar.notify.ci") private var notifyCI = true
    @AppStorage("gitbar.notify.changesRequested") private var notifyChangesRequested = true
    @AppStorage("gitbar.refreshInterval") private var refreshInterval = "60s"
    @AppStorage(TerminalApp.userDefaultsKey) private var aiReviewTerminal = ""
    @AppStorage(ThemeMode.storageKey) private var appearanceMode = ThemeMode.dark.rawValue
    @AppStorage(PanelTab.all.hiddenStorageKey)    private var hideAll = false
    @AppStorage(PanelTab.mine.hiddenStorageKey)   private var hideMine = false
    @AppStorage(PanelTab.review.hiddenStorageKey) private var hideReview = false
    @AppStorage(PanelTab.issues.hiddenStorageKey) private var hideIssues = false
    @AppStorage(PanelTab.stats.hiddenStorageKey)  private var hideStats = false
    @State private var launchAtLogin = false

    private var visibleTabCount: Int {
        [hideAll, hideMine, hideReview, hideIssues, hideStats].filter { !$0 }.count
    }

    private var installedTerminalsSorted: [TerminalApp] {
        TerminalApp.allCases.filter { store.installedTerminals.contains($0) }
    }

    /// The terminal we'd actually launch given the current selection. Mirrors
    /// `TerminalApp.effective` but reads from `@AppStorage` so the subtitle
    /// updates as the user picks.
    private var effectiveTerminal: TerminalApp {
        let chosen = TerminalApp(rawValue: aiReviewTerminal) ?? .terminal
        return store.installedTerminals.contains(chosen) ? chosen : .terminal
    }

    /// Classic PAT: pre-fills note + **repo** scope (pull requests, issues, metadata on repos you can access).
    private static let newClassicTokenURL: URL = {
        var c = URLComponents(string: "https://github.com/settings/tokens/new")!
        c.queryItems = [
            URLQueryItem(name: "description", value: "Gitbar"),
            URLQueryItem(name: "scopes", value: "repo"),
        ]
        return c.url!
    }()

    /// Fine-grained PAT: opens the create flow; pick **All repositories** (or selected), then Pull requests, Issues, Metadata — Read.
    private static let newFineGrainedTokenURL: URL = {
        var c = URLComponents(string: "https://github.com/settings/personal-access-tokens/new")!
        c.queryItems = [
            URLQueryItem(name: "name", value: "Gitbar"),
            URLQueryItem(name: "description", value: "Gitbar menu bar app"),
        ]
        return c.url!
    }()

    var body: some View {
        Form {
            Section("Account") {
                HStack(spacing: 12) {
                    let login = store.myLogin ?? "—"
                    accountAvatar(login: login)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(login).font(.system(size: 13, weight: .semibold))
                        Text("@\(login)")
                            .font(Theme.mono)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.hasToken {
                        Button("Remove") {
                            store.updateToken("")
                            tokenField = ""
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Section("Personal access token") {
                ghCLIRow

                HStack(spacing: 6) {
                    TokenField(
                        text: $tokenField,
                        isSecure: !tokenVisible,
                        placeholder: "ghp_… or github_pat_…"
                    )
                    .id(tokenVisible)
                    .frame(maxWidth: .infinity)
                    .frame(height: 22)

                    Button {
                        tokenVisible.toggle()
                    } label: {
                        Image(systemName: tokenVisible ? "eye.slash" : "eye")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(tokenVisible ? "Hide token" : "Show token")

                    Button("Save") { store.updateToken(tokenField) }
                        .buttonStyle(.borderedProminent)
                        .disabled(tokenField.isEmpty || tokenField == store.token)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Required scopes")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.meta)
                    scopeRow("Pull requests", desc: "Read and write")
                    scopeRow("Issues", desc: "Read")
                    scopeRow("Metadata", desc: "Read")
                }
                .padding(.top, 2)

                HStack(spacing: 12) {
                    Link("Create classic token", destination: Self.newClassicTokenURL)
                        .font(.system(size: 11.5, weight: .medium))
                        .tint(Theme.blue)
                    Text("·")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.faint)
                    Link("Create fine-grained token", destination: Self.newFineGrainedTokenURL)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.top, 2)

                Text("Gitbar only sees what this token can access. Classic tokens need the `repo` scope; fine-grained tokens need pull-request / issues / metadata read access.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Notifications") {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.blue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Coming soon — working on it :D")
                            .font(.system(size: 12, weight: .medium))
                        Text("Native macOS notifications for review requests, CI failures, and change requests.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }

            Section("Tabs") {
                tabToggle(.all,    hidden: $hideAll)
                tabToggle(.mine,   hidden: $hideMine)
                tabToggle(.review, hidden: $hideReview)
                tabToggle(.issues, hidden: $hideIssues)
                tabToggle(.stats,  hidden: $hideStats)
            }

            Section("Behavior") {
                Toggle(isOn: $launchAtLogin) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Launch at login")
                        Text("Start Gitbar automatically when you sign in")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: launchAtLogin) { _, new in
                    try? LaunchAtLogin.setEnabled(new)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Refresh interval")
                        Text("How often to poll GitHub for changes")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $refreshInterval) {
                        Text("30s").tag("30s")
                        Text("60s").tag("60s")
                        Text("5m").tag("5m")
                        Text("Manual").tag("manual")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                }
                .onChange(of: refreshInterval) { _, _ in
                    store.reconfigurePollingFromDefaults()
                }
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Appearance")
                        Text("Match macOS or force a specific theme")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $appearanceMode) {
                        ForEach(ThemeMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                }
                .onChange(of: appearanceMode) { _, new in
                    ThemeMode.apply(ThemeMode(rawValue: new) ?? .system)
                }

                if store.aiReviewers.any {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("AI review terminal")
                            Text("Opens in \(effectiveTerminal.displayName)")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $aiReviewTerminal) {
                            Text("System default").tag("")
                            ForEach(installedTerminalsSorted) { app in
                                Text(app.displayName).tag(app.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }
                }
            }

            Section("App") {
                Button("Quit Gitbar") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: [.command])

                Link(destination: URL(string: "https://github.com/brunokiafuka/gitbar/issues/new")!) {
                    HStack(spacing: 6) {
                        Text("🐛")
                            .font(.system(size: 12))
                        Text("Is it buggy? 😖 Open an issue here")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.link)
            }

            Section {
                Text("Gitbar 0.2.2 · Built for the menu bar")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 640)
        .onAppear {
            tokenField = store.token ?? ""
            launchAtLogin = LaunchAtLogin.isEnabled
        }
        .task {
            await store.refreshGHCLIStatus()
            await store.refreshAIReviewers()
            store.refreshInstalledTerminals()
        }
        .sheet(isPresented: $showCLISignIn) {
            CLISignInView(onClose: {
                showCLISignIn = false
                tokenField = store.token ?? ""
            })
            .environmentObject(store)
        }
    }

    @ViewBuilder
    private var ghCLIRow: some View {
        switch store.ghCLIStatus {
        case .notInstalled:
            HStack(spacing: 10) {
                Image(systemName: "terminal")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.faint)
                    .frame(width: 22, height: 22)
                    .background(Theme.faint.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 1) {
                    Text("GitHub CLI not detected")
                        .font(.system(size: 12, weight: .medium))
                    Text("Install `gh` to skip the manual token paste.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Link("Install", destination: URL(string: "https://cli.github.com")!)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .padding(.vertical, 2)
        case .authed:
            HStack(spacing: 10) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.green)
                    .frame(width: 22, height: 22)
                    .background(Theme.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 1) {
                    Text("GitHub CLI signed in")
                        .font(.system(size: 12, weight: .medium))
                    Text("Import the token gh manages for you.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(cliBusy ? "Importing…" : "Import token") {
                    cliBusy = true
                    Task {
                        let ok = await store.importTokenFromGHCLI()
                        cliBusy = false
                        if ok {
                            tokenField = store.token ?? ""
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(cliBusy)
            }
            .padding(.vertical, 2)
        case .installedNotAuthed:
            HStack(spacing: 10) {
                Image(systemName: "terminal")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.amber)
                    .frame(width: 22, height: 22)
                    .background(Theme.amber.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 1) {
                    Text("GitHub CLI detected")
                        .font(.system(size: 12, weight: .medium))
                    Text("Not signed in to gh yet — we'll guide you through it.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Sign in via gh") {
                    showCLISignIn = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.vertical, 2)
        }

        if let err = store.ghCLIErrorMessage {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.amber)
                Text(err)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(.vertical, 2)
        }
    }

    private func tabToggle(_ tab: PanelTab, hidden: Binding<Bool>) -> some View {
        let show = Binding<Bool>(
            get: { !hidden.wrappedValue },
            set: { hidden.wrappedValue = !$0 }
        )
        let isLastVisible = !hidden.wrappedValue && visibleTabCount == 1
        return Toggle(isOn: show) {
            VStack(alignment: .leading, spacing: 1) {
                Text(tab.label)
                Text(tabSubtitle(for: tab))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(isLastVisible)
        .help(isLastVisible ? "At least one tab must remain visible." : "")
    }

    private func tabSubtitle(for tab: PanelTab) -> String {
        switch tab {
        case .all:    return "Combined overview of every queue"
        case .mine:   return "Pull requests you authored"
        case .review: return "Pull requests awaiting your review"
        case .issues: return "Issues assigned to you"
        case .stats:  return "Activity overview"
        }
    }

    @ViewBuilder
    private func accountAvatar(login: String) -> some View {
        let initials = String(login.prefix(2)).uppercased()
        Group {
            if let url = store.avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        accountAvatarPlaceholder(initials: initials)
                    case .empty:
                        ProgressView()
                            .frame(width: 36, height: 36)
                    @unknown default:
                        accountAvatarPlaceholder(initials: initials)
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            } else {
                accountAvatarPlaceholder(initials: initials)
            }
        }
    }

    private func accountAvatarPlaceholder(initials: String) -> some View {
        Text(initials)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(
                LinearGradient(
                    colors: [Theme.blue, Theme.lilac],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: Circle()
            )
    }


    private func scopeRow(_ name: String, desc: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.green)
                .frame(width: 18, height: 18)
                .background(Theme.green.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
            Text(name).font(Theme.mono)
            Text(desc).font(.system(size: 11.5)).foregroundStyle(.secondary)
            Spacer()
        }
    }
}
