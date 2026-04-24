import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var store: Store
    let onClose: () -> Void

    @State private var tokenField: String = ""
    @State private var tokenVisible = false
    @AppStorage("gitbar.notify.reviewRequests") private var notifyReviews = true
    @AppStorage("gitbar.notify.ci") private var notifyCI = true
    @AppStorage("gitbar.notify.changesRequested") private var notifyChangesRequested = true
    @AppStorage("gitbar.refreshInterval") private var refreshInterval = "60s"
    @AppStorage(ThemeMode.storageKey) private var appearanceMode = ThemeMode.dark.rawValue
    @State private var launchAtLogin = false

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
                Text("Gitbar 0.1.1 · Built for the menu bar")
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
