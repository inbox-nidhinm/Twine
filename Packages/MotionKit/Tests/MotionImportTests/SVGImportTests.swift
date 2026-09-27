import Foundation
import Testing
import AppKit
import MotionModel
import MotionEvaluation
import MotionEditing
import MotionRendering
@testable import MotionImport

private func read(_ body: String, width: Int = 100, height: Int = 100, extra: String = "") throws -> SVGImport.Result {
    let svg = ##"<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="\##(width)" height="\##(height)" viewBox="0 0 \##(width) \##(height)" \##(extra)>\##(body)</svg>"##
    return try SVGImport.read(Data(svg.utf8), name: "Test", center: Vec2(Double(width) / 2, Double(height) / 2))
}

private func only(_ r: SVGImport.Result) -> Layer? { r.layer.children.count == 1 ? r.layer.children[0] : nil }

private func near(_ a: Double, _ b: Double, _ e: Double = 1e-6) -> Bool { abs(a - b) < e }

@Suite struct SVGPathDataTests {
    @Test func readsEveryCommandAndCompactNumbers() {
        // `-5.5.5.5` is -5.5, then .5 and .5.
        let p = SVGPathData.parse("M0,0l10-5.5.5.5H20V10h-5v-2Q25 20 30 10T40 10C45 0 50 0 55 10S65 20 70 10Z")
        #expect(p.subpaths.count == 1 && p.subpaths.first?.isClosed == true)
        let pts = p.subpaths.first?.points.map(\.position) ?? []
        #expect(pts.count == 11)
        guard pts.count == 11 else { return }
        #expect(pts[1] == Vec2(10, -5.5) && pts[2] == Vec2(10.5, -5) && pts[3] == Vec2(20, -5) && pts[4] == Vec2(20, 10))
        #expect(pts[5] == Vec2(15, 10) && pts[6] == Vec2(15, 8))
        #expect(pts.last == Vec2(70, 10))
    }

    @Test func anArcIsAHalfCircleOfTheRightSize() {
        let p = SVGPathData.parse("M0 0 A10 10 0 0 1 20 0")
        let b = p.bounds!
        #expect(near(b.minX, 0, 1e-3) && near(b.maxX, 20, 1e-3) && near(b.minY, -10, 0.05) && near(b.maxY, 0, 1e-3))
        // Sweep the other way, it bulges down.
        #expect(near(SVGPathData.parse("M0 0 A10 10 0 0 0 20 0").bounds!.maxY, 10, 0.05))
    }

    @Test func closingOnTheStartDoesNotRepeatIt() {
        let p = SVGPathData.parse("M0 0 L10 0 L10 10 L0 0 Z")
        #expect(p.subpaths[0].points.count == 3)
    }

    @Test func transformsReadInSVGsOrder() {
        let t = SVGTransform.parse("translate(10 20) rotate(90) scale(2)")
        let p = t.apply(Vec2(1, 0))
        #expect(near(p.x, 10) && near(p.y, 22))
        #expect(near(SVGTransform.parse("rotate(90 5 5)").apply(Vec2(10, 5)).y, 10))
    }
}

@Suite struct SVGImportTests {
    @Test func aRectangleStaysARectangleWithItsCorners() throws {
        let layer = try #require(only(try read(##"<rect x="10" y="20" width="30" height="40" rx="4" fill="#f00"/>"##)))
        #expect(layer.look?.geometry == .rectangle(cornerRadii: CornerRadii(all: 4)))
        #expect(layer.size == Size2(30, 40) && layer.transform.position == Vec2(25, 40))
        #expect(layer.look?.fills.map(\.paint) == [.color(RGBA(1, 0, 0))])
    }

    @Test func aTurnedRectangleKeepsItsKindAndASkewedOneBecomesAPath() throws {
        let turned = try #require(only(try read(##"<rect width="20" height="10" transform="translate(50 50) rotate(30)"/>"##)))
        #expect(turned.look?.geometry == .rectangle(cornerRadii: .zero))
        #expect(near(turned.transform.rotation, 30) && turned.size == Size2(20, 10))
        let skewed = try #require(only(try read(##"<rect width="20" height="10" transform="skewX(20)"/>"##)))
        guard case .path? = skewed.look?.geometry else { Issue.record("not a path"); return }
    }

