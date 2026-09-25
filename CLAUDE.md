# eMotion: notes for working on it

The full brief is `docs/brief.md`. Read it before a milestone. This file is the map and the rules.

## Rules

- **No em dashes anywhere**: UI strings, comments, docs, commit messages.
- No third-party dependencies without asking.
- Every milestone ends with: `./make-app.sh` with no warnings, `./test.sh` passing, a new entry at the top of `eMotion/VersionHistory.swift`, a commit, and a push to `inbox-nidhinm/eMotion`.
- The user is a designer, not an engineer. Explain in plain terms.
- No help text in the UI. States are shown, not explained. Put explanations in `.help()` tooltips.
- Views never write literals: every colour, size and radius comes from `Theme` (in `Packages/MotionKit/Sources/Theme`). Values come from the "Flip Design System" page of Figma file `2XErpBfGuIGNU0DkL58Ute` (node 171:2055), with a light blue accent (#4C9FEF) in place of Flip's green.
- **Accessibility presses do not prove clicks work.** They skip hit testing. To test real clicks without touching the user's mouse, post `NSEvent` mouse and key events through `window.sendEvent` from a temporary in-app hook, and log state after each. After each step post an `.applicationDefined` event through `NSApp.postEvent`: events sent straight to a window skip the event loop, so the undo group never closes, the document never counts as edited, and nothing saves. Remove the hook before committing.
- **Never drive the copy of the app the user is using.** For scripted tests make a copy of `build/eMotion.app` with its own bundle id (`com.nidhin.emotion.selftest`) and point it at a throwaway project in the scratchpad.
- When driving the running app to verify, the user is often working in other apps. Launch with `open -g`, use accessibility presses (`click button N of ...`) rather than synthetic keys or clicks, and never type unless eMotion is frontmost. Setting a SwiftUI text field's value through accessibility does not reach its binding.

## Layers of the code

| Where | What | May import |
|---|---|---|
| `Packages/MotionKit/Sources/MotionModel` | The document: plain `Codable`, `Sendable` value types. File format and migrations in `FileFormat.swift`. | Foundation |
| `Packages/MotionKit/Sources/MotionEditing` | `EditorCommand` (every allowed change), `ProjectStore` (applies commands, snapshot undo, continuous changes), `Arrangement` (group, ungroup, restack), `LayerFactory`, Design mode property edits | Foundation, MotionModel, MotionEvaluation |
| `Packages/MotionKit/Sources/MotionEvaluation` | `evaluate(project, at:)` and `ResolvedScene`: sampling, easing, springs, OKLab blending, shape paths, `Affine` | Foundation, MotionModel |
| `Packages/MotionKit/Sources/MotionRendering` | `SceneRenderer`, `CoreAnimationRenderer`, `OffscreenRenderer` (CARenderer into Metal, used for thumbnails and, from milestone 5, export) | QuartzCore, Metal |
| `Packages/MotionKit/Sources/Theme` | Tokens, type, grain, icons (`Icons.swift` is generated) | SwiftUI |
| `eMotion/` | The app: AppKit lifecycle, `NSDocument`, SwiftUI views | everything |

Milestone 5 adds `MotionExport`. In the app, `Editor/EditorController.swift` is where every canvas gesture, menu item and inspector edit becomes a command, and `Canvas/` holds the AppKit canvas, its drag maths and its overlay.

## Decisions worth knowing

- **Undo is by snapshot.** `ProjectStore` records the whole `Project` before each command. Drags and sliders use `beginContinuousChange` / `updateContinuousChange` / `endContinuousChange` so they undo as one step.
- **Layers are stored back to front** (last in the array is in front). The layers panel shows them reversed.
- **Coordinates are Figma's**: origin top-left, y down, rotation clockwise in degrees. Anchor is in pixels from the layer's top-left. Scale 1 is 100%, opacity 0 to 1.
- **Keyframe easing belongs to the segment after the keyframe.** Springs: applying one moves the next keyframe to the settle point (derived); dragging it afterwards stretches the spring to fit (override). Nothing extra is stored.
- **Fills, strokes and effects are lists** so a future Figma import keeps everything. The MVP UI edits the first.
- **Paths are plain data** (`BezierPath`) and animatable, for SVG import, boolean operations and morphing later.
- **The window chrome**: `ChromelessWindow` (in `Components/Floating.swift`). The traffic lights are moved by hand to 20pt in, and `TrafficLights.keepPlaced` puts them back after AppKit re-lays out the title bar (it does on every title or edited-state change in a document window). Corrections run a turn later, once per burst, and give up after three misses: correcting synchronously from the frame notification recursed until the app crashed. Do not add a toolbar to lower them instead: a taller title bar makes SwiftUI stretch scroll views up under it, which misaligned clicks in the inspector.
- **Focus**: no field has the keyboard when a window opens, and `ChromelessWindow.sendEvent` ends a text edit when a click lands anywhere outside the field.
- **Saving**: autosave in place, plus a save one second after changes stop (`ProjectDocument.scheduleSaveSoon`). `NSDocument`'s read and save overrides are `nonisolated` and step onto the main actor; the package `FileWrapper` is kept and reused so media is never rewritten.
- **Menus** are the app's own (`Components/Menus.swift`), drawn on the panel card. One `MenuHost` per window.
- **Canvas**: `CanvasNSView` owns a `CoreAnimationRenderer` whose root sits in a `world` layer scaled and moved for zoom and pan; the selection is drawn by `CanvasOverlay` in view points. It renders from `show(...)`, which `updateNSView` calls, and never writes to the model there. A plain drag on a layer always moves it; moving the anchor needs Command, because the anchor sits where moves start. Resizing a group changes its scale, not its size.
- **Colour picking** is the app's own `ColorPicker` (saturation square, hue and alpha bars, eyedropper, hex) on a `PopupCard`, raised by `ColorWell` through `MenuHost.showPopup`. No third-party code: Flip vendors a library for this; eMotion does not.
- **Properties by name**: `PropertyID` (a kind plus the fill, stroke or effect id it belongs to) and `LayerProperties.get/set/update` reach any animatable property. `AnyAnimatableProperty` gives every property the same keyframe operations whatever its value type. The timeline, the stopwatches and keyframe copy and paste all go through these.
- **Edit context**: every value edit goes through `EditContext` (from `EditorController.context`). Design mode shifts an animated property's whole animation, or keys values that cannot be offset such as colours; Animate mode keys at the playhead. A static property stays static in both until its stopwatch is turned on.
- **Playback**: the canvas owns a `CADisplayLink` only while playing and calls `EditorController.advance(by:)`. The canvas and timeline representables read `editor.time` inside `updateNSView`, so a new playhead time updates them without re-running the whole window's SwiftUI. Bare playback keys live in `PlaybackKeys`, handled by the canvas and the timeline, never as menu keys, so a space typed in a field stays a space.
- **Timeline**: names column in SwiftUI, tracks (`TimelineTracksView`) and ruler (`TimelineRulerView`) in AppKit, sharing `TimelineViewport`. A bar's ends take clicks before keyframes drawn on the bar. `editor.focus` records whether the canvas or the timeline was clicked last, which decides what Delete, Copy and Paste act on.

## Icons

Placeholder SVGs in `Icons/`, 24x24, stroked, `M L H V C Z` only. Regenerate after editing:

```bash
python3 Tools/svg_to_swift.py --icons Icons --out Packages/MotionKit/Sources/Theme/Icons.swift
```

The app icon is a placeholder drawn by `Tools/make-placeholder-icon.swift`.
