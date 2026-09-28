import Foundation
import Testing
import MotionModel
import MotionEvaluation
@testable import MotionEditing

/// A 100 by 100 square at (500, 300), half faded, turned 10 degrees.
private func square() -> Layer {
    var layer = Layer(name: "Square", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                                    fills: [Fill(paint: .color(.white))])),
                      size: Size2(100, 100), position: Vec2(500, 300))
    layer.opacity = 0.5
    layer.transform.rotation = 10
    return layer
}

private func bar(_ preset: Preset, on layer: Layer, at time: Double = 1) -> Action {
    Presets.action(preset, for: layer, at: time, frameRate: .fps60)
}

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-6 }
private func near(_ a: Vec2, _ b: Vec2) -> Bool { near(a.x, b.x) && near(a.y, b.y) }

@Suite struct PresetTests {
    @Test func theLibraryIsWellFormed() {
        #expect(Set(Presets.library.map(\.id)).count == Presets.library.count)
        // Every kind is in the library, itself or as the other half of a pair.
        let listed = Set(Presets.library.flatMap { [$0.kind] + ($0.kind.reversed.map { [$0] } ?? []) })
        #expect(listed == Set(PresetKind.allCases))
        // Pairs are listed by the half that brings a layer on.
        #expect(Presets.library.allSatisfy { $0.kind.entering != false })
        for kind in PresetKind.allCases {
            #expect(kind.reversed?.reversed == kind || kind.reversed == nil, "\(kind)")
            #expect((kind.reversed == nil) == (kind.entering == nil), "\(kind)")
        }
        for preset in PresetKind.allCases.map(Presets.preset) {
            #expect(!PresetRecipe.parts(PresetRecipe.defaults(preset.kind)).isEmpty, "\(preset.name)")
            let length = PresetRecipe.length(preset.kind)
            #expect(length > 0 && length <= 1, "\(preset.name)")
            // Every part fits inside the bar.
            for part in PresetRecipe.parts(PresetRecipe.defaults(preset.kind)) {
                #expect(part.start >= 0 && part.start + part.duration <= 1 + 1e-9, "\(preset.name)")
            }
        }
    }

    @Test func aPresetIsOneBar() throws {
        let layer = square()
        let action = bar(Presets.preset(.slideIn), on: layer)
        #expect(action.name == "Slide In")
        #expect(action.spec.kind == .preset)
        #expect(near(action.duration, 0.5))
        // It survives a file.
        let data = try JSONEncoder().encode(action)
        #expect(try JSONDecoder().decode(Action.self, from: data) == action)
    }

    @Test func entrancesLandOnTheLayerAsItWas() {
        for preset in PresetKind.allCases.filter({ $0.entering == true && !$0.isSound }).map(Presets.preset) {
            let layer = square()
            let action = bar(preset, on: layer)
            let tracks = ActionTracks([action])
            let end = tracks.state(of: layer, at: action.end + 0.01)
            #expect(near(end.position, Vec2(500, 300)), "\(preset.name)")
            #expect(near(end.opacity, 0.5), "\(preset.name)")
            #expect(near(end.scale, Vec2(1, 1)), "\(preset.name)")
            #expect(near(end.rotation, 10), "\(preset.name)")
            #expect(near(end.layerBlur, 0), "\(preset.name)")
            #expect(end.reveal == .none && end.tilt == layer.transform.tilt, "\(preset.name)")
            // Before it, the layer waits unseen: faded right out, or clipped away.
            let before = tracks.state(of: layer, at: 0.5)
            #expect(before.opacity == 0 || before.reveal.showsNothing, "\(preset.name)")
        }
    }

    @Test func exitsLeaveNothingToSee() {
        for preset in PresetKind.allCases.filter({ $0.entering == false && !$0.isSound }).map(Presets.preset) {
            let layer = square()
            let action = bar(preset, on: layer)
            let tracks = ActionTracks([action])
            let end = tracks.state(of: layer, at: action.end + 0.01)
            #expect(end.opacity < 1e-6 || end.scale.x < 1e-6 || end.reveal.showsNothing, "\(preset.name)")
            // Untouched until it starts.
            #expect(near(tracks.state(of: layer, at: 0.5).opacity, 0.5), "\(preset.name)")
        }
    }

