import Foundation
import Testing
import MotionModel
import MotionEvaluation
@testable import MotionEditing

@Suite struct StyleCopyingTests {
    private let red = RGBA(1, 0, 0), blue = RGBA(0, 0, 1)

    private func shape(fills: [Fill], strokes: [Stroke] = []) -> Layer {
        Layer(name: "S", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: CornerRadii(all: 8)), fills: fills, strokes: strokes)),
              size: Size2(100, 50), position: Vec2(10, 10))
    }

    private func text(_ words: String, size: Double = 24, color: RGBA = .white) -> Layer {
        Layer(name: "T", content: .text(TextContent(text: words, fontFamily: "SF Pro", fontWeight: 400, fontSize: size, color: color)),
              size: Size2(10, 10), position: .zero)
    }

    @Test func aShapeTakesFillsStrokesEffectsOpacityAndBlendUnderNewIDs() {
        var source = shape(fills: [Fill(paint: .solid(red))], strokes: [Stroke(paint: .solid(blue), width: 3)])
        source.opacity = 0.5
        source.blendMode = .multiply
        source.effects = [Effect(kind: .dropShadow(DropShadow()))]
        let style = LayerStyle(of: source)
        let target = shape(fills: [Fill(paint: .solid(.white))])
        let pasted = style.applied(to: target, media: [])
        #expect(pasted.id == target.id && pasted.transform == target.transform && pasted.size == target.size)
        #expect(pasted.opacity == 0.5 && pasted.blendMode == .multiply)
        #expect(pasted.look?.fills.map(\.paint) == [.solid(red)])
        #expect(pasted.look?.strokes.first?.width == 3)
        #expect(pasted.effects.map(\.kind) == source.effects.map(\.kind))
        // Its own outline stays: the corners are the target's.
        #expect(pasted.look?.geometry == target.look?.geometry)
        // Nothing shares an id with the source.
        #expect(pasted.look?.fills.first?.id != source.look?.fills.first?.id)
        #expect(pasted.look?.strokes.first?.id != source.look?.strokes.first?.id)
        #expect(pasted.effects.first?.id != source.effects.first?.id)
    }

    @Test func aTextTakesAnotherTextsTypeButKeepsItsWords() {
        var source = text("Hello", size: 72, color: red)
        if case .text(var t) = source.content {
            t.fontWeight = 700
            t.alignment = .center
            t.letterSpacing = 4
            t.stroke = Stroke(paint: .solid(blue), width: 2)
            source.content = .text(t)
        }
        let pasted = LayerStyle(of: source).applied(to: text("Bye"), media: [])
        guard case .text(let t) = pasted.content else { Issue.record("not text"); return }
        #expect(t.text == "Bye")
        #expect(t.fontSize == 72 && t.fontWeight == 700 && t.alignment == .center && t.letterSpacing == 4)
        #expect(t.color == red && t.stroke?.width == 2)
    }

    @Test func colourAndStrokeCarryBetweenTextAndShapes() {
        // A shape's top fill and first stroke onto a text, one colour each.
        let gradient = Paint.linearGradient(Gradient(stops: [GradientStop(position: 0, color: blue), GradientStop(position: 1, color: red)]))
        let source = shape(fills: [Fill(paint: .solid(.white)), Fill(paint: gradient)], strokes: [Stroke(paint: gradient, width: 5)])
        guard case .text(let t) = LayerStyle(of: source).applied(to: text("A"), media: []).content else { Issue.record("not text"); return }
        #expect(t.color == blue && t.showsFill)
        #expect(t.stroke?.paint == .solid(blue) && t.stroke?.width == 5)
        // A text's colour and stroke onto a shape.
        let onShape = LayerStyle(of: text("A", color: red)).applied(to: shape(fills: []), media: [])
        #expect(onShape.look?.fills.map(\.paint) == [.solid(red)])
        #expect(onShape.look?.strokes.isEmpty == true)
    }

    @Test func picturesFromElsewhereAreLeftOutAndSoundsTakeNothing() {
        let known = UUID(), stranger = UUID()
        let source = shape(fills: [Fill(paint: .image(ImagePaint(mediaID: known))), Fill(paint: .image(ImagePaint(mediaID: stranger)))])
        let pasted = LayerStyle(of: source).applied(to: shape(fills: []), media: [known])
        #expect(pasted.look?.fills.count == 1)
        let sound = Layer(name: "A", content: .audio(AudioContent(mediaID: UUID())), size: Size2(0, 0), position: .zero)
        #expect(LayerStyle(of: source).applied(to: sound, media: [known]) == sound)
    }

    @Test func aGroupTakesOnlyWhatEveryLayerHas() {
        var source = shape(fills: [Fill(paint: .solid(red))])
        source.opacity = 0.3
        let group = LayerFactory.group(in: Box(origin: .zero, size: Size2(10, 10)), children: [], name: "G")
        let pasted = LayerStyle(of: source).applied(to: group, media: [])
        #expect(pasted.opacity == 0.3 && pasted.look == nil && pasted.children == group.children)
    }
}
