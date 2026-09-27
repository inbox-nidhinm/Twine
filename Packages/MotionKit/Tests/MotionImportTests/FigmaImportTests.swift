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
        #expect(kids[0].mask == nil && kids[2].mask?.layerID == kids[1].id && kids[3].mask?.layerID == kids[1].id)
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
          {"type": "IMAGE", "image": "h1", "scaleMode": "FIT", "rotation": 90}]}
        """##, images: ##"{"h1": "\##(png)"}"##)
        let r = try FigmaImport.read(json)
        let fills = try #require(r.layers.first?.look?.fills)
        guard case .linearGradient(let g) = fills[0].paint else { Issue.record("no gradient"); return }
        #expect(g.start == Vec2(0, 0.5) && g.end == Vec2(1, 0.5))
        guard case .image(let crop) = fills[1].paint, case .image(let fit) = fills[2].paint else { Issue.record("no pictures"); return }
        #expect(crop.mode == .crop && crop.crop == ImageCrop(x: 0, y: 0, width: 2, height: 1) && crop.opacity == 0.5)
        #expect(fit.mode == .fit && fit.quarterTurns == 1 && fit.mediaID == crop.mediaID)
        #expect(r.media.count == 1)
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
