import Foundation
import Testing
import MotionModel
import MotionEvaluation
@testable import MotionEditing

/// Adding templates and splitting them into layers.
@Suite @MainActor struct TemplateEditingTests {
    private func store(_ project: Project) -> ProjectStore {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return ProjectStore(project: project, undoManager: undo)
    }

    private func picture(_ media: UUID) -> Layer {
        Layer(name: "P", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                     fills: [Fill(paint: .image(ImagePaint(mediaID: media)))])),
              size: Size2(100, 100), position: Vec2(50, 50))
    }

    @Test func theLibraryHasEveryTemplate() {
        #expect(Templates.library.count == 69)
        #expect(Set(Templates.library.map(\.kind)) == Set(TemplateKind.allCases))
        #expect(Set(Templates.library.map(\.name)).count == 69)
        #expect(Templates.library.filter { $0.group == .isometric }.count == 3)
        #expect(Templates.library.filter { $0.group == .orbit }.count == 8)
        let counts = Dictionary(grouping: Templates.library, by: \.group).mapValues(\.count)
        #expect(counts[.flow] == 10 && counts[.grid] == 8 && counts[.spotlight] == 4 && counts[.reveal] == 4 && counts[.stack] == 7)
        #expect(counts[.sequence] == 13)
    }

    @Test func addingTakesTheSelectedPicturesIntoItsSlots() throws {
        let a = UUID(), b = UUID()
        let pa = picture(a), pb = picture(b)
        let text = LayerFactory.text(at: .zero, name: "T")
        let store = store(Project(composition: Composition(width: 1280, height: 720, duration: 6), layers: [pa, pb, text]))
        let (command, id) = Templates.adding(.ringStream, to: store.project, replacing: [pa, pb, text])
        try store.perform(command)
        let frame = try #require(store.project.layer(withID: id))
        #expect(frame.template?.slots.prefix(2) == [a, b])
        #expect(frame.template?.slots.count == 12)
        #expect(frame.size == Size2(1280, 720))
        // The pictures went in; the text stays.
        #expect(store.project.layer(withID: pa.id) == nil && store.project.layer(withID: pb.id) == nil)
        #expect(store.project.layer(withID: text.id) != nil)
        // Its bar spans the scene.
        let bar = try #require(store.project.actions.first { $0.targetLayerID == id })
        #expect(bar.start == 0 && bar.duration == 6 && bar.spec == .template(TemplatePlay()))
        // One step to undo.
        store.undoManager.undo()
        #expect(store.project.layer(withID: id) == nil && store.project.layer(withID: pa.id) != nil)
    }

    @Test func splittingMakesRealCardsThatPlayTheSame() throws {
        let store = store(Project(composition: Composition(width: 1280, height: 720, duration: 4)))
        let (add, id) = Templates.adding(.photoLoop, to: store.project)
        try store.perform(add)
        let before = store.project
        let command = try #require(Templates.split(id, in: store.project))
        try store.perform(command)
        let frame = try #require(store.project.layer(withID: id))
        #expect(frame.template == nil && frame.space3D != nil)
        #expect(frame.children.count == 8)
        #expect(!store.project.actions.contains { $0.spec.kind == .template })
        #expect(store.project.scenes.last?.name == "Photo Loop")
        // At every step it is where the template was.
        for k in [0, 5, 12, 23] {
            let t = 4 * Double(k) / Double(Templates.splitSteps)
            let template = evaluate(before, at: t).layers.filter { $0.parentID == id }.map(\.projection)
            let split = evaluate(store.project, at: t).layers.filter { $0.parentID == id }.map(\.projection)
            #expect(template.count == split.count)
            for (a, b) in zip(template, split) {
                let p = Vec2(10, 10)
                #expect(abs(a.apply(p)!.x - b.apply(p)!.x) < 0.01 && abs(a.apply(p)!.y - b.apply(p)!.y) < 0.01, "at step \(k)")
            }
        }
        #expect(Templates.split(frame.children[0].id, in: store.project) == nil)
    }

    @Test func aSplitSequencePlaysTheSameAtEveryStep() throws {
        let store = store(Project(composition: Composition(width: 1280, height: 720, duration: 8)))
        let (add, id) = Templates.adding(.ringBelt, to: store.project)
        try store.perform(add)
        let before = store.project
        try store.perform(try #require(Templates.split(id, in: store.project)))
        let steps = Templates.splitSteps(for: .ringBelt)
        #expect(steps == Templates.splitSteps * 2)
        for k in stride(from: 0, to: steps, by: 7) {
            let t = 8 * Double(k) / Double(steps)
            let template = evaluate(before, at: t).layers.filter { $0.parentID == id && $0.opacity > 0.01 }.map(\.projection)
            let split = evaluate(store.project, at: t).layers.filter { $0.parentID == id && $0.opacity > 0.01 }.map(\.projection)
            #expect(template.count == split.count, "at step \(k)")
            for (a, b) in zip(template, split) {
                let p = Vec2(10, 10)
                #expect(abs(a.apply(p)!.x - b.apply(p)!.x) < 0.05 && abs(a.apply(p)!.y - b.apply(p)!.y) < 0.05, "at step \(k)")
            }
        }
    }

    /// A wheel turning twice over its bar keeps turning the same way when
    /// split: no step turns back the long way round.
    @Test func splitTurnsNeverSpinBack() throws {
        let store = store(Project(composition: Composition(width: 1280, height: 720, duration: 8)))
        let (add, id) = Templates.adding(.wheel, to: store.project)
        try store.perform(add)
        var bar = try #require(store.project.actions.first { $0.targetLayerID == id })
        bar.spec = .template(TemplatePlay(loops: 2))
        try store.perform(.updateActions([bar]))
        try store.perform(try #require(Templates.split(id, in: store.project)))
        let card = try #require(store.project.layer(withID: id)?.children.first)
        let turns = store.project.actions.filter { $0.targetLayerID == card.id }.sorted { $0.start < $1.start }
            .compactMap { action -> Double? in if case .rotate(let r) = action.spec { return r.end } else { return nil } }
        #expect(turns.count > 40)
        var last = card.transform.rotation
        for turn in turns {
            #expect(abs(turn - last) < 90)
            last = turn
        }
        #expect(abs(last - card.transform.rotation) > 700)
    }

    // MARK: Template Setting actions

    private func setting(_ key: String, on frame: UUID, from start: Double, length: Double, to end: Double,
                         initial: Double? = nil, row: Int = 10) -> Action {
        Action(target: frame, start: start, duration: length, easing: .linear, rowOrder: row,
               spec: .templateSetting(TemplateSettingAction(key: key, initial: initial, end: end)))
    }

    @Test func aSettingMovesOverItsBar() throws {
        let store = store(Project(composition: Composition(width: 1280, height: 720, duration: 8)))
        let (add, id) = Templates.adding(.ringStream, to: store.project)
        try store.perform(add)
        try store.perform(.insertActions([setting("count", on: id, from: 2, length: 2, to: 24),
                                          setting(TemplateSettingAction.cornerRadius, on: id, from: 0, length: 1, to: 30, row: 11)]))
        func cards(at t: Double) -> [ResolvedLayer] { evaluate(store.project, at: t).layers.filter { $0.parentID == id } }
        // Before its bar the frame's own 12; after, 24; halfway, 18.
        #expect(cards(at: 1).count == 12)
        #expect(cards(at: 3).count == 18)
        #expect(cards(at: 5).count == 24)
        // Each setting is its own track: the radius moved by 1 s, the count still waiting.
        let state = ActionTracks(store.project.actions).state(of: store.project.layer(withID: id)!, at: 1.5)
        #expect(state.template.settings["count"] == 12)
        #expect(state.template.settings[TemplateSettingAction.cornerRadius] == 30)
        // A setting past its range is held to it.
        try store.perform(.insertActions([setting("count", on: id, from: 6, length: 0, to: 10_000, row: 12)]))
        #expect(cards(at: 7).count == 48)
        // The Add Action menu offers it on templates, and only there.
        let frame = try #require(store.project.layer(withID: id))
        #expect(ActionFactory.kinds(for: frame).contains(.templateSetting))
        #expect(!ActionFactory.kinds(for: LayerFactory.frame(in: Box(origin: .zero, size: Size2(10, 10)), name: "F")).contains(.templateSetting))
    }

    @Test func aSettingSwapsItsEnds() throws {
        var frame = Templates.frame(.ringStream, filling: Composition(width: 1280, height: 720))
        frame.template?.settings["tilt"] = .number(-10)
        let action = setting("tilt", on: frame.id, from: 0, length: 1, to: 20)
        let state = ActionTracks([action]).inheritedState(for: action, of: frame)
        let swapped = try #require(ActionGeometry.swappingEnds(action, from: state))
        #expect(swapped.spec == .templateSetting(TemplateSettingAction(key: "tilt", initial: 20, end: -10)))
        // It keeps in files.
        let read = try JSONDecoder().decode(Action.self, from: JSONEncoder().encode(swapped))
        #expect(read == swapped)
        // A new one moves the first setting a good way.
        let made = ActionFactory.make(.templateSetting, for: frame, at: 0, state: LayerState(design: frame),
                                      frameRate: .fps30, rowOrder: 0)
        guard case .templateSetting(let t) = made.spec else { Issue.record("not a setting"); return }
        #expect(t.key == "count" && t.end > 12)
    }

    /// Splitting a template whose Cards setting grows makes every card that
    /// ever shows, and plays the same at every step.
    @Test func aSplitFollowsMovingSettings() throws {
        let store = store(Project(composition: Composition(width: 1280, height: 720, duration: 4)))
        let (add, id) = Templates.adding(.ringStream, to: store.project)
        try store.perform(add)
        try store.perform(.insertActions([setting("count", on: id, from: 0, length: 4, to: 20),
                                          setting("cardSize", on: id, from: 0, length: 4, to: 30, row: 11),
                                          setting(TemplateSettingAction.cornerRadius, on: id, from: 0, length: 4, to: 20, row: 12)]))
        let before = store.project
        try store.perform(try #require(Templates.split(id, in: store.project)))
        let frame = try #require(store.project.layer(withID: id))
        #expect(frame.children.count == 20)
        #expect(!store.project.actions.contains { $0.spec.kind == .templateSetting || $0.spec.kind == .template })
        for k in [0, 6, 13, 24] {
            let t = 4 * Double(k) / Double(Templates.splitSteps)
            let template = evaluate(before, at: t).layers.filter { $0.parentID == id && $0.opacity > 0.01 }
            let split = evaluate(store.project, at: t).layers.filter { $0.parentID == id && $0.opacity > 0.01 }
            #expect(template.count == split.count, "at step \(k)")
            for (a, b) in zip(template, split) {
                for p in [Vec2(0, 0), Vec2(a.size.width, a.size.height)] {
                    let pa = try #require(a.projection.apply(p)), pb = try #require(b.projection.apply(p))
                    #expect(abs(pa.x - pb.x) < 0.05 && abs(pa.y - pb.y) < 0.05, "at step \(k)")
                }
            }
        }
    }

    @Test func newFromTemplateHoldsOnlyTheTemplate() {
        let project = Templates.project(.diveIn, composition: Composition(width: 1080, height: 1080, duration: 5))
        #expect(project.composition.width == 1080 && project.composition.duration == 16)
        #expect(project.layers.count == 1 && project.layers[0].template?.kind == .diveIn)
        #expect(project.actions.count == 1 && project.actions[0].duration == 16 && project.actions[0].spec == .template(TemplatePlay()))
        #expect(Templates.project(.globe, composition: Composition()).composition.duration == 12)
    }
}
