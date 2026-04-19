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
                Text("Classic (ghp_…) and fine-grained (github_pat_…) tokens both work. Grant access to every repo you care about, or All repositories.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .center, spacing: 8) {
                    TokenField(
                        text: $tokenField,
                        isSecure: !tokenVisible,
                        placeholder: "ghp_… or github_pat_…"
                    )
                    .id(tokenVisible)
                    .frame(maxWidth: .infinity)
                    .frame(height: 22)

                    Button("Paste") {
                        if let s = NSPasteboard.general.string(forType: .string) {
                            tokenField = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    .help("Insert token from clipboard")

                    Button(tokenVisible ? "Hide" : "Show") { tokenVisible.toggle() }
                    Button("Save") { store.updateToken(tokenField) }
                        .buttonStyle(.borderedProminent)
                        .disabled(tokenField.isEmpty)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Required permissions")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Classic: enable the repo scope. Fine-grained: under Repository permissions, set at least:")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.meta)
                    scopeRow("Pull requests", desc: "Read and write (merge your PRs)")
                    scopeRow("Issues", desc: "Read (assigned issues)")
                    scopeRow("Metadata", desc: "Read (required for API access)")
                }
                .padding(.top, 2)

                tokenNotice
            }

            Section("Notifications") {
                Toggle(isOn: $notifyReviews) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Review requests")
                        Text("Badge the menu bar icon when someone requests your review")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $notifyCI) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("CI failures")
                        Text("Notify when CI fails on your PRs")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $notifyChangesRequested) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("PR needs changes")
                        Text("Badge the menu bar icon when a reviewer requests changes on your PR")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
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
            }

            Section("App") {
                Button("Quit Gitbar") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: [.command])
            }

            Section {
                Text("Gitbar 0.1.0 · Built for the menu bar")
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

    private var tokenNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.amber)
            VStack(alignment: .leading, spacing: 6) {
                Text("Everything Gitbar sees is scoped to this token. Create, view, or rotate tokens on GitHub.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.primary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                Link(destination: Self.newClassicTokenURL) {
                    HStack(spacing: 6) {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 11))
                        Text("Create classic token (repo scope)")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                }
                .buttonStyle(.link)
                .tint(Theme.blue)
                Link(destination: Self.newFineGrainedTokenURL) {
                    Text("Create fine-grained token")
                        .font(.system(size: 11))
                }
                .buttonStyle(.link)
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.amber.opacity(0.22), lineWidth: 0.5)
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
