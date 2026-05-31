import Foundation
import SwiftUI
import WebKit

/// Observable model wrapping a single `WKWebView`, exposing navigation state to
/// SwiftUI chrome (address bar, progress, back/forward, errors).
final class WebViewModel: ObservableObject {
    @Published var url: URL?
    @Published var title: String = ""
    @Published var progress: Double = 0
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var lastError: String?

    let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())

    func load(_ u: URL) {
        lastError = nil
        webView.load(URLRequest(url: u))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    func reload() {
        lastError = nil
        webView.reload()
    }

    func stop() {
        webView.stopLoading()
        isLoading = false
    }
}

/// Bridges the model's `WKWebView` into SwiftUI and wires up navigation + KVO.
struct WebViewRepresentable: UIViewRepresentable {
    @ObservedObject var model: WebViewModel

    func makeUIView(context: Context) -> WKWebView {
        let webView = model.webView
        webView.navigationDelegate = context.coordinator
        context.coordinator.observe(webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // no-op: navigation is driven imperatively through the model.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let model: WebViewModel
        // NSKeyValueObservation tokens auto-invalidate on deinit, avoiding the
        // manual removeObserver footgun.
        private var observations: [NSKeyValueObservation] = []

        init(model: WebViewModel) {
            self.model = model
        }

        func observe(_ webView: WKWebView) {
            observations = [
                webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                    DispatchQueue.main.async { self?.model.progress = wv.estimatedProgress }
                },
                webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in
                    DispatchQueue.main.async { self?.model.canGoBack = wv.canGoBack }
                },
                webView.observe(\.canGoForward, options: [.new]) { [weak self] wv, _ in
                    DispatchQueue.main.async { self?.model.canGoForward = wv.canGoForward }
                },
                webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
                    DispatchQueue.main.async { self?.model.title = wv.title ?? "" }
                },
                webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
                    DispatchQueue.main.async { self?.model.url = wv.url }
                },
            ]
        }

        deinit {
            observations.forEach { $0.invalidate() }
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.model.isLoading = true
                self.model.lastError = nil
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.model.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.model.isLoading = false
                self.model.lastError = error.localizedDescription
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.model.isLoading = false
                self.model.lastError = error.localizedDescription
            }
        }
    }
}

/// If `string` lacks a URL scheme, prepend `http://`. Used by the address bar.
func normalized(_ string: String) -> URL? {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.contains("://") {
        return URL(string: trimmed)
    }
    return URL(string: "http://\(trimmed)")
}
