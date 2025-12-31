import SwiftUI

// MARK: - Connection Status View

struct ConnectionStatusView: View {
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(colorForStatus)
                .frame(width: 8, height: 8)

            Text(status.displayText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var colorForStatus: Color {
        switch status {
        case .connected:
            return .green
        case .connecting:
            return .yellow
        case .disconnected:
            return .gray
        case .error:
            return .red
        }
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Error Alert Modifier

struct ErrorAlertModifier: ViewModifier {
    @Binding var error: AppError?

    func body(content: Content) -> some View {
        content
            .alert(
                error?.title ?? "Error",
                isPresented: Binding(
                    get: { error != nil },
                    set: { if !$0 { error = nil } }
                )
            ) {
                Button("OK") {
                    error = nil
                }
            } message: {
                if let error = error {
                    Text(error.message)
                }
            }
    }
}

extension View {
    func errorAlert(_ error: Binding<AppError?>) -> some View {
        modifier(ErrorAlertModifier(error: error))
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)

                Text(message)
                    .font(.headline)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .shadow(radius: 10)
            )
        }
    }
}

// MARK: - Toolbar Button Style

struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Color.accentColor.opacity(0.2) : Color.clear)
            )
    }
}

// MARK: - Preview Helpers

#Preview("Connection Status") {
    VStack(spacing: 16) {
        ConnectionStatusView(status: .connected)
        ConnectionStatusView(status: .connecting)
        ConnectionStatusView(status: .disconnected)
        ConnectionStatusView(status: .error("Connection refused"))
    }
    .padding()
}

#Preview("Empty State") {
    EmptyStateView(
        icon: "lightbulb.slash",
        title: "No Devices Found",
        message: "Connect to your Main Repeater to view RA2 devices."
    )
}
