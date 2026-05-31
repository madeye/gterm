import SwiftUI

/// Live management sheet opened from the terminal status bar: lists every port
/// forward configured for the active connection, shows its runtime status, lets
/// the user toggle each listener on/off, and opens an in-app browser for web
/// forwards that are currently listening.
struct PortForwardStatusSheet: View {
    /// This connection's persisted forward configs.
    let forwards: [PortForward]
    /// Live runtime status keyed by forward id.
    let statuses: [UUID: PortForwardStatus]
    let onToggle: (PortForward, Bool) -> Void
    let onOpenBrowser: (PortForward) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if forwards.isEmpty {
                    ContentUnavailableView(
                        "No Port Forwards",
                        systemImage: "network",
                        description: Text("Add forwards in the host's settings.")
                    )
                }
                ForEach(forwards) { forward in
                    row(for: forward)
                }
            }
            .navigationTitle("Port Forwards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private func row(for forward: PortForward) -> some View {
        let status = statuses[forward.id] ?? .stopped
        HStack(spacing: 12) {
            statusDot(status)
            VStack(alignment: .leading, spacing: 2) {
                Text(forward.title)
                Text(forward.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if case .failed(let message) = status {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if forward.isWeb, case .listening = status {
                Button {
                    onOpenBrowser(forward)
                } label: {
                    Image(systemName: "globe")
                }
                .buttonStyle(.borderless)
            }
            Toggle("", isOn: Binding(
                get: { if case .listening = status { return true } else { return false } },
                set: { onToggle(forward, $0) }
            ))
            .labelsHidden()
        }
    }

    @ViewBuilder private func statusDot(_ status: PortForwardStatus) -> some View {
        switch status {
        case .stopped:
            Circle().fill(.gray).frame(width: 10, height: 10)
        case .starting:
            ProgressView().controlSize(.small)
        case .listening:
            Circle().fill(.green).frame(width: 10, height: 10)
        case .failed:
            Circle().fill(.red).frame(width: 10, height: 10)
        }
    }
}
