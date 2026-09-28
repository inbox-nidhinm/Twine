import Foundation
import MotionModel

/// A stretch of a file's sound placed on the timeline: `duration` seconds
/// from `sourceStart` in the file, heard from `start` in the composition, at
/// `volume`, or, when the layer has Volume actions, along `envelope`.
public struct AudioClip: Sendable, Equatable {
    public var mediaID: UUID
    public var start: Double
    public var sourceStart: Double
    public var duration: Double
    public var volume: Double
    /// The level over time, in composition seconds, straight between points:
    /// the first point's level before it, the last's after. Empty when the
    /// level never changes.
    public var envelope: [VolumePoint]

    public init(mediaID: UUID, start: Double, sourceStart: Double, duration: Double, volume: Double,
                envelope: [VolumePoint] = []) {
        self.mediaID = mediaID
        self.start = start
        self.sourceStart = sourceStart
        self.duration = duration
        self.volume = volume
        self.envelope = envelope
    }

    /// The level at a moment in the composition.
    public func volume(at time: Double) -> Double {
        guard let first = envelope.first, let last = envelope.last else { return volume }
        if time <= first.time { return first.volume }
        if time >= last.time { return last.volume }
        guard let i = envelope.firstIndex(where: { $0.time >= time }), i > 0 else { return last.volume }
        let a = envelope[i - 1], b = envelope[i]
        let t = b.time > a.time ? (time - a.time) / (b.time - a.time) : 1
        return a.volume + (b.volume - a.volume) * t
    }
}

/// A sound's level at one moment, 1 being the file's own.
public struct VolumePoint: Sendable, Equatable {
    public var time: Double
    public var volume: Double

    public init(time: Double, volume: Double) {
        self.time = time
        self.volume = volume
    }
}

/// Everything the composition sounds like, as clips: one for each Play on an
/// audio layer, or on a video whose file has sound. A later Play on the same
/// layer cuts off an earlier one, as it does for the picture. Layers switched
/// off, muted or at no volume are silent, and nothing plays past the end of
/// its file or of the composition. Volume actions give the level as it
/// changes. Preview and export both play exactly this.
public func audioClips(_ project: Project) -> [AudioClip] {
    let assets = Dictionary(project.media.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let tracks = Dictionary(grouping: project.actions.filter(\.isEnabled), by: \.targetLayerID)
    var clips: [AudioClip] = []
    for layer in project.allLayers where layer.isVisible {
        let mediaID: UUID, volume: Double, muted: Bool
        switch layer.content {
        case .audio(let a): (mediaID, volume, muted) = (a.mediaID, min(a.volume, 1), a.isMuted)
        case .video(let v): (mediaID, volume, muted) = (v.mediaID, min(v.volume, 1), v.isMuted)
        default: continue
        }
        let fades = (tracks[layer.id] ?? []).filter { $0.drives(.volume) }
        let envelope = fades.isEmpty ? [] : volumeEnvelope(of: layer, fades)
        guard !muted, volume > 0 || envelope.contains(where: { $0.volume > 0 }), let asset = assets[mediaID],
              asset.kind == .audio || asset.hasAudio else { continue }
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
                                   duration: duration, volume: volume, envelope: envelope))
        }
    }
    return clips
}

/// A layer's level over time from its Volume actions, as points close enough
/// together that straight lines between them follow each action's easing: a
/// point just before and at each start (so an instant change is a step), and
/// about thirty a second while an action runs.
public func volumeEnvelope(of layer: Layer, _ actions: [Action]) -> [VolumePoint] {
    var times: Set<Double> = [0]
    for action in actions {
        times.insert(max(action.start - 1e-4, 0))
        times.insert(action.start)
        guard !action.isInstant else { continue }
        let steps = min(max(Int((action.duration * 30).rounded(.up)), 2), 600)
        for k in 1...steps { times.insert(action.start + action.duration * Double(k) / Double(steps)) }
    }
    let tracks = ActionTracks(actions)
    return times.sorted().map { t in
        VolumePoint(time: t, volume: max(tracks.state(of: layer, at: t).volume ?? 0, 0))
    }
}
