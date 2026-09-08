import SwiftUI

/// Puts the Collect Now button above the tab bar, by whichever route the OS has.
///
/// Split out of the app body because the two placements cannot be expressed as
/// one expression: `tabViewBottomAccessory` exists only from iOS 26, and an
/// `if #available` inside a view builder changes the modifier chain's type.
struct CollectNowPlacement: ViewModifier {
    let logging: LoggingCoordinator

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabViewBottomAccessory {
                CollectNowButton(logging: logging)
            }
        } else {
            content.safeAreaInset(edge: .bottom) {
                CollectNowButton(logging: logging)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
        }
    }
}
