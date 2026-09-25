import SwiftUI
import AppKit

/// Flip's grain: one sheet of photographic noise tiled across every surface,
/// so panels read as a material rather than as flat fills.
///
/// Drawn source-over with no blend mode. The artwork is an alpha-keyed speckle
/// holding both darker and lighter grains; over these dark surfaces a blend
/// mode such as overlay crushes the light grains, so drawing it plainly is what
/// keeps its balance. (Flip's `Grain.swift` has the measurements.)
public enum Grain {
    /// The sheet was drawn at 2x.
    private static let assetScale: CGFloat = 2

    @MainActor public static let image: NSImage? = {
        guard let url = Bundle.module.url(forResource: "grain", withExtension: "png", subdirectory: "Textures"),
              let image = NSImage(contentsOf: url),
              let pixels = image.representations.first else { return nil }
        image.size = NSSize(width: CGFloat(pixels.pixelsWide) / assetScale,
                            height: CGFloat(pixels.pixelsHigh) / assetScale)
        return image
    }()
}

extension View {
    /// Lays the grain over this view's area. Apply it to a background shape,
    /// not to a finished panel, or the grain runs over the labels as well.
    public func grained(_ strength: Double = Theme.grain) -> some View {
        overlay(GrainOverlay(strength: strength))
    }
}

private struct GrainOverlay: View {
    let strength: Double

    var body: some View {
        if let image = Grain.image {
            // Tiled by hand: `resizingMode: .tile` draws nothing for an image
            // whose point size differs from its pixel size, and a Canvas pins
            // the tiles to the top-left so the grain does not crawl when the
            // surface changes height.
            Canvas { context, size in
                let tile = context.resolve(Image(nsImage: image))
                var y: CGFloat = 0
                while y < size.height {
                    var x: CGFloat = 0
                    while x < size.width {
                        context.draw(tile, in: CGRect(origin: CGPoint(x: x, y: y), size: tile.size))
                        x += tile.size.width
                    }
                    y += tile.size.height
                }
            }
            .opacity(strength)
            .allowsHitTesting(false)
        }
    }
}
