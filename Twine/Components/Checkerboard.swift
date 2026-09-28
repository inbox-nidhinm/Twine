import SwiftUI
import Theme

/// The pattern that stands for transparency.
struct Checkerboard: View {
    var cell: CGFloat = Theme.checkerCell

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.checkerDark))
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : cell
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)), with: .color(Theme.checkerLight))
                    x += cell * 2
                }
                y += cell
                row += 1
            }
        }
    }
}
