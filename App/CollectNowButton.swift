import SwiftUI
import GlasshouseCore

/// Takes a reading of every enabled signal, on demand.
///
/// Sits above the tab bar rather than in it: SwiftUI tabs cannot act as
/// buttons, and tab items cannot be individually tinted, so the colour states
/// would be impossible there.
///
/// Carries no outer padding — `CollectNowPlacement` decides that, because the
/// iOS 26 accessory slot provides its own container and the iOS 18 inset does
/// not.
struct CollectNowButton: View {
    let logging: LoggingCoordinator

    var body: some View {
        Button {
            Task { await logging.collectNow() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .symbolEffect(.pulse, isActive: isCollecting)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isCollecting || !logging.policies.isAnythingEnabled)
        // Colour is the whole signal here, so it is worth animating properly:
        // an instant snap from red to green reads as a glitch rather than as
        // progress.
        .animation(.easeInOut(duration: 0.45), value: logging.collection)
    }

    private var isCollecting: Bool { logging.collection == .collecting }

    private var title: String {
        switch logging.collection {
        case .idle:
            logging.policies.isAnythingEnabled
                ? "Collect now"
                : "Nothing is being recorded"
        case .collecting:
            "Collecting…"
        case let .finished(recorded):
            recorded == 0 ? "Nothing new to record" : "Recorded \(recorded)"
        }
    }

    private var icon: String {
        switch logging.collection {
        case .idle: "arrow.down.circle"
        case .collecting: "circle.dotted"
        case .finished: "checkmark.circle.fill"
        }
    }

    private var background: Color {
        switch logging.collection {
        case .idle: Color(.secondarySystemBackground)
        case .collecting: .red
        case .finished: .green
        }
    }

    private var foreground: Color {
        switch logging.collection {
        case .idle: logging.policies.isAnythingEnabled ? .primary : .secondary
        case .collecting, .finished: .white
        }
    }
}
