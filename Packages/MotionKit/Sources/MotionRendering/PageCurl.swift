import Foundation
import QuartzCore
import CoreImage
import MotionModel
import MotionEvaluation

/// The Page Curl presets' drawing: Core Image's own page curl, the filter
/// Flip's onboarding turns its pictures with, run on the layer as Core
/// Animation draws it. The page bends round a cylinder without stretching,
/// its back comes over as it turns, and a shadow travels with the fold. Where
/// the page has gone it shows nothing, so whatever is under the layer shows.
public enum PageCurlFilter {
    /// For a layer's `filters`: the layer, `size` big, curled as `curl` has
    /// it, with `back` on the back of the page, then cut to its box, as
    /// Flip's pictures are, so the leaf never pokes out and is wholly gone at
    /// the end. A layer reaches the filter in its own coordinates, running
    /// down, on the canvas and off screen alike.
    static func filters(_ curl: PageCurl, size: CGSize, back: CIImage) -> [Any] {
        let extent = CGRect(origin: .zero, size: size)
        guard let turn = CIFilter(name: "CIPageCurlWithShadowTransition"),
              let crop = CIFilter(name: "CICrop") else { return [] }
        turn.setValue(CIImage(color: .clear).cropped(to: extent), forKey: kCIInputTargetImageKey)
        turn.setValue(back, forKey: "inputBacksideImage")
        turn.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        // The shadow is worked out over the page itself; with no extent the
        // filter draws none.
        turn.setValue(CIVector(cgRect: extent), forKey: "inputShadowExtent")
        turn.setValue(curl.progress, forKey: kCIInputTimeKey)
        turn.setValue(angle(curl.corner, runsDown: true), forKey: kCIInputAngleKey)
        turn.setValue(radius(size), forKey: kCIInputRadiusKey)
        turn.setValue(0.5, forKey: "inputShadowSize")
        turn.setValue(0.65, forKey: "inputShadowAmount")
        crop.setValue(CIVector(cgRect: extent), forKey: "inputRectangle")
        return [turn, crop]
    }

    /// `image`, a picture `size` big, curled as `curl` has it over nothing,
    /// for a preset's tile. Nil while it is flat.
    public static func curled(_ image: CIImage, size: CGSize, curl: PageCurl, back: RGBA) -> CIImage? {
        guard curl.progress > 1e-6, let turn = CIFilter(name: "CIPageCurlWithShadowTransition") else { return nil }
        let extent = CGRect(origin: .zero, size: size)
        turn.setValue(image, forKey: kCIInputImageKey)
        turn.setValue(CIImage(color: .clear).cropped(to: extent), forKey: kCIInputTargetImageKey)
        turn.setValue(image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: back.r, y: back.g, z: back.b, w: 0),
        ]), forKey: "inputBacksideImage")
        turn.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        turn.setValue(CIVector(cgRect: extent), forKey: "inputShadowExtent")
        turn.setValue(curl.progress, forKey: kCIInputTimeKey)
        // A picture runs upward, as the filter's own coordinates do.
        turn.setValue(angle(curl.corner, runsDown: false), forKey: kCIInputAngleKey)
        turn.setValue(radius(size), forKey: kCIInputRadiusKey)
        turn.setValue(0.5, forKey: "inputShadowSize")
        turn.setValue(0.65, forKey: "inputShadowAmount")
        return turn.outputImage?.cropped(to: extent)
    }

    /// The way the fold sweeps, which names the corner that lifts: in the
    /// filter's own coordinates, running upward, 45° lifts the bottom left,
    /// 135° the bottom right, 225° the top right and 315° the top left;
    /// in coordinates that run down, the top and bottom trade places.
    static func angle(_ corner: PresetCorner, runsDown: Bool) -> Double {
        let degrees: Double
        switch corner {
        case .bottomLeft: degrees = runsDown ? 315 : 45
        case .bottomRight: degrees = runsDown ? 225 : 135
        case .topRight: degrees = runsDown ? 135 : 225
        case .topLeft: degrees = runsDown ? 45 : 315
        }
        return degrees * .pi / 180
    }

    /// How tight the fold is: Flip's 72 against a 740 point page, held to
    /// under half the short side, so a strip still curls rather than rolls.
    static func radius(_ size: CGSize) -> Double {
        max(min(0.1 * max(size.width, size.height), 0.4 * min(size.width, size.height)), 2)
    }

    /// The back of the page: what it is printed on, lifted towards the
    /// light, as Flip's are (the same stock as its face, not the picture
    /// over again): the top fill's colour, a gradient's first, a text's own,
    /// or near white for a picture or anything else.
    static func backColor(of layer: ResolvedLayer) -> RGBA {
        var ground = RGBA(0.94, 0.94, 0.94)
        if let fill = layer.look?.fills.last {
            switch fill {
            case .solid(let c): ground = c
            case .linear(let stops, _, _), .radial(let stops, _, _): if let first = stops.first { ground = first.color }
            case .image: break
            }
        } else if case .text(let text) = layer.content {
            ground = text.color
        }
        return lifted(ground)
    }

    /// `ground` lifted towards white, which keeps its hue where brightening
    /// a dark colour goes muddy.
    public static func lifted(_ ground: RGBA) -> RGBA {
        let lift = 0.28
        return RGBA(ground.r + (1 - ground.r) * lift, ground.g + (1 - ground.g) * lift, ground.b + (1 - ground.b) * lift)
    }

    /// The back as a picture: `outline` (the layer's box when nil) filled
    /// with `color`, drawn at `scale` and set to the layer's `size`, so the
    /// leaf keeps a card's rounded corners.
    static func back(outline: CGPath?, size: CGSize, color: RGBA, scale: CGFloat) -> CIImage {
        let extent = CGRect(origin: .zero, size: size)
        let tint = CIColor(red: color.r, green: color.g, blue: color.b)
        guard let outline else { return CIImage(color: tint).cropped(to: extent) }
        let w = max(Int((size.width * scale).rounded(.up)), 1), h = max(Int((size.height * scale).rounded(.up)), 1)
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return CIImage(color: tint).cropped(to: extent)
        }
        context.scaleBy(x: scale, y: scale)
        context.addPath(outline)
        context.setFillColor(CGColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: 1))
        context.fillPath()
        guard let picture = context.makeImage() else { return CIImage(color: tint).cropped(to: extent) }
        return CIImage(cgImage: picture).transformed(by: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
    }
}
