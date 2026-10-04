import Foundation
import Testing
import AppKit
import MotionModel
import MotionEvaluation
import MotionEditing
@testable import MotionImport

private func payload(_ nodes: String, images: String = "{}") -> String {
    ##"{"format": "twine.figma", "version": 1, "images": \##(images), "nodes": [\##(nodes)]}"##
}

private func near(_ a: Double, _ b: Double, _ e: Double = 1e-6) -> Bool { abs(a - b) < e }

@Suite struct FigmaImportTests {
    @Test func knowsItsOwnCopies() {
        #expect(FigmaImport.isPayload(payload("")))
        #expect(!FigmaImport.isPayload("hello"))
        #expect(throws: FigmaImport.ReadError.empty) { try FigmaImport.read(payload("")) }
    }

    @Test func aFrameWithItsLookAndAChildInItsSpace() throws {
        let json = payload(##"""
        {"kind": "frame", "name": "Card", "transform": [1, 0, 0, 1, 100, 50], "width": 200, "height": 120, "clips": true,
         "radii": [16, 16, 0, 0], "fills": [{"type": "SOLID", "color": {"r": 1, "g": 1, "b": 1}, "opacity": 0.5}],
         "strokes": [{"type": "SOLID", "color": {"r": 0, "g": 0, "b": 0}}], "strokeWeight": 2, "strokeAlign": "INSIDE",
         "effects": [{"type": "DROP_SHADOW", "color": {"r": 0, "g": 0, "b": 0, "a": 0.25}, "offset": {"x": 0, "y": 4}, "radius": 8, "spread": 0}],
         "blend": "MULTIPLY",
         "children": [{"kind": "rectangle", "name": "Box", "transform": [1, 0, 0, 1, 110, 60], "width": 20, "height": 10,
                       "fills": [{"type": "SOLID", "color": {"r": 1, "g": 0, "b": 0}}]}]}
        """##)
        let r = try FigmaImport.read(json)
        let frame = try #require(r.layers.first)
        #expect(frame.isFrame && frame.name == "Card" && frame.size == Size2(200, 120))
        #expect(frame.transform.position == Vec2(200, 110))
        #expect(frame.blendMode == .multiply)
        guard case .group(let g) = frame.content else { return }
        #expect(g.clipsContent && g.frame?.cornerRadii == CornerRadii(topLeft: 16, topRight: 16, bottomRight: 0, bottomLeft: 0))
        #expect(g.frame?.fills.map(\.paint) == [.color(RGBA(1, 1, 1, 0.5))])
        #expect(g.frame?.strokes.first?.alignment == .inside && g.frame?.strokes.first?.width == 2)
        #expect(frame.effects.map(\.kind) == [.dropShadow(DropShadow(color: .black, offset: Vec2(0, 4), blur: 8, opacity: 0.25))])
        // The child 10, 10 into the frame, its centre 15 across.
        #expect(g.children.first?.transform.position == Vec2(20, 15))
        #expect(r.bounds == Box(minX: 100, minY: 50, maxX: 300, maxY: 170))
    }

    @Test func figmasTurnTurnsTheOtherWay() throws {
        // Figma's 30 degrees turn anticlockwise: its matrix has b = -sin.
        let a = 30 * Double.pi / 180
        let json = payload(##"{"kind": "rectangle", "name": "R", "transform": [\##(cos(a)), \##(-sin(a)), \##(sin(a)), \##(cos(a)), 0, 0], "width": 10, "height": 10}"##)
        let layer = try #require(try FigmaImport.read(json).layers.first)
        #expect(near(layer.transform.rotation, -30))
    }

    @Test func skewedLayersLandExactly() throws {
        // Figma's own matrix for a turned, slanted and mirrored layer: every
        // corner must land where Figma puts it.
        let m = [0.8, -0.35, 0.9, 0.55, 40.0, 70.0]
        let json = payload(##"{"kind": "rectangle", "name": "R", "transform": [\##(m.map { "\($0)" }.joined(separator: ", "))], "width": 60, "height": 30}"##)
        let layer = try #require(try FigmaImport.read(json).layers.first)
        #expect(layer.transform.skew.x != 0 && layer.transform.skew.y == 0)
        let scene = evaluateDesign(Project(layers: [layer]))
        let corners = try #require(scene.worldCorners(of: layer.id))
        let expected = [(0.0, 0.0), (60.0, 0.0), (60.0, 30.0), (0.0, 30.0)].map { (x, y) in
            Vec2(m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5])
        }
        for (got, want) in zip(corners, expected) {
            #expect(near(got.x, want.x, 1e-6) && near(got.y, want.y, 1e-6), "\(got) against \(want)")
        }
        // A skewed frame keeps its skew, and what is inside lands where Figma
        // has it, through the frame's slant.
        let frame = payload(##"""
        {"kind": "frame", "name": "F", "transform": [1, 0, 0.5, 1, 100, 100], "width": 100, "height": 50, "children": [
         {"kind": "rectangle", "name": "In", "transform": [1, 0, 0.5, 1, 120, 110], "width": 20, "height": 20}]}
        """##)
        let f = try #require(try FigmaImport.read(frame).layers.first)
        guard case .group(let g) = f.content, let child = g.children.first else { Issue.record("no frame"); return }
        #expect(near(f.transform.skew.x, atan(0.5) * 180 / .pi))
        #expect(near(child.transform.skew.x, 0))
        let inner = evaluateDesign(Project(layers: [f]))
        let c = try #require(inner.worldCorners(of: child.id))
        #expect(near(c[2].x, 120 + 20 + 0.5 * 20, 1e-6) && near(c[2].y, 130, 1e-6))
    }

    @Test func aFramesPictureBackgroundIsALayerAndOnlyTheTopPictureCounts() throws {
        // As Figma had it: a colour, three pictures stacked on it, and a tint over them all.
        let picture = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVR4nGP4z8DwHwQZ/gMAG/0D/eqA0WQAAAAASUVORK5CYII="
        let json = payload(##"""
        {"kind": "frame", "name": "Screen", "transform": [1, 0, 0, 1, 0, 0], "width": 200, "height": 100, "clips": true,
         "radii": [12, 12, 12, 12],
         "fills": [{"type": "SOLID", "color": {"r": 0, "g": 0, "b": 0}},
                   {"type": "IMAGE", "image": "a", "scaleMode": "FILL"},
                   {"type": "IMAGE", "image": "b", "scaleMode": "FILL"},
                   {"type": "IMAGE", "image": "c", "scaleMode": "FIT"},
                   {"type": "SOLID", "color": {"r": 1, "g": 1, "b": 1}, "opacity": 0.2}],
         "children": [{"kind": "rectangle", "name": "Card", "transform": [1, 0, 0, 1, 20, 20], "width": 40, "height": 20}]}
        """##, images: ##"{"a": "\##(picture)", "b": "\##(picture)", "c": "\##(picture)"}"##)
        let r = try FigmaImport.read(json)
        let frame = try #require(r.layers.first)
        guard case .group(let g) = frame.content else { Issue.record("no frame"); return }
        // The colour stays the frame's; the picture, with the tint over it, is a layer behind the rest.
        #expect(g.frame?.fills.map(\.paint) == [.color(RGBA(0, 0, 0))])
        #expect(g.children.map(\.name) == ["Background", "Card"])
        let background = try #require(g.children.first)
        #expect(background.size == Size2(200, 100) && background.transform.position == Vec2(100, 50))
        #expect(background.look?.geometry == .rectangle(cornerRadii: CornerRadii(all: 12)))
        let fills = background.look?.fills ?? []
        try #require(fills.count == 2, "\(fills.map(\.paint))")
        #expect(fills[0].paint.imagePaint?.mode == .fit, "only the top picture, in its own mode")
        #expect(fills[1].paint == .color(RGBA(1, 1, 1, 0.2)))
        // Only the one picture is kept, and it is the picture fill Replace works on.
        #expect(r.media.count == 1)
        #expect(background.picture?.index == 0)
    }

    @Test func aMaskMasksWhatIsInFrontOfIt() throws {
        let json = payload(##"""
        {"kind": "group", "name": "G", "transform": [1, 0, 0, 1, 0, 0], "width": 50, "height": 50, "children": [
         {"kind": "rectangle", "name": "Behind", "transform": [1, 0, 0, 1, 0, 0], "width": 10, "height": 10},
         {"kind": "ellipse", "name": "Mask", "isMask": true, "maskType": "ALPHA", "transform": [1, 0, 0, 1, 0, 0], "width": 50, "height": 50},
         {"kind": "rectangle", "name": "A", "transform": [1, 0, 0, 1, 0, 0], "width": 50, "height": 50},
         {"kind": "rectangle", "name": "B", "transform": [1, 0, 0, 1, 0, 0], "width": 50, "height": 50}]}
        """##)
        let group = try #require(try FigmaImport.read(json).layers.first)
        let kids = group.children
        // Figma and Twine mask alike: the mask comes in as one, in its place.
        #expect(kids.map(\.isMask) == [false, true, false, false])
    }

    @Test func gradientsAndPicturesKeepTheirPlaces() throws {
        let png = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                                                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)?
            .representation(using: .png, properties: [:])).base64EncodedString()
        // A left to right gradient is Figma's identity; a crop showing the
        // picture's left half, twice the box's width.
        let json = payload(##"""
        {"kind": "rectangle", "name": "P", "transform": [1, 0, 0, 1, 0, 0], "width": 100, "height": 50, "fills": [
          {"type": "GRADIENT_LINEAR", "transform": [1, 0, 0, 1, 0, 0], "stops": [{"position": 0, "color": {"r": 1, "g": 0, "b": 0, "a": 1}}, {"position": 1, "color": {"r": 0, "g": 0, "b": 1, "a": 1}}]},
          {"type": "IMAGE", "image": "h1", "scaleMode": "CROP", "imageTransform": [0.5, 0, 0, 1, 0, 0], "opacity": 0.5},
          {"type": "IMAGE", "image": "h1", "scaleMode": "FIT", "rotation": 90}]},
        {"kind": "rectangle", "name": "Q", "transform": [1, 0, 0, 1, 0, 0], "width": 100, "height": 50, "fills": [
          {"type": "IMAGE", "image": "h1", "scaleMode": "CROP", "imageTransform": [0.5, 0, 0, 1, 0, 0], "opacity": 0.5}]}
        """##, images: ##"{"h1": "\##(png)"}"##)
        let r = try FigmaImport.read(json)
        // Of the two pictures stacked on P, only the top one comes in.
        let fills = try #require(r.layers.first?.look?.fills)
        try #require(fills.count == 2)
        guard case .linearGradient(let g) = fills[0].paint else { Issue.record("no gradient"); return }
        #expect(g.start == Vec2(0, 0.5) && g.end == Vec2(1, 0.5))
        let alone = try #require(r.layers.last?.look?.fills)
        guard case .image(let crop) = alone.first?.paint, case .image(let fit) = fills[1].paint else { Issue.record("no pictures"); return }
        #expect(crop.mode == .crop && crop.crop == ImageCrop(x: 0, y: 0, width: 2, height: 1) && crop.opacity == 0.5)
        #expect(fit.mode == .fit && fit.quarterTurns == 1 && fit.mediaID == crop.mediaID)
        #expect(r.media.count == 1)
    }

    @Test func angularGradientsComeInTurningTheSameWay() throws {
        let stops = ##""stops": [{"position": 0.25, "color": {"r": 1, "g": 0, "b": 0, "a": 1}}, {"position": 1, "color": {"r": 0, "g": 0, "b": 1, "a": 1}}]"##
        let json = payload(##"""
        {"kind": "rectangle", "name": "A", "transform": [1, 0, 0, 1, 0, 0], "width": 100, "height": 50, "fills": [
          {"type": "GRADIENT_ANGULAR", "transform": [1, 0, 0, 1, 0, 0], \##(stops)}]},
        {"kind": "rectangle", "name": "M", "transform": [1, 0, 0, 1, 0, 0], "width": 100, "height": 50, "fills": [
          {"type": "GRADIENT_ANGULAR", "transform": [-1, 0, 0, 1, 1, 0], \##(stops)}]}
        """##)
        let r = try FigmaImport.read(json)
        guard case .angularGradient(let a)? = r.layers.first?.look?.fills.first?.paint,
              case .angularGradient(let m)? = r.layers.last?.look?.fills.first?.paint else { Issue.record("not angular"); return }
        // Figma's identity starts at the right and turns clockwise, as Twine's do.
        #expect(a.start == Vec2(0.5, 0.5) && a.end == Vec2(1, 0.5) && a.stops.map(\.position) == [0.25, 1])
        // Mirrored, it starts at the left and turns the other way: the stops
        // come in turned end for end.
        #expect(m.start == Vec2(0.5, 0.5) && m.end == Vec2(0, 0.5) && m.stops.map(\.position) == [0.75, 0])
    }

    @Test func vectorsBecomePathsInTheirOwnBox() throws {
        let json = payload(##"""
        {"kind": "vector", "name": "V", "transform": [1, 0, 0, 1, 10, 10], "width": 40, "height": 40,
         "paths": [{"rule": "EVENODD", "d": "M5 5 L35 5 L35 35 L5 35 Z M15 15 L25 15 L25 25 L15 25 Z"}],
         "fills": [{"type": "SOLID", "color": {"r": 0, "g": 0, "b": 0}}]}
        """##)
        let layer = try #require(try FigmaImport.read(json).layers.first)
        #expect(layer.size == Size2(30, 30) && layer.transform.position == Vec2(30, 30))
        #expect(layer.look?.fillRule == .evenOdd)
    }

    @Test func textIsEditableAndMissingFontsAreNoted() throws {
        let json = payload(##"""
        {"kind": "text", "name": "Title", "transform": [1, 0, 0, 1, 0, 0], "width": 200, "height": 40,
         "fills": [{"type": "SOLID", "color": {"r": 0.1, "g": 0.2, "b": 0.3}}],
         "text": {"characters": "Hello", "family": "Helvetica", "style": "Semi Bold", "size": 32, "letterSpacing": 1, "lineHeight": 40, "align": "CENTER", "autoResize": "HEIGHT"}},
        {"kind": "text", "name": "Other", "transform": [1, 0, 0, 1, 0, 100], "width": 200, "height": 40,
         "text": {"characters": "Hi", "family": "No Such Font Twine", "style": "Regular", "size": 16}}
        """##)
        let r = try FigmaImport.read(json)
        guard case .text(let t) = r.layers.first?.content else { Issue.record("not text"); return }
        #expect(t.text == "Hello" && t.fontWeight == 600 && t.fontSize == 32 && t.alignment == .center)
        #expect(t.sizing == .fixedWidth && t.lineHeight == 40 && t.letterSpacing == 1)
        #expect(t.color == RGBA(0.1, 0.2, 0.3))
        #expect(r.missingFonts == ["No Such Font Twine"])
    }

    @Test func figmasPicturesAndSVGsSitInTheirBoxes() throws {
        let png = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
                                                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)?
            .representation(using: .png, properties: [:])).base64EncodedString()
        let svg = #"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"10\" viewBox=\"0 0 20 10\"><rect width=\"20\" height=\"10\" fill=\"red\"/></svg>"#
        let json = payload(##"""
        {"kind": "picture", "name": "Flat", "transform": [1, 0, 0, 1, 0, 0], "width": 4, "height": 2, "png": "\##(png)", "bounds": [10, 20, 4, 2]},
        {"kind": "svg", "name": "Icon", "transform": [1, 0, 0, 1, 0, 0], "width": 20, "height": 10, "svg": "\##(svg)", "bounds": [50, 50, 20, 10]}
        """##)
        let r = try FigmaImport.read(json)
        #expect(r.layers.count == 2)
        #expect(Arrangement.box(of: r.layers[0]) == Box(minX: 10, minY: 20, maxX: 14, maxY: 22))
        #expect(r.layers[0].picture?.paint.mode == .crop)
        #expect(r.layers[1].isGroup && Arrangement.box(of: r.layers[1]) == Box(minX: 50, minY: 50, maxX: 70, maxY: 60))
        #expect(r.layers[1].children.first?.look?.fills.map(\.paint) == [.color(RGBA(1, 0, 0))])
    }

    @Test func fontStylesAreWeights() {
        #expect(FigmaBuilderWeights.check())
    }
}

/// Reaches the weight table through the payload, as the builder is private.
private enum FigmaBuilderWeights {
    static func check() -> Bool {
        let styles = ["Thin": 100, "ExtraLight": 200, "Light": 300, "Regular": 400, "Medium": 500, "Semi Bold": 600,
                      "Bold": 700, "Extra Bold": 800, "Black": 900, "Bold Italic": 700]
        return styles.allSatisfy { style, weight in
            let json = payload(##"{"kind": "text", "name": "T", "transform": [1, 0, 0, 1, 0, 0], "width": 10, "height": 10, "text": {"characters": "x", "family": "Helvetica", "style": "\##(style)", "size": 10}}"##)
            guard case .text(let t)? = try? FigmaImport.read(json).layers.first?.content else { return false }
            return t.fontWeight == weight
        }
    }
}
