import Foundation
import WebKit

/// Dumps the web view's YouTube/Google cookies to a Netscape-format cookies.txt so that
/// yt-dlp can resolve personalized, private, age-restricted or members-only videos using
/// the same logged-in session the user browses with.
enum CookieExporter {
    @MainActor
    static func export(from webView: WKWebView?) async -> URL? {
        guard let store = webView?.configuration.websiteDataStore.httpCookieStore else { return nil }

        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }

        let relevant = cookies.filter {
            $0.domain.contains("youtube.com") || $0.domain.contains("google.com")
        }
        guard !relevant.isEmpty else { return nil }

        var lines = ["# Netscape HTTP Cookie File"]
        for c in relevant {
            let includeSubdomains = c.domain.hasPrefix(".") ? "TRUE" : "FALSE"
            let secure = c.isSecure ? "TRUE" : "FALSE"
            let expiry = c.expiresDate.map { String(Int($0.timeIntervalSince1970)) } ?? "0"
            lines.append([c.domain, includeSubdomains, c.path, secure, expiry, c.name, c.value]
                .joined(separator: "\t"))
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("simpleplayer_cookies.txt")
        do {
            try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
