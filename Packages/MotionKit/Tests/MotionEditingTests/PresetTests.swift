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

private func applied(_ preset: Preset, at time: Double = 1) -> (Layer, ActionTracks) {
    let layer = square()
    let state = ActionTracks([]).state(of: layer, at: time)
    let actions = Presets.actions(preset, for: layer, at: time, state: state, frameRate: .fps60)
    return (layer, ActionTracks(actions))
}

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-6 }
private func near(_ a: Vec2, _ b: Vec2) -> Bool { near(a.x, b.x) && near(a.y, b.y) }

@Suite struct PresetTests {
    @Test func theLibraryIsWellFormed() throws {
        #expect(Set(Presets.library.map(\.id)).count == Presets.library.count)
        for preset in Presets.library {
            #expect(!preset.steps.isEmpty, "\(preset.name)")
            #expect(preset.duration > 0 && preset.duration <= 1, "\(preset.name)")
        }
        // Presets are plain data.
        let data = try JSONEncoder().encode(Presets.library)
        #expect(try JSONDecoder().decode([Preset].self, from: data) == Presets.library)
    }

    @Test func entrancesLandOnTheLayerAsItWas() {
        for preset in Presets.library where preset.category == .entrance {
            let (layer, tracks) = applied(preset)
            let end = tracks.state(of: layer, at: 1 + preset.duration + 0.01)
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
            let (layer, tracks) = applied(preset)
            let end = tracks.state(of: layer, at: 1 + preset.duration + 0.01)
            #expect(end.opacity < 1e-6 || end.scale.x < 1e-6, "\(preset.name)")
            // Untouched until it starts.
            #expect(near(tracks.state(of: layer, at: 0.5).opacity, 0.5), "\(preset.name)")
        }
    }

    @Test func emphasisReturnsTheLayerToWhereItWas() {
        for preset in Presets.library where preset.category == .emphasis {
            let (layer, tracks) = applied(preset)
            let end = tracks.state(of: layer, at: 1 + preset.duration + 0.01)
            #expect(near(end.position, Vec2(500, 300)) && near(end.scale, Vec2(1, 1)) && near(end.rotation, 10),
                    "\(preset.name)")
            // And moves it on the way.
            let middle = tracks.state(of: layer, at: 1 + preset.duration * 0.3)
            #expect(!(near(middle.position, Vec2(500, 300)) && near(middle.scale, Vec2(1, 1)) && near(middle.rotation, 10)),
                    "\(preset.name)")
        }
    }

    @Test func aFadedOutLayerFadesBackToItsDesign() {
        var layer = square()
        let out = Action(target: layer.id, start: 0, duration: 0.5, spec: .opacity(OpacityAction(end: 0)))
        let state = ActionTracks([out]).state(of: layer, at: 1)
        let fade = Presets.library.first { $0.id == "fade-in" }!
        let actions = Presets.actions(fade, for: layer, at: 1, state: state, frameRate: .fps60)
        if case .opacity(let o) = actions[0].spec { #expect(o.end == 0.5) } else { Issue.record("not an opacity") }
        layer.opacity = 0
        let again = Presets.actions(fade, for: layer, at: 1, state: state, frameRate: .fps60)
        if case .opacity(let o) = again[0].spec { #expect(o.end == 1) } else { Issue.record("not an opacity") }
    }

    @Test func onlyPresetsALayerCanTakeAreOffered() {
        let sound = Layer(name: "Sound", content: .audio(AudioContent(mediaID: UUID())), size: Size2(0, 0), position: .zero)
        let project = Project(layers: [sound, square()])
        let soundPresets = Presets.library.filter { $0.category == .sound }
        #expect(soundPresets.count == 2)
        // A sound takes only the sound presets, a shape everything else.
        #expect(Presets.available(for: [sound], in: project) == soundPresets)
        #expect(Presets.available(for: [square()], in: project).count == Presets.library.count - soundPresets.count)
        #expect(Presets.available(for: [square(), sound], in: project).isEmpty)
    }

    @Test func soundPresetsSuitOnlyVideoWithSound() {
        let silent = MediaAsset(kind: .video, fileName: "s.mov", originalName: "s.mov", contentHash: "s", duration: 2)
        let loud = MediaAsset(kind: .video, fileName: "l.mov", originalName: "l.mov", contentHash: "l", duration: 2, hasAudio: true)
        let a = Layer(name: "A", content: .video(VideoContent(mediaID: silent.id)), size: Size2(10, 10), position: .zero)
        let b = Layer(name: "B", content: .video(VideoContent(mediaID: loud.id)), size: Size2(10, 10), position: .zero)
        var project = Project(layers: [a, b])
        project.media = [silent, loud]
        #expect(!Presets.available(for: [a], in: project).contains { $0.category == .sound })
        #expect(Presets.available(for: [b], in: project).contains { $0.id == "fade-sound-in" })
        #expect(!ActionFactory.kinds(for: a, in: project).contains(.volume))
        #expect(ActionFactory.kinds(for: b, in: project).contains(.volume))
    }

    @Test func fadingSoundInComesUpToItsOwnLevelAtMost100Percent() {
        let sound = Layer(name: "Sound", content: .audio(AudioContent(mediaID: UUID(), volume: 1.5)), size: Size2(0, 0), position: .zero)
        let fade = Presets.library.first { $0.id == "fade-sound-in" }!
        let made = Presets.actions(fade, for: sound, at: 0, state: LayerState(design: sound), frameRate: .fps60)
        #expect(made.first?.spec == .volume(VolumeAction(initial: 0, end: 1)))
        #expect(made.first?.duration == 1)
    }

    @Test func stepsLandOnFrames() {
        let shake = Presets.library.first { $0.id == "shake" }!
        let (_, tracks) = applied(shake, at: 1.004)
        _ = tracks
        let layer = square()
        let actions = Presets.actions(shake, for: layer, at: 1.004, state: ActionTracks([]).state(of: layer, at: 1),
                                      frameRate: .fps30)
        for a in actions {
            #expect(abs((a.start * 30).rounded() - a.start * 30) < 1e-6)
            #expect(abs((a.duration * 30).rounded() - a.duration * 30) < 1e-6 && a.duration > 0)
        }
    }
}