    @Test func emphasisReturnsTheLayerToWhereItWas() {
        for preset in PresetKind.allCases.filter({ $0.entering == nil }).map(Presets.preset) {
            let layer = square()
            let action = bar(preset, on: layer)
            let tracks = ActionTracks([action])
            let end = tracks.state(of: layer, at: action.end + 0.01)
            #expect(near(end.position, Vec2(500, 300)) && near(end.scale, Vec2(1, 1)) && near(end.rotation, 10),
                    "\(preset.name)")
            let middle = tracks.state(of: layer, at: action.start + action.duration * 0.3)
            #expect(!(near(middle.position, Vec2(500, 300)) && near(middle.scale, Vec2(1, 1)) && near(middle.rotation, 10)),
                    "\(preset.name)")
        }
    }

    @Test func settingsChangeWhatItDoes() {
        let layer = square()
        var action = bar(Presets.preset(.slideIn), on: layer)
        // From the left by default: it starts 160 to the left.
        #expect(near(ActionTracks([action]).state(of: layer, at: 1).position, Vec2(340, 300)))
        guard case .preset(var settings) = action.spec else { Issue.record("not a preset"); return }
        settings.direction = .bottom
        settings.distance = 50
        settings.fades = false
        action.spec = .preset(settings)
        let tracks = ActionTracks([action])
        #expect(near(tracks.state(of: layer, at: 1).position, Vec2(500, 350)))
        // Without its fade, it is seen all the way in.
        #expect(near(tracks.state(of: layer, at: 1.1).opacity, 0.5))
    }

    @Test func stretchingTheBarStretchesEveryPart() {
        let layer = square()
        var action = bar(Presets.preset(.slideIn), on: layer, at: 0)
        action.easing = .preset(.none, intensity: 0)
        let normal = ActionTracks([action])
        var long = action
        long.duration = action.duration * 2
        let stretched = ActionTracks([long])
        // Halfway through the one is where halfway through the other is.
        for f in [0.1, 0.3, 0.5, 0.8] {
            let a = normal.state(of: layer, at: action.duration * f)
            let b = stretched.state(of: layer, at: long.duration * f)
            #expect(near(a.position, b.position) && near(a.opacity, b.opacity), "at \(f)")
        }
    }

    @Test func splittingPlaysTheSame() throws {
        // Every one but those that clip the layer, which no action does.
        for preset in PresetKind.allCases.filter({ !$0.isSound && Presets.splits(PresetRecipe.defaults($0)) }).map(Presets.preset) {
            var layer = square()
            // Something before it on the layer, so the split fixes the right values.
            let earlier = Action(target: layer.id, start: 0, duration: 0.5, spec: .move(MoveAction(mode: .by, end: Vec2(30, 0))))
            let action = bar(preset, on: layer)
            let whole = ActionTracks([earlier, action])
            let state = whole.inheritedState(for: action, of: layer)
            let parts = try #require(Presets.split(action, of: layer, from: state, frameRate: .fps60))
            #expect(parts.count > 1 || preset.kind == .fadeIn || preset.kind == .fadeOut, "\(preset.name)")
            let split = ActionTracks([earlier] + parts)
            // A shake's and a wiggle's jolts are a few frames long, and split
            // actions land on frames, so between them they differ a little;
            // they end in the same place.
            let jolts = preset.kind == .shake || preset.kind == .wiggle
            let times = jolts ? [0.5, action.end + 0.05] : Array(stride(from: 0.0, through: action.end + 0.2, by: 1.0 / 60))
            for t in times {
                let a = whole.state(of: layer, at: t), b = split.state(of: layer, at: t)
                #expect(abs(a.position.x - b.position.x) < 0.5 && abs(a.position.y - b.position.y) < 0.5
                        && abs(a.opacity - b.opacity) < 0.02 && abs(a.scale.x - b.scale.x) < 0.02
                        && abs(a.rotation - b.rotation) < 0.5 && abs(a.layerBlur - b.layerBlur) < 0.5,
                        "\(preset.name) at \(t)")
            }
            layer.opacity = 0.5
        }
    }

    @Test func aFadedOutLayerFadesBackToItsDesign() {
        var layer = square()
        let out = Action(target: layer.id, start: 0, duration: 0.5, spec: .opacity(OpacityAction(end: 0)))
        let fade = bar(Presets.preset(.fadeIn), on: layer)
        var tracks = ActionTracks([out, fade])
        #expect(near(tracks.state(of: layer, at: fade.end + 0.01).opacity, 0.5))
        layer.opacity = 0
        tracks = ActionTracks([out, fade])
        #expect(near(tracks.state(of: layer, at: fade.end + 0.01).opacity, 1))
    }

    @Test func onlyPresetsALayerCanTakeAreOffered() {
        let sound = Layer(name: "Sound", content: .audio(AudioContent(mediaID: UUID())), size: Size2(0, 0), position: .zero)
        let project = Project(layers: [sound, square()])
        let soundPresets = Presets.library.filter(\.isSound)
        #expect(soundPresets.count == 1)
        // A sound takes only the sound presets, a shape everything else.
        #expect(Presets.available(for: [sound], in: project) == soundPresets)
        let textPresets = Presets.library.filter(\.isText)
        #expect(Presets.available(for: [square()], in: project).count
                == Presets.library.count - soundPresets.count - textPresets.count)
        // A sound among layers that draw is left out rather than emptying the list.
        #expect(Presets.available(for: [square(), sound], in: project) == Presets.available(for: [square()], in: project))
    }

    @Test func soundPresetsSuitOnlyVideoWithSound() {
        let silent = MediaAsset(kind: .video, fileName: "s.mov", originalName: "s.mov", contentHash: "s", duration: 2)
        let loud = MediaAsset(kind: .video, fileName: "l.mov", originalName: "l.mov", contentHash: "l", duration: 2, hasAudio: true)
        let a = Layer(name: "A", content: .video(VideoContent(mediaID: silent.id)), size: Size2(10, 10), position: .zero)
        let b = Layer(name: "B", content: .video(VideoContent(mediaID: loud.id)), size: Size2(10, 10), position: .zero)
        var project = Project(layers: [a, b])
        project.media = [silent, loud]
        #expect(!Presets.available(for: [a], in: project).contains { $0.isSound })
        #expect(Presets.available(for: [b], in: project).contains { $0.kind == .fadeSoundIn })
        #expect(!ActionFactory.kinds(for: a, in: project).contains(.volume))
        #expect(ActionFactory.kinds(for: b, in: project).contains(.volume))
    }

    @Test func fadingSoundInComesUpToItsOwnLevelAtMost100Percent() {
        let sound = Layer(name: "Sound", content: .audio(AudioContent(mediaID: UUID(), volume: 1.5)), size: Size2(0, 0), position: .zero)
        let fade = bar(Presets.preset(.fadeSoundIn), on: sound, at: 0)
        #expect(fade.duration == 1)
        let tracks = ActionTracks([fade])
        #expect(tracks.state(of: sound, at: 0).volume == 0)
        #expect(tracks.state(of: sound, at: 1.01).volume == 1)
        // And the sound hears it: the fade reaches the clip's envelope.
        #expect(fade.drives(.volume))
    }

    @Test func barsAndSplitsLandOnFrames() throws {
        let layer = square()
        let shake = Presets.action(Presets.preset(.shake), for: layer, at: 1.004, frameRate: .fps30)
        #expect(abs((shake.start * 30).rounded() - shake.start * 30) < 1e-6)
        let parts = try #require(Presets.split(shake, of: layer, from: LayerState(design: layer), frameRate: .fps30))
        for a in parts {
            #expect(abs((a.start * 30).rounded() - a.start * 30) < 1e-6)
            #expect(abs((a.duration * 30).rounded() - a.duration * 30) < 1e-6)
        }
    }

    @Test func pairsAreNamedForTheirWay() {
        #expect(Presets.name(of: .fadeIn) == "Fade In")
        #expect(Presets.name(of: .fadeOut) == "Fade Out")
        #expect(Presets.name(of: .scalePop) == "Grow In")
        #expect(Presets.name(of: .maskSlideOut) == "Mask & Slide Out")
        #expect(Presets.name(of: .dropOut) == "Drop Out")
        #expect(Presets.name(of: .fadeSoundOut) == "Sound Fade Out")
        #expect(Presets.name(of: .shake) == "Shake")
        #expect(bar(Presets.library[0], on: square()).name == "Fade In")
    }

    @Test func eachPresetShowsItsOwnSettings() {
        #expect(Presets.controls(for: .slideIn) == [.direction, .distance, .fades])
        #expect(Presets.controls(for: .fadeIn).isEmpty)
        // A shake keeps its jolts' own easing, so it offers none.
        #expect(!PresetRecipe.usesEasing(.shake))
        #expect(PresetRecipe.usesEasing(.slideIn))
    }

    @Test func thePickerShowsEveryGroupInOrder() {
        // The library runs group by group, so the picker's headings each come once.
        let groups = Presets.library.map(\.group)
        let runs = groups.enumerated().filter { $0.offset == 0 || groups[$0.offset - 1] != $0.element }.map(\.element)
        #expect(runs == PresetGroup.allCases)
    }

    @Test func aMaskPresetClipsTheLayerToItsOwnBox() {
        let layer = square()
        var action = bar(Presets.preset(.maskResizeIn), on: layer, at: 0)
        action.easing = .preset(.none, intensity: 0)
        let tracks = ActionTracks([action])
        // Shut before, open halfway from the left halfway through, whole after.
        #expect(tracks.state(of: layer, at: 0).reveal.showsNothing)
        let half = tracks.state(of: layer, at: action.duration / 2).reveal.box
        #expect(near(half.x, 0) && near(half.width, 0.5) && near(half.height, 1))
        #expect(tracks.state(of: layer, at: action.end + 0.01).reveal == .none)
        // It moves nothing else.
        #expect(near(tracks.state(of: layer, at: action.duration / 2).position, Vec2(500, 300)))
        // Out closes it again, toward the other side.
        let out = bar(Presets.preset(.maskResizeOut), on: layer, at: 0)
        #expect(ActionTracks([out]).state(of: layer, at: out.end + 0.01).reveal.showsNothing)
        // A clip is no action, so the bar stays one piece.
        #expect(Presets.split(action, of: layer, from: LayerState(design: layer), frameRate: .fps60) == nil)
    }

    @Test func textPresetsSuitOnlyText() throws {
        let text = Layer(name: "T", content: .text(TextContent(text: "Hi there")), size: Size2(100, 40), position: .zero)
        let project = Project(layers: [text, square()])
        #expect(Presets.available(for: [text], in: project).contains { $0.isText })
        #expect(!Presets.available(for: [square()], in: project).contains { $0.isText })
        #expect(!Presets.available(for: [text, square()], in: project).contains { $0.isText })
        // A text preset goes on moving letters, and they travel one type size.
        let rise = try #require(Presets.library.first { $0.name == "Letters Rise" })
        let action = Presets.action(rise, for: text, at: 0, frameRate: .fps60)
        guard case .preset(let settings) = action.spec else { Issue.record("not a preset"); return }
        #expect(settings.unit == .letters && settings.direction == .bottom && settings.distance == 48)
        #expect(action.name == "Letters Rise" && near(action.duration, 0.8))
        #expect(!Presets.splits(settings))
        // It survives a file.
        let data = try JSONEncoder().encode(action)
        #expect(try JSONDecoder().decode(Action.self, from: data) == action)
    }

    @Test func lettersTakeTurnsAcrossTheBar() {
        let text = Layer(name: "T", content: .text(TextContent(text: "abcde")), size: Size2(100, 40), position: .zero)
        var settings = PresetRecipe.defaults(.fadeIn)
        settings.unit = .letters
        settings.delay = 0.1
        let action = Action(target: text.id, start: 1, duration: 1, easing: .preset(.none, intensity: 0), spec: .preset(settings))
        let tracks = ActionTracks([action])
        // The layer itself is left alone: the letters move instead.
        #expect(tracks.state(of: text, at: 1.1).opacity == 1)
        let animation = tracks.textAnimation(of: text.id, at: 1.1)
        // Each letter fades in over what is left after the delays: 0.6s.
        let early = animation?.states(count: 5, at: 1.3) ?? []
        #expect(early.count == 5)
        #expect(near(early[0].opacity, 0.5) && near(early[1].opacity, 1.0 / 3) && early[4].opacity == 0)
        // Before the bar every letter waits unseen; after it every one is home.
        #expect(animation?.states(count: 5, at: 0.5).allSatisfy { $0.opacity == 0 } == true)
        #expect(animation?.states(count: 5, at: 2.01).allSatisfy { $0 == TextAnimation.rest } == true)
        // Backward starts with the last.
        settings.order = .backward
        let back = ActionTracks([Action(target: text.id, start: 1, duration: 1, easing: .preset(.none, intensity: 0),
                                        spec: .preset(settings))])
        let states = back.textAnimation(of: text.id, at: 1.3)?.states(count: 5, at: 1.3) ?? []
        #expect(near(states[4].opacity, 0.5) && states[0].opacity == 0)
    }

    @Test func showAndHideAreKeptWhateverPresetsDo() {
        let layer = square()
        func visibility(_ shown: Bool, at time: Double) -> Action {
            Action(target: layer.id, start: time, duration: 0, spec: .visibility(VisibilityAction(isVisible: shown)))
        }
        func state(_ actions: [Action], at time: Double) -> LayerState { ActionTracks(actions).state(of: layer, at: time) }
        // Shown at 1s, then a Fade In at 3s: shown as designed until 3s.
        let fadeIn = bar(Presets.preset(.fadeIn), on: layer, at: 3)
        let shown = [visibility(true, at: 1), fadeIn]
        #expect(state(shown, at: 0.5).isShown && near(state(shown, at: 0.5).opacity, 0.5))
        #expect(state(shown, at: 2.99).isShown && near(state(shown, at: 2.99).opacity, 0.5))
        #expect(near(state(shown, at: 3).opacity, 0))
        #expect(near(state(shown, at: fadeIn.end).opacity, 0.5))
        // A Slide Out, then a Show: the opacity comes back, the place does not.
        let slideOut = bar(Presets.preset(.slideOut), on: layer, at: 1)
        let back = [slideOut, visibility(true, at: 3)]
        #expect(near(state(back, at: 2.5).opacity, 0))
        #expect(near(state(back, at: 3).opacity, 0.5))
        #expect(state(back, at: 3).position == state(back, at: 2.5).position)
        #expect(state(back, at: 3).position != layer.transform.position)
        // Hidden at 1s, then a Fade In at 3s: it plays, and shows the layer.
        let hidden = [visibility(false, at: 1), fadeIn]
        #expect(state(hidden, at: 0.5).isShown && near(state(hidden, at: 0.5).opacity, 0.5))
        #expect(!state(hidden, at: 2.99).isShown)
        #expect(state(hidden, at: 3).isShown)
        #expect(near(state(hidden, at: fadeIn.end).opacity, 0.5))
        // An Out preset after a Hide leaves it hidden.
        let fadeOut = bar(Presets.preset(.fadeOut), on: layer, at: 3)
        #expect(!state([visibility(false, at: 1), fadeOut], at: 3.1).isShown)
    }

    @Test func aShowBringsBackLettersFadedOut() {
        let text = Layer(name: "T", content: .text(TextContent(text: "abc")), size: Size2(100, 40), position: .zero)
        var settings = PresetRecipe.defaults(.fadeOut)
        settings.unit = .letters
        let out = Action(target: text.id, start: 1, duration: 1, easing: .preset(.none, intensity: 0), spec: .preset(settings))
        let show = Action(target: text.id, start: 3, duration: 0, spec: .visibility(VisibilityAction(isVisible: true)))
        let tracks = ActionTracks([out, show])
        #expect(tracks.textAnimation(of: text.id, at: 2.5)?.states(count: 3, at: 2.5).allSatisfy { $0.opacity == 0 } == true)
        #expect(tracks.textAnimation(of: text.id, at: 3)?.states(count: 3, at: 3).allSatisfy { $0.opacity == 1 } == true)
        // Letters waiting on an entrance after a Show wait as designed.
        var entering = PresetRecipe.defaults(.fadeIn)
        entering.unit = .letters
        let fadeIn = Action(target: text.id, start: 3, duration: 1, easing: .preset(.none, intensity: 0), spec: .preset(entering))
        let early = Action(target: text.id, start: 1, duration: 0, spec: .visibility(VisibilityAction(isVisible: true)))
        #expect(ActionTracks([early, fadeIn]).textAnimation(of: text.id, at: 2) == nil)
        #expect(ActionTracks([fadeIn]).textAnimation(of: text.id, at: 2) != nil)
    }

    @Test func aDelayTooLongForTheTextIsShortened() {
        var settings = PresetRecipe.defaults(.fadeIn)
        settings.unit = .letters
        settings.delay = 1
        let action = Action(target: UUID(), start: 0, duration: 1, easing: .preset(.none, intensity: 0), spec: .preset(settings))
        let animation = ActionTracks([action]).textAnimation(of: action.targetLayerID, at: 0)
        // Ten letters still all arrive by the bar's end.
        #expect(animation?.states(count: 10, at: 1.001).allSatisfy { near($0.opacity, 1) } == true)
        #expect(animation?.states(count: 10, at: 0.9).last.map { $0.opacity > 0 && $0.opacity < 1 } == true)
    }

    @Test func randomOrderIsTheSameEveryTime() {
        let id = UUID()
        let a = TextAnimation.ranks(12, order: .random, seed: id)
        #expect(a == TextAnimation.ranks(12, order: .random, seed: id))
        #expect(Set(a) == Set((0..<12).map(Double.init)))
        #expect(TextAnimation.ranks(5, order: .center, seed: id) == [2, 1, 0, 1, 2])
        #expect(TextAnimation.ranks(5, order: .edges, seed: id) == [0, 1, 2, 1, 0])
    }

    @Test func textSplitsIntoLettersWordsAndLines() {
        let style = TextStyle(TextContent(text: ""))
        let text = "Hi big\nworld"
        #expect(TextSpans.spans(.letters, of: text, style: style, width: nil).count == 10)
        let words = TextSpans.spans(.words, of: text, style: style, width: nil)
        #expect(words.map(\.range.location) == [0, 3, 7])
        let lines = TextSpans.spans(.lines, of: text, style: style, width: nil)
        #expect(lines.count == 2)
        // Words sit left to right on their line, and lines one under the other.
        #expect(words[0].box.maxX <= words[1].box.minX && words[2].box.minY > words[0].box.minY)
        #expect(lines[1].box.minY >= lines[0].box.maxY - 1e-6)
    }

    @Test func aTextPresetDrawsTheLettersOnlyWhileTheyMove() {
        let text = Layer(name: "T", content: .text(TextContent(text: "abc")), size: Size2(100, 40), position: .zero)
        let rise = Presets.library.first { $0.name == "Letters Rise" }!
        let action = Presets.action(rise, for: text, at: 0, frameRate: .fps60)
        let project = Project(layers: [text], actions: [action])
        func units(at t: Double) -> [ResolvedTextUnit] {
            guard case .text(let t) = evaluate(project, at: t).layer(text.id)?.content else { return [] }
            return t.units
        }
        #expect(units(at: 0.2).count == 3)
        #expect(units(at: action.end + 0.01).isEmpty)
    }
}
