import SwiftUI
import WebKit

/// Logged-in YouTube web view. The user browses their home/feed/recommendations here.
/// When the web view navigates to a video, we hand the id to the native player instead of
/// letting YouTube render the watch page with its full chrome.
///
/// Detection is layered so it never misses a video, however it was opened:
///  1. `decidePolicyFor` — catches full-page navigations (typed URLs, target=_blank). We can
///     cancel them before the watch page even loads.
///  2. KVO on `url` — catches YouTube's in-app SPA navigations (history.pushState), which don't
///     trigger the navigation delegate. This is the robust catch-all.
///  3. JS click interception — best-effort, stops the click before navigation to avoid any flash.
struct BrowseView: NSViewRepresentable {
    @EnvironmentObject var model: AppModel

    // Safari macOS UA — avoids Google's "this browser may not be secure" block on login.
    private static let safariUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "openVideo")
        controller.addUserScript(
            WKUserScript(source: Self.interceptJS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // persistent → login survives relaunches
        config.userContentController = controller
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = Self.safariUA
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        model.webView = webView

        // Robust catch-all: observe the URL for SPA navigations (pushState) the delegate misses.
        context.coordinator.observation = webView.observe(\.url, options: [.new]) { [weak coordinator = context.coordinator] webView, _ in
            coordinator?.handlePotentialVideo(url: webView.url, from: webView, restoreFeed: true)
        }

        webView.load(URLRequest(url: URL(string: "https://www.youtube.com")!))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let model: AppModel
        var observation: NSKeyValueObservation?
        init(model: AppModel) { self.model = model }
        deinit { observation?.invalidate() }

        /// Switches to the native player if `url` is a video and we're currently browsing.
        /// `restoreFeed` makes the (now hidden) web view step back so the feed is intact on return.
        func handlePotentialVideo(url: URL?, from webView: WKWebView?, restoreFeed: Bool) {
            guard let url, let id = YouTubeURL.videoID(from: url) else { return }
            Task { @MainActor in
                guard self.model.mode == .browse else { return }
                self.model.play(videoID: id)
                if restoreFeed, webView?.canGoBack == true {
                    webView?.goBack()
                }
            }
        }

        // Full-page navigations to a video: cancel and play natively (avoids loading the watch page).
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if (navigationAction.targetFrame?.isMainFrame ?? true),
               let url = navigationAction.request.url,
               YouTubeURL.videoID(from: url) != nil,
               webView.url != nil {  // not the very first load
                decisionHandler(.cancel)
                handlePotentialVideo(url: url, from: webView, restoreFeed: false)
                return
            }
            decisionHandler(.allow)
        }

        // Best-effort click interception (no flash when it works).
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let href = message.body as? String,
                  let id = YouTubeURL.videoID(from: href) else { return }
            Task { @MainActor in
                guard self.model.mode == .browse else { return }
                self.model.play(videoID: id)
            }
        }
    }

    private static let interceptJS = """
    (function(){
      if (window.__sp_installed) return; window.__sp_installed = true;
      function vid(href){
        try {
          var u = new URL(href, location.href);
          if (u.hostname.indexOf('youtu.be') >= 0) { var s = u.pathname.slice(1); return s || null; }
          if (u.pathname === '/watch') { return u.searchParams.get('v'); }
          var parts = u.pathname.split('/').filter(Boolean);
          if (parts.length >= 2 && (parts[0]==='shorts'||parts[0]==='embed'||parts[0]==='live')) return parts[1];
        } catch(e){}
        return null;
      }
      document.addEventListener('click', function(e){
        var a = e.target.closest && e.target.closest('a[href]');
        if (!a) return;
        if (vid(a.href)) {
          e.preventDefault(); e.stopPropagation();
          try { window.webkit.messageHandlers.openVideo.postMessage(a.href); } catch(err){}
        }
      }, true);
    })();
    """
}
