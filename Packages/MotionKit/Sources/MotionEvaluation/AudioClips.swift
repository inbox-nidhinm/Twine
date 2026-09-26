import Foundation
import MotionModel

/// A stretch of a file's sound placed on the timeline: `duration` seconds
/// from `sourceStart` in the file, heard from `start` in the composition.
public struct AudioClip: Sendable, Equatable {
    public var mediaID: UUID
    public var start: Double
    public var sourceStart: Double
    public var duration: Double
    public var volume: Double

    public init(mediaID: UUID, start: Double, sourceStart: Double, duration: Double, volume: Double) {
        self.mediaID = mediaID
        self.start = start
        self.sourceStart = sourceStart
        self.duration = duration
        self.volume = volume
    }
}

/// Everything the composition sounds like, as clips: one for each Play on an
/// audio layer, or on a video whose file has sound. A later Play on the same
/// layer cuts off an earlier one, as it does for the picture. Layers switched
/// off, muted or at no volume are silent, and nothing plays past the end of
/// its file or of the composition. Preview and export both play exactly this.
public func audioClips(_ project: Project) -> [AudioClip] {
    let assets = Dictionary(project.media.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let tracks = Dictionary(grouping: project.actions.filter(\.isEnabled), by: \.targetLayerID)
    var clips: [AudioClip] = []
    for layer in project.allLayers where layer.isVisible {
        let mediaID: UUID, volume: Double, muted: Bool
        switch layer.content {
        case .audio(let a): (mediaID, volume, muted) = (a.mediaID, a.volume, a.isMuted)
        case .video(let v): (mediaID, volume, muted) = (v.mediaID, v.volume, v.isMuted)
        default: continue
        }
        guard !muted, volume > 0, let asset = assets[mediaID], asset.kind == .audio || asset.hasAudio else { continue }
        let plays = (tracks[layer.id] ?? []).compactMap { a -> (Action, PlayAction)? in
            if case .play(let p) = a.spec { return (a, p) }
            return nil
        }.sorted { ActionTracks.order($0.0, $1.0) }
        for (i, (action, play)) in plays.enumerated() {
            var end = action.end
            if i + 1 < plays.count { end = min(end, plays[i + 1].0.start) }
            end = min(end, project.composition.duration)
            if let length = asset.duration { end = min(end, action.start + max(length - play.trimStart, 0)) }
            let duration = end - action.start
            guard duration > 1e-6 else { continue }
            clips.append(AudioClip(mediaID: mediaID, start: action.start, sourceStart: play.trimStart,
                                   duration: duration, volume: volume))
        }
    }
    return clips
}
