import SwiftUI

/// The Collect tab's label: a peer of the other three, but an action.
///
/// Colour is the whole point of this control, and a tab bar templates its
/// icons — it recolours them to match selection state and ignores what the
/// view asked for. `.alwaysOriginal` is the documented opt-out: the image
/// carries its own colour and the bar leaves it alone.
struct CollectTabLabel: View {
    let state: LoggingCoordinator.CollectionState
    let isEnabled: Bool

    var body: some View {
        Label {
            // Deliberately constant. A label that changed to "Collecting…"
            // would resize the tab and shove its neighbours sideways every
            // time it was pressed.
            Text("Collect")
        } icon: {
            Image(uiImage: tinted)
        }
    }

    private var tinted: UIImage {
        let symbol = UIImage(systemName: icon) ?? UIImage()
        return symbol.withTintColor(colour, renderingMode: .alwaysOriginal)
    }

    private var icon: String {
        switch state {
        case .idle: "arrow.down.circle"
        case .collecting: "circle.dotted"
        case .finished: "checkmark.circle.fill"
        }
    }

    private var colour: UIColor {
        switch state {
        case .idle: isEnabled ? .label : .tertiaryLabel
        case .collecting: .systemRed
        case .finished: .systemGreen
        }
    }
}
