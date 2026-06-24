import SwiftUI
import WebKit

enum Mode {
    case browse
    case player
}

/// Central app state shared between the browse (WKWebView) and player (AVPlayer) modes.
@MainActor
final class AppModel: ObservableObject {
    @Published var mode: Mode = .browse
    @Published var currentVideoID: String?
    @Published var showURLBar: Bool = false

    /// Reference to the live WKWebView so we can read its cookies and pause its media.
    weak var webView: WKWebView?

    func play(videoID: String) {
        // Stop any media playing inside the (about-to-be-hidden) web view.
        webView?.evaluateJavaScript(
            "document.querySelectorAll('video').forEach(function(v){v.pause();});",
            completionHandler: nil
        )
        currentVideoID = videoID
        withAnimation(.easeInOut(duration: 0.2)) {
            mode = .player
        }
    }

    func backToBrowse() {
        withAnimation(.easeInOut(duration: 0.2)) {
            mode = .browse
        }
        currentVideoID = nil
    }
}

/// Parses YouTube URLs into a bare video id. Handles watch, youtu.be, shorts, embed, live.
enum YouTubeURL {
    static func videoID(from string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }
        return videoID(from: url)
    }

    static func videoID(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""

        if host.contains("youtu.be") {
            let id = url.pathComponents.first(where: { $0 != "/" && !$0.isEmpty })
            return id?.isEmpty == false ? id : nil
        }

        guard host.contains("youtube.com") else { return nil }

        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        if let first = parts.first,
           ["shorts", "embed", "live"].contains(first),
           parts.count >= 2 {
            return parts[1]
        }

        if url.path == "/watch" {
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            return comps?.queryItems?.first(where: { $0.name == "v" })?.value
        }

        return nil
    }
}
