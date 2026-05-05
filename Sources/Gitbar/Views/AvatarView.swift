import SwiftUI
import AppKit

/// Disk + memory cached loader for GitHub user avatars.
///
/// Uses a dedicated `URLCache` under `~/Library/Caches/Gitbar/avatars` for the
/// raw response bytes (URLSession respects HTTP cache headers; GitHub's avatar
/// CDN sets long max-age) plus an in-memory `NSCache` of decoded `NSImage` so
/// re-renders don't redecode PNGs.
@MainActor
final class AvatarCache {
    static let shared = AvatarCache()

    private let memory = NSCache<NSURL, NSImage>()
    private let session: URLSession

    private init() {
        memory.countLimit = 256

        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Gitbar/avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let urlCache = URLCache(
            memoryCapacity: 4 * 1024 * 1024,
            diskCapacity: 64 * 1024 * 1024,
            directory: dir
        )
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = urlCache
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: cfg)
    }

    func image(for url: URL) async -> NSImage? {
        if let cached = memory.object(forKey: url as NSURL) {
            return cached
        }
        guard let (data, _) = try? await session.data(from: url),
              let img = NSImage(data: data) else {
            return nil
        }
        memory.setObject(img, forKey: url as NSURL)
        return img
    }
}

/// Round avatar with a fallback monogram while loading or on failure.
struct AvatarView: View {
    @Environment(\.colorScheme) private var colorScheme
    let url: String?
    let login: String
    var size: CGFloat = 14

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fill)
            } else {
                Text(monogram)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
                    .background(Theme.surfaceHi(colorScheme))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .task(id: url) {
            guard let s = url, let u = URL(string: s) else {
                image = nil
                return
            }
            image = await AvatarCache.shared.image(for: u)
        }
    }

    private var monogram: String {
        String(login.first.map(Character.init) ?? "?").uppercased()
    }
}

/// AppKit-backed tooltip that's more reliable than SwiftUI's `.help()` inside
/// custom layouts (FlowLayout) and Button labels. Drop in as `.tooltip("…")`.
struct ToolTip: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        v.toolTip = text
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.toolTip = text
    }
}

extension View {
    func tooltip(_ text: String) -> some View {
        overlay(ToolTip(text: text))
    }
}
