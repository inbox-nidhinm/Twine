# Twine brief

The kickoff brief as written by Nidhin, followed by the decisions made while answering the kickoff questions (25 September 2026). Where the two differ, the decisions win.

## Decisions from kickoff

- Project at `Documents/Claude Code/Twine`, its own repository, pushed to private GitHub `inbox-nidhinm/Twine` after each milestone.
- Xcode project plus `make-app.sh` for a double-clickable build. Bundle `com.nidhin.twine`, files `Name.twine`. Signed to run on this Mac only; no sandbox.
- In-app Version History, as in Flip.
- Design tokens from the "Flip Design System" page of Figma file `2XErpBfGuIGNU0DkL58Ute` (node 171:2055), with a light blue accent instead of Flip's green. Placeholder icons for now; do not reuse Flip's icons. Dark only. Placeholder app icon. Trupeer Slab Light for display type.
- A home screen at launch.
- Layout like Jitter: a layers panel for groupings, and a separate keyframe timeline. The right panel switches between Design mode (tools on the bottom bar, no timeline) and Animate mode (timeline, no tools). In Design mode an edit to a keyframed property shifts the whole animation; in Animate mode it keys at the playhead.
- Inspector: one scrolling panel of collapsible sections. With nothing selected it shows composition settings and export.
- New projects: 1920x1080, 60 fps, 5 seconds, white. Also 23.976, 29.97, 59.94 and custom rates.
- Coordinates as Figma: origin top-left, y down, rotation clockwise in degrees. Anchor in pixels from the layer's top-left, default centre. sRGB, exports tagged Rec. 709.
- Position is one keyframed property moving in straight lines. Easing belongs to the segment after a keyframe. Springs: applying one moves the next keyframe to where the spring settles; dragging it afterwards stretches the spring to fit. Colours blend in a perceptual space (OKLab).
- Solo affects canvas and export. Hidden layers never export.
- Presets: in presets start at the layer's in point, out presets end at its out point, 0.5s each. Fade, slide from each side, scale pop and blur (in and out), rotate in, drop in with bounce, pulse, shake.
- Inside and outside strokes are faked on closed shapes with a doubled stroke clipped to the shape; open paths draw centred.
- Fonts referenced by name, with a fallback if missing. Any shape layer can be a mask, chosen from a menu, with an invert toggle. No After Effects style parenting.
- Media always copied into the project; importing the same file twice reuses one copy. Video plays at its own speed. Audio is silent while scrubbing.
- Space plays and pauses. Two-finger scroll pans, pinch zooms. Tool letters as Figma (V, R, O, L, P, T), Flip's shortcuts where they overlap. Content outside the composition is hidden.
- Export adds HEVC with transparency, and the current frame as a PNG. The export UI is a collapsible section that asks where to save.

## 1. How to work with me

- Before writing any code, ask me every clarifying question you have. I prefer to clear all doubts and preferences upfront rather than have you assume. Group questions by topic.
- After questions are answered, write a short implementation plan (milestones, files, key types) and wait for my approval.
- Work milestone by milestone (see section 9). At the end of each milestone: the project builds with no warnings, the app runs, tests pass, and you give me a short summary of what to try manually.
- Commit at the end of each milestone with a clear message.
- Do not add third-party dependencies without asking first. Prefer Apple frameworks.
- If something in this document conflicts with a platform limitation, stop and tell me instead of silently working around it.
- Never use em dashes anywhere: UI strings, comments, docs, commit messages.

## 2. Platform and stack

- Target: macOS 26 Tahoe minimum. Apple Silicon.
- Language: Swift 6 with strict concurrency.
- UI: SwiftUI for panels, inspector and app structure. AppKit (`NSView` subclasses bridged into SwiftUI) wherever SwiftUI is not precise or fast enough, which will likely include the canvas and the timeline.
- Rendering: Core Animation layer tree (GPU composited, Metal under the hood). No custom Metal shaders in the MVP.
- Media: AVFoundation for video decode, audio playback and export.
- Documents: document-based app with a package file format (a folder bundle containing `document.json` plus a `media/` folder for imported assets). Continuous autosave. Version the file format from day one (`formatVersion` field).

## 3. Architecture (the most important section)

The MVP uses Core Animation, but I will later replace or supplement it with a custom Metal renderer, add motion blur, and add a Figma import plugin. The architecture must make those future additions possible without rewrites. Keep these layers strictly separate:

