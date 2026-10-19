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
        let files = [a, b].map { MediaAsset(id: $0, kind: .image, fileName: "\($0).png", originalName: "p.png", contentHash: "\($0)",
                                            pixelWidth: 400, pixelHeight: 300) }
        let store = store(Project(composition: Composition(width: 1280, height: 720, duration: 6), layers: [pa, pb, text], media: files))
        let (command, id) = Templates.adding(.ringStream, to: store.project, replacing: [pa, pb, text])
        try store.perform(command)
        let frame = try #require(store.project.layer(withID: id))
        #expect(frame.templateSlots.prefix(2) == [a, b])
        #expect(frame.templateSlots.count == 12)
        // Slots are the frame's children, slot 1 the last (the top of the layers panel).
        #expect(frame.children.count == 12 && frame.children.last?.slotMedia == a)
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
        func cards(at t: Double) -> [ResolvedLayer] {
            evaluate(store.project, at: t).layers.filter { $0.parentID == id && $0.placed.backOf == nil }
        }
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

    // MARK: Videos in slots

    private func clip(seconds: Double) -> MediaAsset {
        MediaAsset(kind: .video, fileName: "clip.mov", originalName: "clip.mov", contentHash: "c",
                   pixelWidth: 1920, pixelHeight: 1080, duration: seconds, hasAudio: true)
    }

    @Test func aVideoInASlotPlaysRoundInARoundedCard() throws {
        let video = clip(seconds: 3)
        var frame = Templates.frame(.slideCarousel, filling: Composition(width: 1280, height: 720), pictures: [video])
        frame.templateSlotLayers = [TemplateSlots.layer(video, in: frame.size)]
        let bar = Action(target: frame.id, start: 0, duration: 8, easing: .linear, rowOrder: 0, spec: .template(TemplatePlay()))
        let project = Project(composition: Composition(width: 1280, height: 720, duration: 8), layers: [frame], actions: [bar],
                              media: [video])
        let scene = evaluate(project, at: 7.5)
        let videos = scene.layers.filter { if case .video = $0.content { return true } else { return false } }
        #expect(!videos.isEmpty)
        for v in videos {
            // Muted, inside a card frame that rounds and clips it, at 7.5 s into a 3 s clip.
            guard case .video(let media, let time, _) = v.content else { continue }
            #expect(media == video.id && abs(time - 1.5) < 1e-9)
            let card = try #require(v.parentID)
            #expect(TemplateCards.isCard(card, of: frame.id))
            #expect(!TemplateCards.isCard(v.id, of: frame.id) && !TemplateCards.isCard(v.id, of: card))
        }
        // Split, each video plays on with Play bars back to back, as long as the scene.
        let command = try #require(Templates.split(frame.id, in: project))
        let store = store(project)
        try store.perform(command)
        let split = try #require(store.project.layer(withID: frame.id))
        let child = try #require(split.children.first?.children.first)
        if case .video(let content) = child.content { #expect(content.isMuted) } else { Issue.record("no video") }
        let plays = store.project.actions.filter { $0.targetLayerID == child.id && $0.spec.kind == .play }.sorted { $0.start < $1.start }
        #expect(plays.map(\.start) == [0, 3, 6] && plays.last?.duration == 2)
    }

    // MARK: Slots as layers

    /// A project saved before slots were layers reads its slot list into
    /// slot children, in order, a video as a video and a missing file empty.
    @Test func olderSlotListsBecomeChildren() throws {
        let picture = MediaAsset(kind: .image, fileName: "a.png", originalName: "Sunset.png", contentHash: "a", pixelWidth: 400, pixelHeight: 200)
        let video = clip(seconds: 2)
        let frame = Templates.frame(.ringStream, filling: Composition(width: 1280, height: 720))
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(frame)) as! [String: Any]
        var content = json["content"] as! [String: Any]
        var group = content["group"] as! [String: Any]
        var template = group["template"] as! [String: Any]
        template["slots"] = [picture.id.uuidString, NSNull(), video.id.uuidString, UUID().uuidString]
        group["template"] = template
        group["children"] = []
        content["group"] = group
        json["content"] = content
        let old = try JSONDecoder().decode(Layer.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.template?.legacySlots?.count == 4 && old.children.isEmpty)
        let project = TemplateSlots.converted(Project(layers: [old], media: [picture, video]))
        let converted = try #require(project.layers.first)
        #expect(converted.template?.legacySlots == nil)
        #expect(converted.templateSlots == [picture.id, nil, video.id, nil])
        #expect(converted.templateSlotLayers[0].name == "Sunset")
        if case .video(let v) = converted.templateSlotLayers[2].content { #expect(v.isMuted) } else { Issue.record("not a video") }
        // Nothing to convert leaves the project as it is.
        #expect(TemplateSlots.converted(project) == project)
    }

    /// A slot is never drawn, played or animated itself.
    @Test func slotsTakeNoActionsOrPlayBars() throws {
        let video = clip(seconds: 2)
        var frame = Templates.frame(.ringStream, filling: Composition(width: 1280, height: 720))
        frame.templateSlotLayers[0] = TemplateSlots.layer(video, in: frame.size)
        let project = MediaPlays.withPlayBars(Project(layers: [frame], media: [video]))
        #expect(project.actions.isEmpty)
        let slot = frame.templateSlotLayers[0]
        #expect(project.templateSlotIDs.contains(slot.id) && project.templateSlotIDs.count == 12)
        #expect(ActionFactory.kinds(for: slot, in: project).isEmpty)
        #expect(!ActionFactory.kinds(for: frame, in: project).isEmpty)
        #expect(audioClips(project).isEmpty)
        // The slots are not drawn: only the cards are.
        let drawn = evaluate(project, at: 0).layers.map(\.id)
        #expect(!drawn.contains(slot.id))
    }

    /// A double-click on a card goes in to the slot it shows.
    @Test func aCardKnowsItsSlot() throws {
        var frame = Templates.frame(.carouselRing, filling: Composition(width: 1280, height: 720))
        frame.templateSlotLayers = Array(frame.templateSlotLayers.prefix(5))
        let setup = try #require(frame.template)
        for index in 0..<5 {
            let card = TemplateCards.id(of: index, in: frame.id)
            #expect(TemplateCards.slot(of: card, in: frame, setup: setup, phase: setup.pose) == index)
        }
        #expect(TemplateCards.slot(of: UUID(), in: frame, setup: setup, phase: 0) == nil)
    }
}
