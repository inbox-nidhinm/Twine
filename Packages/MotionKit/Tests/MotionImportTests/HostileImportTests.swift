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
              case .polygon(let sides)? = r.layers.first(where: { $0.name == "P" })?.look?.geometry else {
            Issue.record("no star or polygon")
            return
        }
        #expect(points == FigmaImport.maxPoints && sides == FigmaImport.maxPoints)
    }
}
