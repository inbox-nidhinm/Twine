import Foundation
import Testing
import MotionModel
@testable import MotionEvaluation

/// Values past anything Twine writes, reaching evaluation without the file
/// reader's clean-up: each used to stop the app turning a number into a
/// count (4 October 2026).
@Suite struct HugeValueTests {
    @Test func anEndlessVolumeFadeStillMakesASound() {
        let sound = MediaAsset(kind: .audio, fileName: "s.wav", originalName: "s.wav", contentHash: "h", duration: 4)
        let s = Layer(name: "S", content: .audio(AudioContent(mediaID: sound.id)), size: Size2(0, 0), position: .zero)
        let play = Action(target: s.id, start: 0, duration: 4, spec: .play(PlayAction(trimStart: 0)))
        let fade = Action(target: s.id, start: 0, duration: 1e300, spec: .volume(VolumeAction(end: 0)))
        let clips = audioClips(Project(layers: [s], actions: [play, fade], media: [sound]))
        #expect(clips.count == 1)
        #expect((clips.first?.envelope.count ?? 0) <= 700)
    }

    @Test func shapesKeepToSixtyCorners() {
        let size = Size2(100, 100)
        let polygon = ShapePaths.polygon(size, sides: .max)
        #expect(polygon.subpaths[0].points.count == FileSafety.maxCorners)
        let star = ShapePaths.star(size, points: .max, innerRadius: 0.5)
        #expect(star.subpaths[0].points.count == FileSafety.maxCorners * 2)
    }
}
