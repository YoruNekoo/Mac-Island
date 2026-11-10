import SwiftUI

/// Notch silhouette: square top corners, rounded bottom corners. Never a capsule.
struct IslandShape: Shape {
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radii = RectangleCornerRadii(topLeading: 0,
                                         bottomLeading: bottomRadius,
                                         bottomTrailing: bottomRadius,
                                         topTrailing: 0)
        return UnevenRoundedRectangle(cornerRadii: radii, style: .continuous).path(in: rect)
    }
}
