import Foundation
import Testing
import MotionModel
import MotionEvaluation
import MotionEditing
@testable import MotionImport

/// The copy the plugin itself makes (FigmaPlugin/test/run.js writes it from
/// a stand-in for Figma), read as Twine reads a paste: the two halves agree.
@Suite struct FigmaPluginSampleTests {
    private var sample: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../FigmaPlugin/test/sample-payload.json")
            .standardizedFileURL
    }

    @Test func thePluginsOwnCopyPastes() throws {
        let text = try String(contentsOf: sample, encoding: .utf8)
        let r = try FigmaImport.read(text)
        let card = try #require(r.layers.first)
        #expect(card.isFrame && card.name == "Card" && card.size == Size2(320, 200))
        #expect(r.bounds == Box(minX: 100, minY: 50, maxX: 420, maxY: 250))
        let names = card.children.map(\.name)
        #expect(names == ["Photo", "Title", "Mixed", "Leaning", "Slanted", "Sheared", "Icon", "Painted Regions", "Masked", "Rule", "Note"])
        let photo = card.children[0]
        #expect(photo.picture?.paint.mode == .fill && photo.transform.position == Vec2(76, 56))
        guard case .text(let title) = card.children[1].content else { Issue.record("title is not text"); return }
        #expect(title.fontFamily == "Inter" && title.fontWeight == 600 && abs(title.letterSpacing + 0.48) < 1e-9)
        #expect(card.children[2].picture != nil && card.children[3].picture != nil, "mixed and italic text are pictures")
        // Skewed in Figma, and still a shape and text, slanted as Figma has them.
        let slanted = card.children[4], sheared = card.children[5]
        #expect(slanted.look != nil && abs(slanted.transform.skew.x - atan(0.4) * 180 / .pi) < 1e-9)
        guard case .text = sheared.content else { Issue.record("sheared is not text"); return }
        #expect(abs(sheared.transform.skew.x - atan(0.3) * 180 / .pi) < 1e-9)
        #expect(card.children[6].look?.fillRule == .evenOdd)
        #expect(card.children[7].isGroup, "Figma's SVG, read into a group")
        let masked = card.children[8]
        #expect(masked.children[1].mask?.layerID == masked.children[0].id)
        #expect(card.effects.count == 1 && r.warnings.count == 1)
        // The stand-in gives the photo and every drawing the same bytes,
        // which are kept once.
        #expect(r.media.count == 1)
    }
}
