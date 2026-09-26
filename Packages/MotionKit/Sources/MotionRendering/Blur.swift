import Foundation
import QuartzCore
import CoreImage

/// Gaussian blur for layers and for what is behind them.
///
/// Core Image's `CIGaussianBlur`, the public way to blur a layer, draws its
/// result shifted: about 9 px left and down at a radius of 12, more as the
/// radius grows, both on screen and off. And a layer's `backgroundFilters`
/// only see what is behind it when the layer is a direct child of what it
/// covers, which no layer here is, since every layer sits in a container.
///
/// So this uses the two pieces macOS builds its own translucent windows
/// from: Core Animation's `gaussianBlur` filter, which lands exactly where it
/// should, and `CABackdropLayer`, which blurs whatever is behind it however
/// deeply it is nested. Neither is in the public headers. Both are looked up
/// by name, and if either is ever missing, layer blur falls back to Core
/// Image and background blur is left out, rather than anything failing.
enum Blur {
    /// A filter for a layer's `filters`, blurring by `amount` as Figma
    /// measures it: twice the Gaussian's standard deviation.
    static func filter(amount: Double) -> Any {
        let sigma = max(amount, 0) / 2
        if let type = NSClassFromString("CAFilter") as? NSObject.Type,
           let made = type.perform(NSSelectorFromString("filterWithType:"), with: "gaussianBlur")?
               .takeUnretainedValue() as? NSObject {
            made.setValue(sigma, forKey: "inputRadius")
            // Not `inputNormalizeEdges`: set, it stops the filter drawing
            // anything at all in CARenderer.
            return made
        }
        return CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: sigma]) as Any
    }

    /// A layer that shows whatever is drawn behind it, run through its own
    /// `filters`. Nil if the system does not have one.
    static func makeBackdrop() -> CALayer? {
        guard let type = NSClassFromString("CABackdropLayer") as? CALayer.Type,
              NSClassFromString("CAFilter") != nil else { return nil }
        return type.init()
    }
}
