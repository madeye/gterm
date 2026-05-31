import SwiftUI

/// Full-screen in-app browser cover wrapping a `WKWebView` (via
/// `WebViewRepresentable`) with an address bar, reload/stop control, a linear
/// progress indicator, and bottom-bar back/forward navigation. Opened from the
/// port-forward status sheet to load `http://127.0.0.1:<localPort>`, which the
/// kernel loopback hands to the NIO listener that tunnels it over SSH.
struct BrowserScreen: View {
    let initialURL: URL
    let onClose: () -> Void

    @StateObject private var model = WebViewModel()
    @State private var urlText: String

    init(initialURL: URL, onClose: @escaping () -> Void) {
        self.initialURL = initialURL
        self.onClose = onClose
        _urlText = State(initialValue: initialURL.absoluteString)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                if model.isLoading {
                    ProgressView(value: model.progress)
                        .progressViewStyle(.linear)
                }
                ZStack {
                    WebViewRepresentable(model: model)
                    if let error = model.lastError {
                        ContentUnavailableView(
                            label: {
                                Label("Can't Open Page", systemImage: "wifi.exclamationmark")
                            },
                            description: { Text(error) },
                            actions: {
                                Button("Retry") { model.reload() }
                            }
                        )
                        .background(.background)
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { model.goBack() } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!model.canGoBack)
                    Spacer()
                    Button { model.goForward() } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!model.canGoForward)
                }
            }
        }
        .onAppear { model.load(initialURL) }
        .onChange(of: model.url) { _, newValue in
            if let newValue { urlText = newValue.absoluteString }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }
            TextField("address", text: $urlText)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.go)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if let url = normalized(urlText) { model.load(url) }
                }
            Button {
                if model.isLoading {
                    model.stop()
                } else {
                    model.reload()
                }
            } label: {
                Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// If the typed string lacks a scheme, prepend `http://` before loading.
    private func normalized(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") {
            return URL(string: trimmed)
        }
        return URL(string: "http://\(trimmed)")
    }
}