1. Document model. Pure Swift value types, `Codable`, `Sendable`, no UI or rendering imports. Project settings, layer tree, properties, keyframes, media references. Every layer has a stable `UUID` that never changes (future Figma import needs to map IDs).
2. Animation evaluation. A pure function: `evaluate(document, at time: Double) -> ResolvedScene`. `ResolvedScene` is a flat, render-ready description of every visible layer with all property values resolved for that exact moment. It must work at any fractional time, not just frame boundaries (future motion blur renders several subframes per frame and averages them).
3. Renderer. A `SceneRenderer` protocol that takes a `ResolvedScene` and draws it. The MVP implementation is `CoreAnimationRenderer`. The same renderer must drive both the live canvas and offscreen export, so what I see is what I export. Groups render as their own container layer so group opacity, group transforms and future group motion blur work correctly.
4. Export pipeline. Steps through time deterministically, calls `evaluate`, renders offscreen (for example `CARenderer` into a Metal texture, then into a `CVPixelBuffer`), and writes with `AVAssetWriter`. Must not depend on real-time playback.
5. UI. Canvas, timeline, inspector, toolbar. The UI edits the document model only through a small set of commands so every change is undoable.

Core Animation's own implicit and explicit animations must not drive playback. Disable implicit actions and set layer properties directly from `ResolvedScene` every frame. This keeps scrubbing exact and the renderer swappable.

Write unit tests for: keyframe interpolation, easing curves, spring easing, evaluation at arbitrary times, document encode and decode round trips, and export frame timing.

## 4. Project model

- One composition per project. No infinite canvas, no multiple scenes.
- Composition settings: width and height in pixels, frame rate (24, 25, 30, 50, 60, custom), duration, background color or transparent.
- Layer tree with groups (nesting allowed), reorder, rename, hide, lock, solo.
- Each layer has an in point and out point on the timeline (visible range).

### Layer types in the MVP

- Shapes: rectangle (with per-corner radius), ellipse, line, polygon or star, and bezier paths created with a pen tool (click to add points, drag to create curve handles, edit points after creation). Fill (solid, linear gradient, radial gradient), stroke (color, width, alignment where Core Animation allows, dash pattern, caps, joins).
- Text: whole-layer text only. Font family, weight, size, color, alignment, letter spacing, line height, fixed width or auto width. Animated as a whole layer. No per-letter effects in the MVP.
- Images: PNG, JPEG, HEIC, WebP if supported by ImageIO. Copied into the document package.
- Video: MOV and MP4, copied into the package. Frame-accurate display while scrubbing (not a free-running `AVPlayerLayer`). Trim start, playback offset on the timeline.
- Audio: audio-only files, plus audio tracks from video layers. Volume per layer (animatable), mute. Plays in sync during preview and is mixed into exports. Show a waveform on the timeline.
- Groups: transform, opacity and visibility apply to all children. Clip to bounds toggle.
- Masks: a layer can use another shape layer as its mask (alpha mask). Keep this simple.

## 5. Animation system

- Every animatable property can have keyframes. Properties with no keyframes hold a static value.
- Animatable properties: position, anchor point, scale (x and y, linked or unlinked), rotation, opacity, size (width and height for shapes and text boxes), corner radius, fill color, gradient stops, stroke color, stroke width, stroke trim start and end, shadow (color, offset, blur, opacity), layer blur (via Core Image filter on the layer), volume.
- Easing per keyframe segment: linear, hold, preset curves (ease in, ease out, ease in out, and a handful of stronger variants), custom cubic bezier with a small curve preview, and spring (stiffness, damping, mass, with the segment duration derived or overridden).
- Auto keyframing: if a property already has keyframes, changing it on the canvas or inspector creates or updates a keyframe at the playhead. If it has none, the change sets the static value. A stopwatch style toggle next to each property turns keyframing on and off.
- Presets: one-click animations that generate normal editable keyframes (fade in, fade out, slide in from each side, scale pop, rotate in, blur in, and a few others). Presets are just keyframe templates, not a separate system. Store them in a way that makes adding new presets data-only.

## 6. Editor features

### Canvas

- Full-bleed canvas with the composition frame centered. Zoom (pinch, shortcuts, fit, 100%), pan (space drag, two-finger scroll).
- Select, multi-select, marquee select, move, resize with handles, rotate, edit anchor point.
- Smart snapping and guides: to composition edges and center, to other layers' edges and centers, equal spacing.
- Alignment and distribution actions.
- Pen tool and point editing for bezier paths.
- Custom cursor per tool.

### Timeline

- One row per layer, expandable to show each animated property.
- Layer bars with draggable in and out points, and drag to move the whole bar.
- Keyframes shown as markers. Click, shift-click, marquee select. Drag to retime, with snapping to the playhead, other keyframes and layer bar edges. Copy, paste, delete, duplicate.
- Setting easing on a selection of keyframe segments at once.
- Scrubbing with a playhead, zoom and scroll on the time axis, frame ruler with time or frame display.
- Playback: play, pause, loop, step one frame forward and back, jump to start and end.
- Audio waveforms on audio and video rows.

