import Foundation
import Testing
import MotionModel
import MotionEvaluation
@testable import MotionEditing

@Suite struct MediaEditingTests {
    private let sound = MediaAsset(kind: .audio, fileName: "s.wav", originalName: "s.wav", contentHash: "h", duration: 4)

    private func layer(muted: Bool = false) -> Layer {
        Layer(name: "S", content: .audio(AudioContent(mediaID: sound.id, volume: 0.8, isMuted: muted)), size: Size2(0, 0), position: .zero)
    }

    private func play(_ layer: Layer, at start: Double, for duration: Double, from trim: Double = 0) -> Action {
        Action(target: layer.id, start: start, duration: duration, spec: .play(PlayAction(trimStart: trim)))
    }

    @Test func aLaterPlayCutsOffAnEarlierOne() {
        let s = layer()
        let clips = audioClips(Project(composition: Composition(duration: 10), layers: [s],
                                       actions: [play(s, at: 0, for: 3), play(s, at: 2, for: 1, from: 1)], media: [sound]))
        #expect(clips == [AudioClip(mediaID: sound.id, start: 0, sourceStart: 0, duration: 2, volume: 0.8),
                          AudioClip(mediaID: sound.id, start: 2, sourceStart: 1, duration: 1, volume: 0.8)])
    }

    @Test func clipsStopAtTheEndOfTheFileAndTheScene() {
        let s = layer()
        let clips = audioClips(Project(composition: Composition(duration: 5), layers: [s],
                                       actions: [play(s, at: 2, for: 10, from: 1)], media: [sound]))
        // Three seconds of file left from 1 s in, but the scene ends at 5 s.
        #expect(clips.first?.duration == 3)
        let late = audioClips(Project(composition: Composition(duration: 5), layers: [s],
                                      actions: [play(s, at: 3, for: 10)], media: [sound]))
        #expect(late.first?.duration == 2)
    }

    @Test func mutedOrHiddenLayersAreSilent() {
        let muted = layer(muted: true)
        #expect(audioClips(Project(layers: [muted], actions: [play(muted, at: 0, for: 1)], media: [sound])).isEmpty)
        var hidden = layer()
        hidden.isVisible = false
        #expect(audioClips(Project(layers: [hidden], actions: [play(hidden, at: 0, for: 1)], media: [sound])).isEmpty)
    }

    @Test func trimmingAPlayBarsStartTrimsTheFile() {
        let s = layer()
        let original = play(s, at: 1, for: 3, from: 0.5)
        let later = ActionEditing.trimmed(original, startEdge: true, to: 2, symmetric: false, rate: .fps30, mediaLength: 4)
        #expect(later.start == 2 && later.duration == 2)
        #expect(later.spec == .play(PlayAction(trimStart: 1.5)))
        // Not before the start of the file: 0.5 s in, starting at 1 s.
        let early = ActionEditing.trimmed(original, startEdge: true, to: 0, symmetric: false, rate: .fps30, mediaLength: 4)
        #expect(early.start == 0.5 && early.spec == .play(PlayAction(trimStart: 0)))
        // Nor past its end: 3.5 s of file left from 0.5 s in.
        let long = ActionEditing.trimmed(original, startEdge: false, to: 10, symmetric: false, rate: .fps30, mediaLength: 4)
        #expect(long.end == 4.5)
    }

    @Test func importedMediaFitsTheComposition() {
        let big = MediaAsset(kind: .image, fileName: "b.png", originalName: "b.png", contentHash: "b", pixelWidth: 4000, pixelHeight: 2000)
        let layer = LayerFactory.media(big, center: Vec2(960, 540), fitting: Size2(1920, 1080), name: "B")
        #expect(layer.size == Size2(1920, 960))
        #expect(ActionFactory.kinds(for: layer).contains(.play) == false)
    }
}
