import Foundation
import Testing
import MotionModel
import MotionEvaluation
@testable import MotionEditing

@MainActor
@Suite struct SelectionColorsTests {
    private let red = RGBA(1, 0, 0), blue = RGBA(0, 0, 1), green = RGBA(0, 1, 0)

    private func shape(_ fills: [Fill], strokes: [Stroke] = []) -> Layer {
        Layer(name: "S", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero), fills: fills, strokes: strokes)),
              size: Size2(10, 10), position: Vec2(0, 0))
    }

    private func shape(_ paint: Paint) -> Layer { shape([Fill(paint: paint)]) }

    private func group(_ children: [Layer]) -> Layer {
        Layer(name: "G", content: .group(GroupContent(children: children)), size: Size2(10, 10), position: Vec2(0, 0))
    }

    private func gradient(_ a: RGBA, _ b: RGBA, start: Vec2 = Vec2(0, 0.5)) -> Gradient {
        Gradient(stops: [GradientStop(position: 0, color: a), GradientStop(position: 1, color: b)], start: start)
    }

    private func fills(_ layer: Layer?) -> [Paint] { layer?.look?.fills.map(\.paint) ?? [] }

    @Test func listsEachColourOnceFrontFirstWithGradientsWhole() {
        let back = shape(.color(red)), middle = shape(.linearGradient(gradient(red, blue))), front = shape(.color(blue))
        let g = group([back, middle, front, shape(.color(red))])
        let project = Project(layers: [g])
        let entries = SelectionColors.entries(in: project, under: [g.id])
        #expect(entries.map(\.look) == [.color(red), .color(blue), .gradient(gradient(red, blue), .linear)])
        #expect(entries[0].places.count == 2)
        #expect(entries[1].places == [.fill(layer: front.id, id: front.look!.fills[0].id)])
    }

    @Test func nearlyEqualColoursAndMatchingGradientsCountOnce() {
        let a = shape(.color(RGBA(0.5, 0.5, 0.5))), b = shape(.color(RGBA(0.5001, 0.5, 0.5)))
        // The same stops in another direction are the same gradient.
        let c = shape(.linearGradient(gradient(red, blue))), d = shape(.linearGradient(gradient(red, blue, start: Vec2(0.5, 0))))
        let e = shape(.radialGradient(gradient(red, blue)))
        let project = Project(layers: [a, b, c, d, e])
        let entries = SelectionColors.entries(in: project, under: [a.id, b.id, c.id, d.id, e.id])
        #expect(entries.count == 3)
    }

    @Test func hiddenPaintsAndActionsFollowButAreNotListed() {
        var layer = shape([Fill(paint: .color(red)), Fill(isEnabled: false, paint: .color(blue)), Fill(isEnabled: false, paint: .color(red))])
        layer.effects = [Effect(kind: .dropShadow(DropShadow(color: RGBA(0, 0, 0, 0.25))))]
        let toRed = Action(target: layer.id, start: 0, duration: 1, name: "Colour", spec: .color(ColorAction(end: .color(red))))
        let toGreen = Action(target: layer.id, start: 1, duration: 1, name: "Colour", spec: .color(ColorAction(end: .color(green))))
        let project = Project(layers: [group([layer])], actions: [toRed, toGreen])
        let entries = SelectionColors.entries(in: project, under: [project.layers[0].id])
        #expect(entries.map(\.look) == [.color(red), .color(RGBA(0, 0, 0, 0.25))])
        #expect(entries[0].places.contains(.actionEnd(toRed.id)))
        #expect(!entries[0].places.contains(.actionEnd(toGreen.id)))
        #expect(entries[0].places.count == 3)
    }

    @Test func recolouringChangesEveryPlaceInOneStep() throws {
        let a = shape(.color(red)), b = shape(.color(red))
        var text = Layer(name: "T", content: .text(TextContent(text: "Hi", color: red)), size: Size2(10, 10), position: Vec2(0, 0))
        text.effects = [Effect(kind: .innerShadow(DropShadow(color: red)))]
        var frame = LayerFactory.frame(in: Box(origin: .zero, size: Size2(100, 100)), name: "F")
        frame.look?.fills = [Fill(paint: .color(red))]
        if case .group(var g) = frame.content {
            g.children = [a, group([b, text])]
            frame.content = .group(g)
        }
        let action = Action(target: b.id, start: 0, duration: 1, name: "Colour",
                            spec: .color(ColorAction(initial: .color(red), end: .color(blue))))
        let undo = UndoManager()
        undo.groupsByEvent = false
        let store = ProjectStore(project: Project(layers: [frame], actions: [action]), undoManager: undo)
        let entry = try #require(SelectionColors.entries(in: store.project, under: [frame.id]).first)
        #expect(entry.look == .color(red))
        let command = try #require(SelectionColors.setting(entry.places, to: green, in: store.project))
        try store.perform(command)
        let p = store.project
        #expect(fills(p.layer(withID: frame.id)) == [.color(green)])
        #expect(fills(p.layer(withID: a.id)) == [.color(green)])
        #expect(fills(p.layer(withID: b.id)) == [.color(green)])
        if case .text(let t) = p.layer(withID: text.id)?.content { #expect(t.color == green) } else { Issue.record("no text") }
        if case .innerShadow(let s) = p.layer(withID: text.id)?.effects.first?.kind { #expect(s.color == green) } else { Issue.record("no shadow") }
        if case .color(let c) = p.actions[0].spec {
            #expect(c.initial == .color(green))
            #expect(c.end == .color(blue))
        }
        undo.undo()
        #expect(fills(store.project.layer(withID: b.id)) == [.color(red)])
    }

    @Test func aGradientTakesNewStopsAndKeepsItsOwnDirectionAndKind() throws {
        let a = shape(.linearGradient(gradient(red, blue))), b = shape(.linearGradient(gradient(red, blue, start: Vec2(0.5, 0))))
        let project = Project(layers: [a, b])
        let entry = try #require(SelectionColors.entries(in: project, under: [a.id, b.id]).first)
        var edited = gradient(green, blue)
        edited.stops.append(GradientStop(position: 0.5, color: red))
        var p = project
        try SelectionColors.setting(entry.places, toStopsOf: edited, in: project)!.apply(to: &p)
        #expect(p.layer(withID: a.id)?.look?.fills[0].paint.gradient?.stops == edited.stops)
        #expect(p.layer(withID: b.id)?.look?.fills[0].paint.gradient?.start == Vec2(0.5, 0))
        #expect(p.layer(withID: b.id)?.look?.fills[0].paint.gradientKind == .linear)
    }

    @Test func aLayerInsideAnotherPickedOneCountsOnce() {
        let inner = shape(.color(red))
        let g = group([inner])
        let entries = SelectionColors.entries(in: Project(layers: [g]), under: [g.id, inner.id])
        #expect(entries.first?.places.count == 1)
    }
}
