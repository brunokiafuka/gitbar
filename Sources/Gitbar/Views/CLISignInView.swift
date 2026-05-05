import SwiftUI
import AppKit

/// Inline sign-in screen presented as a sheet from the empty-state panel and
/// from Settings. Drives `gh auth login --web`, displays the one-time code,
/// and offers a one-click "Open browser" jump to https://github.com/login/device.
struct CLISignInView: View {
    @EnvironmentObject var store: Store
    @Environment(\.colorScheme) private var scheme
    let onClose: () -> Void

    @StateObject private var model = CLISignInModel()

    var body: some View {
        VStack(spacing: 16) {
            header
            Divider().opacity(0.4)
            content
            footer
        }
        .padding(20)
        .frame(width: 380)
        .background(VisualEffect(material: .popover, blendingMode: .behindWindow))
        .task { await model.start(store: store) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.blue)
                .frame(width: 28, height: 28)
                .background(Theme.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text("Sign in with GitHub CLI")
                    .font(.system(size: 13, weight: .semibold))
                Text("Gitbar will use `gh` to authorize your account.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.cancel()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .detecting:
            phaseRow(systemImage: "ellipsis.circle", title: "Checking GitHub CLI…", showSpinner: true)
        case .needCode:
            needCode
        case .success(let login):
            phaseRow(
                systemImage: "checkmark.circle.fill",
                title: "Signed in as @\(login)",
                tint: Theme.green
            )
        case .error(let message):
            errorState(message: message)
        }
    }

    private var needCode: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("Enter this one-time code")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.meta)
                Text(model.userCode ?? "····-····")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 18)
                    .background(Theme.surface(scheme), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Theme.hairline(scheme), lineWidth: 1)
                    )
            }

            HStack(spacing: 8) {
                Button {
                    if let code = model.userCode {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(code, forType: .string)
                        model.didCopyCode = true
                    }
                } label: {
                    Label(model.didCopyCode ? "Copied" : "Copy code",
                          systemImage: model.didCopyCode ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .disabled(model.userCode == nil)

                Button {
                    if let url = model.verificationURL {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open browser", systemImage: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.verificationURL == nil)
            }

            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Waiting for authorization in your browser…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.amber)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Try again") {
                    Task { await model.restart(store: store) }
                }
                .buttonStyle(.bordered)
                Button("Use a token instead") {
                    onClose()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func phaseRow(
        systemImage: String,
        title: String,
        showSpinner: Bool = false,
        tint: Color = Theme.blue
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 13))
            if showSpinner {
                ProgressView().controlSize(.small)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Text("`gh` runs locally — your credentials never leave your machine.")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.faint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}

@MainActor
final class CLISignInModel: ObservableObject {
    enum Phase: Equatable {
        case detecting
        case needCode
        case success(login: String)
        case error(String)
    }

    @Published var phase: Phase = .detecting
    @Published var userCode: String?
    @Published var verificationURL: URL?
    @Published var didCopyCode = false

    private var loginTask: Task<Void, Never>?

    func start(store: Store) async {
        await refreshAndRoute(store: store)
    }

    func restart(store: Store) async {
        cancel()
        userCode = nil
        verificationURL = nil
        didCopyCode = false
        phase = .detecting
        await refreshAndRoute(store: store)
    }

    func cancel() {
        loginTask?.cancel()
        loginTask = nil
    }

    private func refreshAndRoute(store: Store) async {
        await store.refreshGHCLIStatus()

        switch store.ghCLIStatus {
        case .notInstalled:
            phase = .error("GitHub CLI (gh) is not installed. Install it from https://cli.github.com.")
            return
        case .authed:
            // Already signed in to gh — short-circuit straight to import.
            await importExistingToken(store: store)
        case .installedNotAuthed:
            phase = .needCode
            startDeviceLogin(store: store)
        }
    }

    private func importExistingToken(store: Store) async {
        let ok = await store.importTokenFromGHCLI()
        if ok {
            phase = .success(login: store.viewer?.login ?? store.myLogin ?? "you")
        } else {
            phase = .error(store.ghCLIErrorMessage ?? "Couldn't read the token from `gh`.")
        }
    }

    private func startDeviceLogin(store: Store) {
        loginTask = Task { [weak self] in
            guard let self else { return }
            let stream = GHCLIAuth.deviceLogin()
            do {
                for try await event in stream {
                    if Task.isCancelled { return }
                    switch event {
                    case .userCode(let code):
                        self.userCode = code
                    case .verificationURL(let url):
                        self.verificationURL = url
                    case .completed:
                        await self.importExistingToken(store: store)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled {
                    self.phase = .error(error.localizedDescription)
                }
            }
        }
    }
}