    @Test func circlesAreEllipsesAndFillsDefaultToBlack() throws {
        let layer = try #require(only(try read(##"<circle cx="50" cy="50" r="10"/>"##)))
        #expect(layer.look?.geometry == .ellipse(arc: .full) && layer.size == Size2(20, 20))
        #expect(layer.look?.fills.map(\.paint) == [.color(.black)])
    }

    @Test func coloursInEveryWay() throws {
        let r = try read(##"<rect width="1" height="1" fill="#0f08"/><rect width="1" height="1" fill="rgb(255, 0, 0)" fill-opacity=".5"/><rect width="1" height="1" style="fill: rebeccapurple"/><rect width="1" height="1" class="a"/><style>.a { fill: hsl(120, 100%, 50%) }</style>"##)
        let paints = r.layer.children.compactMap { $0.look?.fills.first?.paint }
        #expect(paints.count == 4)
        #expect(paints[0] == .color(RGBA(0, 1, 0, Double(0x88) / 255)))
        #expect(paints[1] == .color(RGBA(1, 0, 0, 0.5)))
        #expect(paints[2] == .color(RGBA(hex: "663399")!))
        if case .solid(let c) = paints[3] { #expect(near(c.g, 1) && near(c.r, 0)) } else { Issue.record("not solid") }
    }

    @Test func strokesScaleWithTheirTransform() throws {
        let layer = try #require(only(try read(##"<path d="M0 0 L10 0" stroke="blue" stroke-width="2" stroke-linecap="round" stroke-dasharray="3" fill="none" transform="scale(3)"/>"##)))
        let stroke = try #require(layer.look?.strokes.first)
        #expect(near(stroke.width, 6) && stroke.cap == .round && stroke.dashPattern == [9, 9])
        #expect(layer.look?.fills.isEmpty == true)
        #expect(layer.size == Size2(30, 0))
    }

    @Test func groupsWithSomethingOfTheirOwnStayGroups() throws {
        let r = try read(##"<g><rect width="10" height="10"/></g><g opacity="0.5"><rect x="20" width="10" height="10"/><rect x="40" width="10" height="10"/></g>"##)
        #expect(r.layer.children.count == 2)
        #expect(!r.layer.children[0].isGroup, "a group of one is just that one")
        let group = r.layer.children[1]
        #expect(group.isGroup && group.opacity == 0.5 && group.children.count == 2)
        #expect(Arrangement.box(of: group) == Box(minX: 20, minY: 0, maxX: 50, maxY: 10))
    }

    @Test func gradientsLandInTheLayersBox() throws {
        let layer = try #require(try read(##"<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#fff"/><stop offset="100%" stop-color="#000" stop-opacity="0.5"/></linearGradient><linearGradient id="u" gradientUnits="userSpaceOnUse" x1="20" y1="0" x2="40" y2="0" xlink:href="#g"/></defs><rect x="20" y="0" width="20" height="10" fill="url(#g)"/><rect x="20" y="20" width="20" height="10" fill="url(#u)"/>"##).layer.children.first)
        guard case .linearGradient(let g)? = layer.look?.fills.first?.paint else { Issue.record("no gradient"); return }
        #expect(near(g.start.x, 0) && near(g.end.x, 1) && near(g.start.y, 0))
        #expect(g.stops.map(\.color) == [.white, RGBA(0, 0, 0, 0.5)])
        let second = try read(##"<defs><linearGradient id="g"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#000"/></linearGradient><linearGradient id="u" gradientUnits="userSpaceOnUse" x1="25" y1="0" x2="35" y2="0" xlink:href="#g"/></defs><rect x="20" y="20" width="20" height="10" fill="url(#u)"/>"##)
        guard case .linearGradient(let u)? = only(second)?.look?.fills.first?.paint else { Issue.record("no gradient"); return }
        #expect(near(u.start.x, 0.25) && near(u.end.x, 0.75), "user space points, measured in the box")
    }

    @Test func aClipPathBecomesAMask() throws {
        let r = try read(##"<defs><clipPath id="c"><rect x="10" y="10" width="50" height="50" rx="8"/></clipPath></defs><g clip-path="url(#c)"><rect width="100" height="100" fill="red"/></g>"##)
        #expect(r.layer.children.count == 2)
        let (clip, target) = (r.layer.children[0], r.layer.children[1])
        #expect(target.mask?.layerID == clip.id)
        #expect(Arrangement.box(of: clip) == Box(minX: 10, minY: 10, maxX: 60, maxY: 60))
    }

    @Test func evenOddPathsKeepTheirRule() throws {
        let layer = try #require(only(try read(##"<path fill-rule="evenodd" d="M0 0H100V100H0Z M25 25H75V75H25Z"/>"##)))
        #expect(layer.look?.fillRule == .evenOdd)
    }

    @Test func figmasShadowsAndBlursBecomeEffects() throws {
        let filter = ##"""
        <defs><filter id="f" x="0" y="0" width="100" height="100" filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB">
        <feFlood flood-opacity="0" result="BackgroundImageFix"/>
        <feColorMatrix in="SourceAlpha" type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0" result="hardAlpha"/>
        <feMorphology radius="2" operator="dilate" in="SourceAlpha" result="effect1_dropShadow_1_2"/>
        <feOffset dy="4"/><feGaussianBlur stdDeviation="6"/><feComposite in2="hardAlpha" operator="out"/>
        <feColorMatrix type="matrix" values="0 0 0 0 0.2 0 0 0 0 0.4 0 0 0 0 0.6 0 0 0 0.25 0"/>
        <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_1_2"/>
        <feBlend mode="normal" in="SourceGraphic" in2="effect1_dropShadow_1_2" result="shape"/>
        <feColorMatrix in="SourceAlpha" type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0" result="hardAlpha"/>
        <feOffset dx="1" dy="-2"/><feGaussianBlur stdDeviation="1"/>
        <feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1"/>
        <feColorMatrix type="matrix" values="0 0 0 0 1 0 0 0 0 1 0 0 0 0 1 0 0 0 0.5 0"/>
        <feBlend mode="normal" in2="shape" result="effect2_innerShadow_1_2"/>
        <feGaussianBlur stdDeviation="3" result="effect3_foregroundBlur_1_2"/>
        </filter></defs>
        """##
        let layer = try #require(only(try read(filter + ##"<g filter="url(#f)"><rect width="20" height="20"/></g>"##)))
        let kinds = layer.effects.map(\.kind)
        #expect(kinds.count == 3)
        #expect(kinds.first == .dropShadow(DropShadow(color: RGBA(0.2, 0.4, 0.6), offset: Vec2(0, 4), blur: 12, opacity: 0.25, spread: 2)))
        #expect(kinds.dropFirst().first == .innerShadow(DropShadow(color: .white, offset: Vec2(1, -2), blur: 2, opacity: 0.5, spread: 0)))
        #expect(kinds.last == .layerBlur(LayerBlur(radius: 6)))
    }

    @Test func figmasPictureFillsBecomePictures() throws {
        let png = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                                                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)?
            .representation(using: .png, properties: [:]))
        let body = ##"<rect width="40" height="20" fill="url(#p)"/><defs><pattern id="p" patternContentUnits="objectBoundingBox" width="1" height="1"><use xlink:href="#img" transform="matrix(0.25 0 0 0.5 0 0)"/></pattern><image id="img" width="4" height="2" xlink:href="data:image/png;base64,\##(png.base64EncodedString())"/></defs>"##
        let r = try read(body)
        let paint = try #require(only(r)?.picture?.paint)
        #expect(paint.mode == .crop && paint.crop == ImageCrop(x: 0, y: 0, width: 1, height: 1))
        #expect(r.media.count == 1 && r.media[0].asset.id == paint.mediaID && r.media[0].asset.pixelWidth == 4)
    }

    @Test func textBecomesAPictureInItsPlace() throws {
        let r = try read(##"<text x="10" y="60" font-size="30" fill="#00f">Hi</text>"##)
        let layer = try #require(only(r))
        #expect(r.pictureCount == 1 && r.media.count == 1)
        #expect(layer.picture != nil)
        let box = try #require(Arrangement.box(of: layer))
        #expect(box.minX > 8 && box.minX < 16 && box.maxY > 55 && box.maxY < 66 && box.minY > 30)
    }

    @Test func figmasLinesOfTextArePlacedAsTheyWere() throws {
        // Figma writes each line as a positioned tspan; the system draws
        // those wrongly unless they are made texts of their own.
        let r = try read(##"<g clip-path="url(#c)"><text fill="#1E1E1E" style="white-space: pre" font-family="Helvetica" font-size="20"><tspan x="10" y="40">One</tspan><tspan x="10" y="70">Two</tspan></text></g><defs><clipPath id="c"><rect width="100" height="100"/></clipPath></defs>"##, extra: #"fill="none""#)
        let text = try #require(r.layer.children.last)
        let box = try #require(Arrangement.box(of: text))
        #expect(box.minX > 8 && box.minX < 14, "\(box)")
        #expect(box.minY > 20 && box.minY < 30 && box.maxY > 66 && box.maxY < 76, "both lines, top to bottom")
        #expect(text.name == "Text 1")
    }

    @Test func boldTextIsDrawnBold() throws {
        func ink(_ weight: String) throws -> Int {
            let r = try read(##"<text x="5" y="40" font-family="Helvetica" font-size="28" font-weight="\##(weight)"><tspan x="5" y="40">Hi</tspan></text>"##)
            let png = try #require(r.media.first?.data)
            let rep = try #require(NSBitmapImageRep(data: png))
            var total = 0
            for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide { total += Int((rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) * 100) } }
            return total
        }
        #expect(try ink("bold") > (try ink("normal")) * 12 / 10)
    }

    @Test func theViewBoxAndFittingScaleEverything() throws {
        let svg = ##"<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" viewBox="0 0 20 10"><rect x="5" width="10" height="10" stroke="#000" stroke-width="1"/></svg>"##
        let r = try SVGImport.read(Data(svg.utf8), name: "S", center: Vec2(0, 0), fitting: Size2(100, 100))
        #expect(r.layer.size == Size2(100, 50) && r.layer.isFrame)
        let rect = try #require(only(r))
        #expect(rect.size == Size2(50, 50) && rect.transform.position == Vec2(50, 25))
        #expect(near(rect.look?.strokes.first?.width ?? 0, 5))
    }

    @Test func notAnSVGIsRefused() {
        #expect(throws: SVGImport.ReadError.notSVG) { try SVGImport.read(Data("hello".utf8), name: "x") }
    }
}

/// The whole file read in and drawn by Twine, against the same file drawn by
/// the system: every pixel close.
@Suite(.serialized) struct SVGDrawingTests {
    private let sample = ##"""
    <svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
    <defs>
      <linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff"/></linearGradient>
      <clipPath id="c"><circle cx="48" cy="48" r="12"/></clipPath>
    </defs>
    <rect width="64" height="64" fill="#ffffff"/>
    <path fill-rule="evenodd" fill="#228833" d="M4 4H28V28H4Z M10 10H22V22H10Z"/>
    <rect x="36" y="4" width="24" height="24" rx="6" fill="url(#g)"/>
    <g transform="rotate(45 16 48)"><rect x="8" y="40" width="16" height="16" fill="#ffaa00" stroke="#000000" stroke-width="2"/></g>
    <g clip-path="url(#c)"><rect x="32" y="32" width="32" height="32" fill="#8800ff"/></g>
    </svg>
    """##

    @Test func twineDrawsItAsTheSystemDoes() throws {
        let r = try SVGImport.read(Data(sample.utf8), name: "S", center: Vec2(32, 32))
        #expect(r.pictureCount == 0)
        let project = Project(composition: Composition(width: 64, height: 64, background: Background(isTransparent: true)),
                              layers: [r.layer])
        let renderer = try #require(OffscreenRenderer(pixelWidth: 64, pixelHeight: 64))
        let twine = try #require(renderer.image(of: evaluate(project, at: 0)))
        let system = try #require(SVGPictures.draw(sample, size: Size2(64, 64), scale: 1))
        let reference = try #require(NSBitmapImageRep(data: system.png)?.cgImage)
        func rgba(_ image: CGImage) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: 64 * 64 * 4)
            let context = CGContext(data: &bytes, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return bytes
        }
        // TWINE_SVG_OUT=folder saves both drawings, to look at.
        if let folder = ProcessInfo.processInfo.environment["TWINE_SVG_OUT"] {
            for (name, image) in [("twine", twine), ("system", reference)] {
                let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                try data?.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
            }
        }
        let a = rgba(twine), b = rgba(reference)
        // Edges are drawn a little differently; the body of every shape must
        // agree.
        var off = 0
        for i in stride(from: 0, to: a.count, by: 4) where (0..<3).contains(where: { abs(Int(a[i + $0]) - Int(b[i + $0])) > 40 }) {
            off += 1
        }
        #expect(off < 64 * 64 / 25, "\(off) pixels differ")
    }
}
