import Foundation

/// Wraps the `gh` GitHub CLI binary so Gitbar can broker authentication
/// without asking the user to paste a personal access token. Three flows:
///
///   1. `status()` reports whether `gh` is installed and signed in.
///   2. `token()` reads `gh auth token` for an already-signed-in user.
///   3. `deviceLogin()` drives `gh auth login --web` and streams the
///      one-time code + verification URL so SwiftUI can render an
///      inline sign-in screen.
enum GHCLIAuth {
    enum Status: Equatable {
        case notInstalled
        case installedNotAuthed
        case authed(host: String)
    }

    enum DeviceLoginEvent {
        case userCode(String)
        case verificationURL(URL)
        case completed
    }

    enum GHCLIError: LocalizedError {
        case notInstalled
        case notAuthed
        case processFailed(Int32, String)
        case missingScope

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "GitHub CLI (gh) is not installed."
            case .notAuthed:
                return "GitHub CLI is not signed in."
            case .processFailed(let code, let msg):
                let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty
                    ? "gh exited with status \(code)."
                    : "gh: \(trimmed)"
            case .missingScope:
                return "Token is missing the `repo` scope. Run `gh auth refresh -s repo` and try again."
            }
        }
    }

    /// Locate `gh` via login-shell `command -v gh` so Homebrew (Apple Silicon
    /// `/opt/homebrew/bin`, Intel `/usr/local/bin`) and MacPorts paths resolve
    /// even when GUI apps inherit a stripped PATH.
    static func locate() -> URL? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", "command -v gh"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        } catch {
            // Fall through to fixed-path probe.
        }

        for candidate in ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    static func status() async -> Status {
        guard let gh = locate() else { return .notInstalled }
        let result = await runProcess(executable: gh, arguments: ["auth", "status", "--hostname", "github.com"])
        return result.status == 0 ? .authed(host: "github.com") : .installedNotAuthed
    }

    /// Reads `gh auth token --hostname github.com`. Throws if not installed
    /// or not signed in.
    static func token() async throws -> String {
        guard let gh = locate() else { throw GHCLIError.notInstalled }
        let result = await runProcess(executable: gh, arguments: ["auth", "token", "--hostname", "github.com"])
        if result.status != 0 {
            throw GHCLIError.notAuthed
        }
        let token = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty {
            throw GHCLIError.notAuthed
        }
        return token
    }

    /// Reads the gh-managed token and verifies it carries the `repo` scope by
    /// hitting `GET /user`. We don't parse `gh auth status` output (the format
    /// varies by version); a real API call is the source of truth.
    static func tokenWithScopeCheck() async throws -> String {
        let token = try await token()
        var req = URLRequest(url: URL(string: "https://api.github.com/user")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("gitbar/0.1", forHTTPHeaderField: "User-Agent")

        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw GHCLIError.processFailed(-1, "no response from GitHub API")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw GHCLIError.missingScope
        }
        if !(200..<300).contains(http.statusCode) {
            throw GHCLIError.processFailed(Int32(http.statusCode), "GitHub API error")
        }

        // GitHub returns granted scopes in `X-OAuth-Scopes` for classic tokens.
        // Fine-grained PATs lack this header — we trust the 200 OK in that case.
        if let scopes = http.value(forHTTPHeaderField: "X-OAuth-Scopes"),
           !scopes.isEmpty {
            let granted = Set(scopes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            if !granted.contains("repo") && !granted.contains("public_repo") {
                throw GHCLIError.missingScope
            }
        }
        return token
    }

    /// Streaming `gh auth login --web`. Emits the user code and verification
    /// URL as soon as `gh` prints them, then `.completed` when the polling
    /// finishes successfully. Cancel by terminating the underlying stream.
    static func deviceLogin() -> AsyncThrowingStream<DeviceLoginEvent, Error> {
        AsyncThrowingStream { continuation in
            guard let gh = locate() else {
                continuation.finish(throwing: GHCLIError.notInstalled)
                return
            }

            let process = Process()
            process.executableURL = gh
            process.arguments = [
                "auth", "login",
                "--hostname", "github.com",
                "--web",
                "--scopes", "repo",
                "--git-protocol", "https",
            ]

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let stdinPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = stdinPipe

            let state = DeviceLoginParser(continuation: continuation, stdin: stdinPipe.fileHandleForWriting)

            stderrPipe.fileHandleForReading.readabilityHandler = { fh in
                state.feed(fh.availableData)
            }
            stdoutPipe.fileHandleForReading.readabilityHandler = { fh in
                state.feed(fh.availableData)
            }

            process.terminationHandler = { p in
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                if p.terminationStatus == 0 {
                    continuation.yield(.completed)
                    continuation.finish()
                } else {
                    let trailing = state.snapshot()
                    continuation.finish(throwing: GHCLIError.processFailed(p.terminationStatus, trailing))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: error)
                return
            }

            continuation.onTermination = { _ in
                if process.isRunning { process.terminate() }
            }
        }
    }

    private static func runProcess(executable: URL, arguments: [String]) async -> (status: Int32, stdout: String, stderr: String) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = executable
                p.arguments = arguments
                let out = Pipe()
                let err = Pipe()
                p.standardOutput = out
                p.standardError = err
                do {
                    try p.run()
                    p.waitUntilExit()
                    let outData = out.fileHandleForReading.readDataToEndOfFile()
                    let errData = err.fileHandleForReading.readDataToEndOfFile()
                    cont.resume(returning: (
                        p.terminationStatus,
                        String(data: outData, encoding: .utf8) ?? "",
                        String(data: errData, encoding: .utf8) ?? ""
                    ))
                } catch {
                    cont.resume(returning: (-1, "", error.localizedDescription))
                }
            }
        }
    }
}

