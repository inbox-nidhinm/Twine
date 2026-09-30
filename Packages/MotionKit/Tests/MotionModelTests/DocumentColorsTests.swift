import Foundation
import Testing
@testable import MotionModel

@Suite struct DocumentColorsTests {
    private func shape(_ paints: [Paint], stroke: Paint? = nil) -> Layer {
        Layer(name: "S", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                      fills: paints.map { Fill(paint: $0) },
                                                      strokes: stroke.map { [Stroke(paint: $0)] } ?? [])),
              size: Size2(10, 10), position: Vec2(0, 0))
    }

    @Test func mostUsedComeFirstAndRepeatsCountOnce() {
        let red = RGBA(1, 0, 0), blue = RGBA(0, 0, 1)
        var project = Project(layers: [shape([.color(blue)]), shape([.color(red)]), shape([.color(red)], stroke: .color(red))])
        project.composition.background = Background(color: .white)
        let colors = project.documentColors()
        #expect(colors.first == red)
        #expect(colors.count == 3)
        #expect(colors.contains(blue) && colors.contains(.white))
    }

    @Test func gradientsShadowsTextAndActionsCount() {
        let a = RGBA(0.1, 0.2, 0.3), b = RGBA(0.4, 0.5, 0.6), s = RGBA(0, 0, 0, 0.25), t = RGBA(0.9, 0.1, 0.1), e = RGBA(0.2, 0.9, 0.2)
        var layer = shape([.linearGradient(Gradient(stops: [GradientStop(position: 0, color: a), GradientStop(position: 1, color: b)]))])
        layer.effects = [Effect(kind: .dropShadow(DropShadow(color: s)))]
        var text = Layer(name: "T", content: .text(TextContent(text: "Hi")), size: Size2(10, 10), position: Vec2(0, 0))
        if case .text(var content) = text.content { content.color = t; text.content = .text(content) }
        let action = Action(target: layer.id, start: 0, duration: 1, name: "Colour", spec: .color(ColorAction(end: .color(e))))
        var project = Project(layers: [layer, text], actions: [action])
        project.composition.background = Background(color: .white, isTransparent: true)
        let colors = Set(project.documentColors())
        #expect(colors == [a, b, s, t, e])
    }

    @Test func nearlyEqualColoursAreOneAndTheListIsCapped() {
        let layers = (0..<30).map { i in shape([.color(RGBA(Double(i) / 30, 0, 0))]) }
            + [shape([.color(RGBA(0.5, 0.5, 0.5))]), shape([.color(RGBA(0.5 + 0.0001, 0.5, 0.5))])]
        let colors = Project(layers: layers).documentColors(limit: 16)
        #expect(colors.count == 16)
        #expect(colors.first == RGBA(0.5, 0.5, 0.5))
    }
}