### Inspector

- Direct numeric values in pixels, degrees, percent and seconds. No relative or abstract units.
- Controls never cap my range. Sliders may have a comfortable default range but typing any value must work.
- Keyframe toggle per property.

### General

- Full undo and redo for every change, including timeline edits.
- Continuous autosave.
- Keyboard shortcuts for all common actions, with a shortcuts card shown with ⌘/ that lists only app-specific shortcuts.

## 7. Design language: match Flip

The UI must match the design language of Flip, my existing macOS frame-by-frame animation app. Key principles:

- No help text anywhere in the UI. States are shown, not explained: empty lists look empty, disabled controls look disabled. Icons with tooltips instead of labels wherever possible.
- Canvas first. Panels float over the canvas and give their space back when hidden. A bottom strip bar holds playback and view controls (in this app, the timeline lives in or expands from this bottom area).
- Components: chunky slider tracks with white pill fills, unit fields for numeric values, segment rows, pill toggles, bar buttons with chevron menus for paired or related tools, collapsible sections (for example the export section).
- Toolbar: compact, with related tools grouped behind chevron menus rather than many separate buttons.
- Fewer modes, more direct manipulation.

Design tokens (colors, radii, shadows, type) and icon SVGs live in my Figma design system file "JUI" (file key `2XErpBfGuIGNU0DkL58Ute`). Put all tokens in one place (a `Theme` module) so nothing is hardcoded in views.

Where macOS 26 default styling (for example Liquid Glass materials) conflicts with Flip's look, follow Flip's look. Ask me if unsure.

## 8. Export

- Formats: MP4 (H.264 and HEVC), MOV (HEVC, ProRes 422, ProRes 4444 with transparency).
- Transparency must be preserved end to end in ProRes 4444 when the background is set to transparent.
- Options: resolution scale (0.5x, 1x, 2x, custom), frame range (whole composition or a selected range), include audio on or off, quality or bitrate for H.264 and HEVC.
- Rendering is deterministic and offline: exported frames must match the canvas exactly at the same times.
- Progress indicator with cancel. Export runs off the main thread and does not freeze the UI.

## 9. Milestones

Complete these in order. Each milestone ends with a working, runnable app.

1. Foundation: Xcode project, document-based app, package file format with versioning, document model types, autosave, undo infrastructure, `Theme` module with placeholder or real tokens.
2. Evaluation and rendering: keyframes, interpolation, easing (bezier and spring), `evaluate(at:)`, `ResolvedScene`, `SceneRenderer` protocol, `CoreAnimationRenderer`, tests.
3. Canvas and basic shapes: rectangle, ellipse, line, polygon, fills and strokes, selection, transform handles, zoom and pan, inspector with static properties.
4. Timeline and playback: layer rows, layer bars, keyframe markers, auto keyframing, easing editing, scrubbing, playback, shortcuts.
5. Export: MP4 and MOV including ProRes 4444 with alpha, progress, cancel, render parity with the canvas.
6. Text and images: text layers, image import, groups, masks, snapping and guides, alignment.
7. Video and audio: frame-accurate video layers, audio playback in sync, waveforms, audio in exports.
8. Presets, pen tool and polish: preset library, pen tool and point editing, shortcuts card, custom cursors, performance pass (smooth scrubbing with 100+ layers).

## 10. Out of scope for the MVP (design for these, do not build them)

These are planned. Do not implement them now, but do not make choices that block them. Where relevant, leave a clear extension point and note it in code comments.

- Figma import plugin: one-way import of a single frame into editable native layers, with complex nodes brought in as SVG. Needs stable layer IDs and a layer model that can represent Figma's fills, strokes and effects.
- SVG import and parsing into editable shape layers.
- Custom Metal renderer as an alternative `SceneRenderer`.
- Motion blur for layers and groups via subframe accumulation (render several subframes per frame with shutter angle and sample count, then average). Requires `evaluate` at fractional times and groups rendering as their own layer, both of which the MVP already provides.
- Per-letter and per-line text effects.
- Boolean operations on paths.
- Shape morphing between paths.
- Graph editor for value and speed curves.

Explicitly never planned: real-time collaboration, AI generation, Lottie export, shader effects, synced re-import from Figma, multiple scenes or infinite canvas.

## 11. Definition of done for the MVP

I can create a project, add shapes, text, images, video and audio, animate them with keyframes and easing or presets, scrub and play back smoothly with synced audio, and export an MP4 or a transparent ProRes 4444 MOV that matches the canvas exactly. The app looks and feels like Flip, every action is undoable, and nothing is ever lost because of autosave.