/// Buffers gh's interleaved stdout/stderr, extracts the first matching
/// user code (`ABCD-1234`) and verification URL, then writes a newline to
/// gh's stdin so it stops waiting on "Press Enter…" and starts polling.
private final class DeviceLoginParser: @unchecked Sendable {
    private let continuation: AsyncThrowingStream<GHCLIAuth.DeviceLoginEvent, Error>.Continuation
    private let stdin: FileHandle
    private let lock = NSLock()
    private var buffer = ""
    private var sawCode = false
    private var sawURL = false
    private var pokedStdin = false

    private static let codeRegex = try! NSRegularExpression(pattern: #"([A-Z0-9]{4}-[A-Z0-9]{4})"#)
    private static let urlRegex = try! NSRegularExpression(pattern: #"https://github\.com/login/device"#)

    init(
        continuation: AsyncThrowingStream<GHCLIAuth.DeviceLoginEvent, Error>.Continuation,
        stdin: FileHandle
    ) {
        self.continuation = continuation
        self.stdin = stdin
    }

    func feed(_ data: Data) {
        guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
        lock.lock()
        buffer.append(chunk)
        let snapshot = buffer
        let alreadySawCode = sawCode
        let alreadySawURL = sawURL
        lock.unlock()

        if !alreadySawCode {
            let range = NSRange(snapshot.startIndex..<snapshot.endIndex, in: snapshot)
            if let match = Self.codeRegex.firstMatch(in: snapshot, range: range),
               let r = Range(match.range(at: 1), in: snapshot) {
                lock.lock(); sawCode = true; lock.unlock()
                continuation.yield(.userCode(String(snapshot[r])))
            }
        }
        if !alreadySawURL {
            let range = NSRange(snapshot.startIndex..<snapshot.endIndex, in: snapshot)
            if let match = Self.urlRegex.firstMatch(in: snapshot, range: range),
               let r = Range(match.range, in: snapshot),
               let url = URL(string: String(snapshot[r])) {
                lock.lock(); sawURL = true; lock.unlock()
                continuation.yield(.verificationURL(url))
            }
        }

        lock.lock()
        let shouldPoke = sawCode && sawURL && !pokedStdin
        if shouldPoke { pokedStdin = true }
        lock.unlock()

        if shouldPoke {
            // Unblock gh's "Press Enter to open …" prompt so it begins polling.
            // We drive the browser ourselves from SwiftUI; gh's own `open`
            // call is a harmless no-op duplicate.
            try? stdin.write(contentsOf: Data("\n".utf8))
            try? stdin.close()
        }
    }

    func snapshot() -> String {
        lock.lock(); defer { lock.unlock() }
        return buffer
    }
}
