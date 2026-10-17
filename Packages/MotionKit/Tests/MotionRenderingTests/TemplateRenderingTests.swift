import Foundation
import Testing
import CoreGraphics
import ImageIO
import MotionModel
import MotionEvaluation
@testable import MotionRendering

/// Every template drawn as exports draw it: something shows, inside the
/// frame. With `TWINE_SPIKE_OUT` set, each is saved there to look at.
@Suite struct TemplateRenderingTests {
    @Test(arguments: TemplateKind.allCases)
    func everyTemplateDraws(_ kind: TemplateKind) throws {
        let size = Size2(640, 360)
        let setup = TemplateSetup(kind: kind, slots: Array(repeating: nil, count: TemplateRecipes.slotCount(kind)))
        let frame = Layer(name: "T", content: .group(GroupContent(clipsContent: true, frame: FrameStyle(fills: [Fill(paint: .color(RGBA(0.08, 0.08, 0.09)))]),
                                                                  template: setup)),
                          size: size, position: Vec2(320, 180))
        let project = Project(composition: Composition(width: 640, height: 360), layers: [frame])
        let renderer = try #require(OffscreenRenderer(pixelWidth: 640, pixelHeight: 360))
        let image = try #require(renderer.image(of: evaluate(project, at: 0)))
        // Count the pixels lighter than the ground: the cards.
        var bytes = [UInt8](repeating: 0, count: 640 * 360 * 4)
        let context = CGContext(data: &bytes, width: 640, height: 360, bitsPerComponent: 8, bytesPerRow: 640 * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 640, height: 360))
        var lit = 0
        for i in stride(from: 0, to: bytes.count, by: 4) where Int(bytes[i]) + Int(bytes[i + 1]) + Int(bytes[i + 2]) > 150 { lit += 1 }
        #expect(lit > 640 * 360 / 50, "\(kind) shows its cards (\(lit) pixels)")
        if let folder = ProcessInfo.processInfo.environment["TWINE_SPIKE_OUT"],
           let out = CGImageDestinationCreateWithURL(URL(fileURLWithPath: folder).appendingPathComponent("template-\(kind.rawValue).png") as CFURL,
                                                     "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(out, image, nil)
            CGImageDestinationFinalize(out)
        }
    }
}
