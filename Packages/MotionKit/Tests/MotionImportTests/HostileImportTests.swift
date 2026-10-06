import Foundation
import Testing
import AppKit
import MotionModel
@testable import MotionImport

/// Files made to break a reader: each must be refused or read safely,
/// never crash, hang or reach outside the file.
@Suite struct HostileImportTests {
    private func svg(_ body: String, doctype: String = "") -> Data {
        Data(##"\##(doctype)<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="100" height="100">\##(body)</svg>"##.utf8)
    }

    private func read(_ data: Data) throws -> SVGImport.Result {
        try SVGImport.read(data, name: "Test", center: Vec2(50, 50))
    }

    private func allFinite(_ layers: [Layer]) -> Bool {
        layers.allSatisfy { Finite.isFinite($0) && allFinite($0.children) }
    }

    // MARK: use

    @Test func aUseOfItselfDrawsNothing() throws {
        let r = try read(svg(##"<use id="u" href="#u"/><rect width="10" height="10"/>"##))
        #expect(r.layer.children.count == 1)
    }

    @Test func aGroupUsingItselfIsDrawnOnce() throws {
        let r = try read(svg(##"<g id="g"><rect width="10" height="10"/><use href="#g"/></g>"##))
        #expect(r.layer.children.count == 1)
    }

    @Test func usesThatReachEachOtherStop() throws {
        let r = try read(svg(##"<defs><g id="a"><use href="#b"/></g><g id="b"><use href="#a"/><rect width="5" height="5"/></g></defs><use href="#a"/>"##))
        #expect(allFinite([r.layer]))
    }

    @Test func usesThatMultiplyPastTheLimitAreRefused() {
        // Ten of the one before at each of eight levels: a hundred million.
        var defs = #"<rect id="l0" width="1" height="1"/>"#
        for level in 1...8 {
            let uses = String(repeating: ##"<use href="#l\##(level - 1)"/>"##, count: 10)
            defs += #"<g id="l\#(level)">\#(uses)</g>"#
        }
        #expect(throws: SVGImport.ReadError.tooComplex) { try read(svg("<defs>\(defs)</defs><use href=\"#l8\"/>")) }
    }

    @Test func nestingPastTheLimitIsRefused() {
        // Deep enough to crash the system's own XML reader, on any thread.
        let deep = String(repeating: "<g>", count: 100_000) + #"<rect width="1" height="1"/>"# + String(repeating: "</g>", count: 100_000)
        #expect(throws: SVGImport.ReadError.tooComplex) { try read(svg(deep)) }
    }

    @Test func nestingIsCountedFromTheBytes() {
        let text = ##"<?xml version="1.0"?><!DOCTYPE svg><svg a=">"><!-- <g><g><g> --><g><rect/><![CDATA[<g><g>]]><g b='/>'></g></g></svg>"##
        #expect(SVGImport.nesting(of: Data(text.utf8), limit: 100) == 3)
    }

    // MARK: Numbers

    @Test func aHugeArcIsReadWithoutCrashing() throws {
        let p = SVGPathData.parse("M0 0 A1 1 0 0 1 1e200 0 L5 5")
        #expect(p.subpaths.allSatisfy { $0.points.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite } })
        let r = try read(svg(#"<path d="M0 0 A1 1 0 0 1 1e200 0"/>"#))
        #expect(allFinite([r.layer]))
    }

    @Test func infinitiesAndNotNumbersAreNotNumbers() {
        for text in ["inf", "-infinity", "nan", "1e999", "2e9"] {
            #expect(SVGNumber.parse(text) == nil)
        }
        #expect(SVGNumber.parse("12px") == 12)
    }

    @Test func runawayScalesLeaveTheLayerOut() throws {
        let scales = String(repeating: #"<g transform="scale(1e9)">"#, count: 40)
        let r = try read(svg(scales + #"<rect width="10" height="10"/>"# + String(repeating: "</g>", count: 40)
                             + #"<rect width="10" height="10" opacity="nan" transform="scale(inf)"/>"#))
        #expect(allFinite([r.layer]))
    }

    // MARK: Entities

    @Test func anEntityReadingAFileIsRefused() throws {
        let secret = FileManager.default.temporaryDirectory.appendingPathComponent("twine-entity-\(UUID().uuidString).txt")
        try "secret".write(to: secret, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: secret) }
        let doctype = #"<!DOCTYPE svg [<!ENTITY x SYSTEM "\#(secret.absoluteString)">]>"#
        #expect(throws: SVGImport.ReadError.entities) { try read(svg("<text>&x;</text>", doctype: doctype)) }
    }

    @Test func entitiesMadeOfEntitiesAreRefused() {
        let doctype = #"<!DOCTYPE svg [<!ENTITY a "aaaaaaaaaa"><!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">]>"#
        #expect(throws: SVGImport.ReadError.entities) { try read(svg("<text>&b;</text>", doctype: doctype)) }
    }

    @Test func illustratorsPlainEntitiesStillRead() throws {
        let doctype = #"<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd" [<!ENTITY ns_svg "http://www.w3.org/2000/svg">]>"#
        let r = try read(svg(#"<rect width="10" height="10"/>"#, doctype: doctype))
        #expect(r.layer.children.count == 1)
    }

    // MARK: Figma

    @Test func aFigmaPasteWithHugeValuesIsReadSafely() throws {
        let png = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                                                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)?
            .representation(using: .png, properties: [:])).base64EncodedString()
        let json = ##"""
        {"format": "twine.figma", "version": 1, "images": {"p": "\##(png)"}, "nodes": [
          {"kind": "rectangle", "name": "R", "transform": [1, 0, 0, 1, 0, 0], "width": 10, "height": 10,
           "fills": [{"type": "IMAGE", "image": "p", "scaleMode": "FIT", "rotation": 1e300}]},
          {"kind": "star", "name": "S", "transform": [1, 0, 0, 1, 0, 0], "width": 10, "height": 10, "count": 2000000000},
          {"kind": "polygon", "name": "P", "transform": [1, 0, 0, 1, 0, 0], "width": 10, "height": 10, "count": 2000000000},
          {"kind": "rectangle", "name": "Far", "transform": [1e300, 0, 0, 1e300, 1e300, 0], "width": 1e300, "height": 10}]}
        """##
        let r = try FigmaImport.read(json)
        #expect(allFinite(r.layers))
        #expect(r.layers.map(\.name) == ["R", "S", "P"])
        guard case .star(let points, _, _)? = r.layers.first(where: { $0.name == "S" })?.look?.geometry,
              case .polygon(let sides, _)? = r.layers.first(where: { $0.name == "P" })?.look?.geometry else {
            Issue.record("no star or polygon")
            return
        }
        #expect(points == FigmaImport.maxPoints && sides == FigmaImport.maxPoints)
    }

    // MARK: Encodings (4 October 2026)

    /// Ten times the one before, at each of eight levels: a billion letters.
    private var laughs: String {
        var entities = #"<!ENTITY a0 "aaaaaaaaaa">"#
        for level in 1...8 { entities += "<!ENTITY a\(level) \"" + String(repeating: "&a\(level - 1);", count: 10) + "\">" }
        return #"<?xml version="1.0" encoding="UTF-16"?><!DOCTYPE svg [\#(entities)]><svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><text>&a8;</text></svg>"#
    }

    @Test func entitiesInUTF16AreStillSeen() throws {
        var marked = Data([0xFF, 0xFE])
        marked.append(try #require(laughs.data(using: .utf16LittleEndian)))
        #expect(throws: SVGImport.ReadError.entities) { try read(marked) }
        let unmarked = try #require(laughs.data(using: .utf16BigEndian))
        #expect(throws: SVGImport.ReadError.entities) { try read(unmarked) }
        let wide = try #require(laughs.data(using: .utf32LittleEndian))
        #expect(throws: SVGImport.ReadError.entities) { try read(wide) }
    }

    @Test func aPlainSVGInUTF16StillReads() throws {
        let text = #"<?xml version="1.0" encoding="UTF-16"?><svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><rect width="10" height="10"/></svg>"#
        var data = Data([0xFE, 0xFF])
        data.append(try #require(text.data(using: .utf16BigEndian)))
        #expect(try read(data).layer.children.count == 1)
    }

    @Test func onlyEncodingsThatWriteLettersAsThemselvesAreRead() throws {
        let body = #"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><rect width="10" height="10"/></svg>"#
        // Plain bytes claiming to be wide would be read as something else.
        #expect(throws: SVGImport.ReadError.notSVG) { try read(Data((#"<?xml version="1.0" encoding="UTF-16"?>"# + body).utf8)) }
        #expect(throws: SVGImport.ReadError.notSVG) { try read(Data((#"<?xml version="1.0" encoding="IBM037"?>"# + body).utf8)) }
        #expect(throws: SVGImport.ReadError.notSVG) { try read(Data(body.utf8) + Data([0])) }
        for name in ["UTF-8", "iso-8859-1", "windows-1252", "US-ASCII"] {
            #expect(try read(Data((#"<?xml version="1.0" encoding='\#(name)'?>"# + body).utf8)).layer.children.count == 1)
        }
    }

    // MARK: What the system draws

    /// `<use>`s ten of the one before at each of nine levels, in `defs`,
    /// where the reader never walks.
    private var multiplyingDefinitions: String {
        var defs = #"<rect id="l0" width="1" height="1"/>"#
        for level in 1...9 {
            defs += #"<g id="l\#(level)">"# + String(repeating: ##"<use href="#l\##(level - 1)"/>"##, count: 10) + "</g>"
        }
        return defs
    }

    @Test func usesMultiplyingInsideATextsPatternAreRefused() {
        let pattern = ##"<pattern id="p" width="10" height="10" patternUnits="userSpaceOnUse"><use href="#l9"/></pattern>"##
        let started = Date()
        #expect(throws: SVGImport.ReadError.tooComplex) {
            try read(svg("<defs>\(pattern)\(multiplyingDefinitions)</defs><text y=\"20\" fill=\"url(#p)\">Hi</text>"))
        }
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test func aPictureCarriesOnlyTheDefinitionsItUses() throws {
        let gradient = #"<linearGradient id="g"><stop offset="0" stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient>"#
        let started = Date()
        let r = try read(svg("<defs>\(gradient)\(multiplyingDefinitions)</defs><text y=\"20\" font-size=\"20\" fill=\"url(#g)\">Hi</text>"))
        #expect(r.pictureCount == 1)
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test func picturesDrawnTogetherKeepToTheBudget() throws {
        let texts = String(repeating: #"<text y="20" font-size="20">Hi</text>"#, count: 3)
        let budget = SVGImport.Budget()
        budget.pixels = SVGPictures.pixels(size: Size2(100, 100), scale: 2) * 2
        #expect(throws: SVGImport.ReadError.tooComplex) {
            try SVGImport.read(svg(texts), name: "Test", center: Vec2(50, 50), budget: budget)
        }
        #expect(try SVGImport.read(svg(texts), name: "Test", center: Vec2(50, 50)).pictureCount == 3)
    }

    /// A real PNG one pixel wider than any picture taken in. (ImageIO
    /// itself refuses one whose data is too short for the size it claims.)
    private var tooWide: String {
        get throws {
            let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: FileSafety.largestPictureSide + 1, pixelsHigh: 1,
                                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            return try #require(rep.representation(using: .png, properties: [:])).base64EncodedString()
        }
    }

    @Test func aPictureTooLargeIsLeftOut() throws {
        let png = try tooWide
        #expect(SVGPictures.pixelSize(of: try #require(Data(base64Encoded: png))) == Size2(Double(FileSafety.largestPictureSide + 1), 1))
        let r = try read(svg(#"<image width="10" height="10" href="data:image/png;base64,\#(png)"/><rect width="5" height="5"/>"#))
        #expect(r.media.isEmpty)
        #expect(r.layer.children.count == 1)
        #expect(FileSafety.pictureFits(width: 4096, height: 4096))
        #expect(!FileSafety.pictureFits(width: 16_385, height: 10))
        #expect(!FileSafety.pictureFits(width: 12_000, height: 12_000))
    }

    @Test func aFigmaPasteWithHugeTextAndGiantPicturesIsHeld() throws {
        let json = ##"""
        {"format": "twine.figma", "version": 1, "images": {"p": "\##(try tooWide)"}, "nodes": [
          {"kind": "text", "name": "T", "transform": [1, 0, 0, 1, 0, 0], "width": 200, "height": 40,
           "text": {"characters": "Hi", "family": "Helvetica", "style": "Regular", "size": 1e300, "letterSpacing": -1e300, "lineHeight": 1e400}},
          {"kind": "rectangle", "name": "R", "transform": [1, 0, 0, 1, 0, 0], "width": 10, "height": 10,
           "strokeWeight": 1e300, "fills": [{"type": "IMAGE", "image": "p", "scaleMode": "FILL"}],
           "effects": [{"type": "LAYER_BLUR", "radius": 1e300}]}]}
        """##
        let r = try FigmaImport.read(json)
        guard case .text(let t) = r.layers.first?.content else { Issue.record("not text"); return }
        #expect(t.fontSize == FileSafety.fontSizes.upperBound)
        #expect(t.letterSpacing == -FileSafety.limit && t.lineHeight == FileSafety.limit)
        #expect(r.media.isEmpty)
        #expect(r.layers.last?.look?.strokes.first?.width ?? 0 <= FileSafety.limit)
    }

    @Test func aFigmaPasteOfManyDrawnSVGsIsRefusedAsAWhole() throws {
        let one = #"<svg xmlns='http://www.w3.org/2000/svg' width='1024' height='1024'><text y='20'>Hi</text></svg>"#
        let node = #"{"kind": "svg", "name": "S", "transform": [1, 0, 0, 1, 0, 0], "width": 1024, "height": 1024, "svg": "\#(one)", "bounds": [0, 0, 1024, 1024]}"#
        // Each draws 4 million pixels; a budget of two and a half stops at
        // the third, in place of the 4 billion pixels of a real paste,
        // which take about ten seconds in a release build.
        let json = #"{"format": "twine.figma", "version": 1, "images": {}, "nodes": ["# + Array(repeating: node, count: 5).joined(separator: ",") + "]}"
        let budget = SVGImport.Budget()
        budget.pixels = SVGPictures.pixels(size: Size2(1024, 1024), scale: 2) * 2.5
        #expect(throws: FigmaImport.ReadError.tooComplex) { try FigmaImport.read(json, budget: budget) }
        #expect(budget.pixels < 0)
    }
}
