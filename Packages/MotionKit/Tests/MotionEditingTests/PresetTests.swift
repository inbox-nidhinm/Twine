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
        #expect(Set(Presets.library.map(\.kind)) == Set(PresetKind.allCases))
        for preset in Presets.library {
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
        for preset in Presets.library where preset.category == .entrance {
            let layer = square()
            let action = bar(preset, on: layer)
            let tracks = ActionTracks([action])
            let end = tracks.state(of: layer, at: action.end + 0.01)
            #expect(near(end.position, Vec2(500, 300)), "\(preset.name)")
            #expect(near(end.opacity, 0.5), "\(preset.name)")
            #expect(near(end.scale, Vec2(1, 1)), "\(preset.name)")
            #expect(near(end.rotation, 10), "\(preset.name)")
            #expect(near(end.layerBlur, 0), "\(preset.name)")
            // Before it, the layer waits unseen.
            #expect(tracks.state(of: layer, at: 0.5).opacity == 0, "\(preset.name)")
        }
    }

    @Test func exitsLeaveNothingToSee() {
        for preset in Presets.library where preset.category == .exit {
            let layer = square()
            let action = bar(preset, on: layer)
            let tracks = ActionTracks([action])
            let end = tracks.state(of: layer, at: action.end + 0.01)
            #expect(end.opacity < 1e-6 || end.scale.x < 1e-6, "\(preset.name)")
            // Untouched until it starts.
            #expect(near(tracks.state(of: layer, at: 0.5).opacity, 0.5), "\(preset.name)")
        }
    }

    @Test func emphasisReturnsTheLayerToWhereItWas() {
        for preset in Presets.library where preset.category == .emphasis {
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
        for preset in Presets.library where preset.category != .sound {
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
        let soundPresets = Presets.library.filter { $0.category == .sound }
        #expect(soundPresets.count == 2)
        // A sound takes only the sound presets, a shape everything else.
        #expect(Presets.available(for: [sound], in: project) == soundPresets)
        #expect(Presets.available(for: [square()], in: project).count == Presets.library.count - soundPresets.count)
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
        #expect(!Presets.available(for: [a], in: project).contains { $0.category == .sound })
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

    @Test func eachPresetShowsItsOwnSettings() {
        #expect(Presets.controls(for: .slideIn) == [.direction, .distance, .fades])
        #expect(Presets.controls(for: .fadeIn).isEmpty)
        // A shake keeps its jolts' own easing, so it offers none.
        #expect(!PresetRecipe.usesEasing(.shake))
        #expect(PresetRecipe.usesEasing(.slideIn))
    }
}
