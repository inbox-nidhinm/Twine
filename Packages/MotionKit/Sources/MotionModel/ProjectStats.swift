import Foundation

/// What a project holds, counted for the home screen's Info card.
public struct ProjectStats: Sendable, Equatable {
    /// Every layer, however deep in groups and frames.
    public var layers = 0
    public var shapes = 0
    /// Shapes filled with a picture count here, not as shapes.
    public var pictures = 0
    public var texts = 0
    public var videos = 0
    public var sounds = 0
    public var groups = 0
    public var frames = 0

    public var actions = 0
    public var presets = 0
    /// Actions kept but switched off in the timeline.
    public var switchedOff = 0
    public var scenes = 0
    /// Where the last action ends, in seconds; nil with no actions.
    public var lastActionEnds: Double?

    /// Files in the package's media folder.
    public var mediaFiles = 0

    public init() {}
}

extension Project {
    public var stats: ProjectStats {
        var s = ProjectStats()
        forEachLayer { layer in
            s.layers += 1
            switch layer.content {
            case .shape: if layer.picture != nil { s.pictures += 1 } else { s.shapes += 1 }
            case .text: s.texts += 1
            case .video: s.videos += 1
            case .audio: s.sounds += 1
            case .group: if layer.isFrame { s.frames += 1 } else { s.groups += 1 }
            }
        }
        for action in actions {
            s.actions += 1
            if case .preset = action.spec { s.presets += 1 }
            if !action.isEnabled { s.switchedOff += 1 }
            s.lastActionEnds = max(s.lastActionEnds ?? 0, action.start + action.duration)
        }
        s.scenes = scenes.count
        s.mediaFiles = media.count
        return s
    }
}
