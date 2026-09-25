import SwiftUI
import MotionModel
import Theme

/// The composition frame, fitted into the part of the window the panels
/// leave free. Anything outside the frame is not drawn.
///
/// A stand-in for milestone 1. Milestone 3 replaces this with an `NSView` that
/// hosts the Core Animation renderer and handles selection, zoom and pan.
struct CanvasView: View {
    let composition: Composition
    let insets: EdgeInsets

    /// Breathing room between the fitted frame and whatever covers the canvas.
    private let margin: CGFloat = 32

    var body: some View {
        GeometryReader { geo in
            let frame = fittedFrame(in: geo.size)
            ZStack(alignment: .topLeading) {
                Theme.canvas.grained()
                background
                    .frame(width: frame.width, height: frame.height)
                    .overlay(Rectangle().strokeBorder(Theme.edge, lineWidth: 1))
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
    }

    @ViewBuilder private var background: some View {
        if composition.background.isTransparent {
            Checkerboard()
        } else {
            Rectangle().fill(composition.background.color.opaque)
        }
    }

    private func fittedFrame(in size: CGSize) -> CGRect {
        let area = CGRect(x: insets.leading + margin, y: insets.top + margin,
                          width: max(size.width - insets.leading - insets.trailing - margin * 2, 40),
                          height: max(size.height - insets.top - insets.bottom - margin * 2, 40))
        let w = CGFloat(composition.width), h = CGFloat(composition.height)
        let scale = min(area.width / w, area.height / h)
        let fitted = CGSize(width: w * scale, height: h * scale)
        return CGRect(x: area.midX - fitted.width / 2, y: area.midY - fitted.height / 2,
                      width: fitted.width, height: fitted.height)
    }
}

/// The pattern that stands for transparency.
struct Checkerboard: View {
    var cell: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.42)))
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : cell
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)), with: .color(Color(white: 0.52)))
                    x += cell * 2
                }
                y += cell
                row += 1
            }
        }
    }
}
