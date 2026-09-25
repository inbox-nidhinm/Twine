# eMotion: notes for working on it

The original brief is `docs/brief.md`. The project is now working through a Jitter-style redesign: `docs/redesign.md` (the brief) and `docs/redesign-decisions.md` (answers, which win where they differ). Read both before a milestone. This file is the map and the rules.

## Rules

- **No em dashes anywhere**: UI strings, comments, docs, commit messages.
- No third-party dependencies without asking.
- Every milestone ends with: `./make-app.sh` with no warnings, `./test.sh` passing, a new entry at the top of `eMotion/VersionHistory.swift`, a commit, and a push to `inbox-nidhinm/eMotion`.
- The user is a designer, not an engineer. Explain in plain terms.
- No help text in the UI. States are shown, not explained. Put explanations in `.help()` tooltips.
- Views never write literals: every colour, size and radius comes from `Theme` (in `Packages/MotionKit/Sources/Theme`). Values come from the "Flip Design System" page of Figma file `2XErpBfGuIGNU0DkL58Ute` (node 171:2055), with a light blue accent (#4C9FEF) in place of Flip's green.
- **Accessibility presses do not prove clicks work.** They skip hit testing. To test real clicks without touching the user's mouse, post `NSEvent` mouse and key events through `window.sendEvent` from a temporary in-app hook, and log state after each. After each step post an `.applicationDefined` event through `NSApp.postEvent`: events sent straight to a window skip the event loop, so the undo group never closes, the document never counts as edited, and nothing saves. Remove the hook before committing.
- **Posted events do not reliably reach SwiftUI gestures.** `onTapGesture` and `DragGesture` sometimes ignore events sent through `window.sendEvent` for a whole session, while real `Button`s always respond. Make clickable controls real buttons; for drags in SwiftUI views (the curve editor), set the value from the hook and say the drag itself was not exercised.
- **Never drive the copy of the app the user is using.** For scripted tests make a copy of `build/eMotion.app` with its own bundle id (`com.nidhin.emotion.selftest`) and point it at a throwaway project in the scratchpad.
- When driving the running app to verify, the user is often working in other apps. Launch with `open -g`, use accessibility presses (`click button N of ...`) rather than synthetic keys or clicks, and never type unless eMotion is frontmost. Setting a SwiftUI text field's value through accessibility does not reach its binding.

## Layers of the code

| Where | What | May import |
|---|---|---|
| `Packages/MotionKit/Sources/MotionModel` | The document: plain `Codable`, `Sendable` value types. File format and migrations in `FileFormat.swift`. | Foundation |
| `Packages/MotionKit/Sources/MotionEditing` | `EditorCommand` (every allowed change, including actions), `ProjectStore` (applies commands, snapshot undo, continuous changes), `Arrangement` (group, ungroup, restack, carrying actions along), `LayerFactory`, `LayerEditing` | Foundation, MotionModel, MotionEvaluation |
| `Packages/MotionKit/Sources/MotionEvaluation` | `evaluate(project, at:)`, `evaluateDesign(project)` and `ResolvedScene`: `ActionTracks` (the action rules), easing presets, springs, OKLab blending, shape paths, `Affine` | Foundation, MotionModel |
| `Packages/MotionKit/Sources/MotionRendering` | `SceneRenderer`, `CoreAnimationRenderer`, `OffscreenRenderer` (CARenderer into Metal, used for thumbnails and, from milestone 5, export) | QuartzCore, Metal |
| `Packages/MotionKit/Sources/Theme` | Tokens, type, grain, icons (`Icons.swift` is generated) | SwiftUI |
| `eMotion/` | The app: AppKit lifecycle, `NSDocument`, SwiftUI views | everything |

Export (after redesign milestone 5) adds `MotionExport`. In the app, `Editor/EditorController.swift` is where every canvas gesture, menu item and inspector edit becomes a command, and `Canvas/` holds the AppKit canvas, its drag maths and its overlay.

## Decisions worth knowing

- **Undo is by snapshot.** `ProjectStore` records the whole `Project` before each command. Drags and sliders use `beginContinuousChange` / `updateContinuousChange` / `endContinuousChange` so they undo as one step.
- **Layers are stored back to front** (last in the array is in front). The layers panel shows them reversed.
- **Coordinates are Figma's**: origin top-left, y down, rotation clockwise in degrees. Anchor is in pixels from the layer's top-left. Scale 1 is 100%, opacity 0 to 1.
- **Actions, not keyframes.** A layer's properties are plain values: its design state. `Project.actions` is a flat list; each `Action` targets one layer, has a start, a duration (0 is instant), an easing, and an `ActionSpec` carrying its own typed optional initial value and end value. Layers have no in or out points.
- **The action rules live in one place**: `walk` in `MotionEvaluation/ActionTracks.swift`, with its numbered comment. Each action drives one channel (position, scale, rotation, opacity, size, visibility). On one channel of one layer, actions go in start order (ties by `rowOrder`); an empty initial value inherits the value at the action's start; the first action's explicit initial value holds from time 0 (entrances); a later action takes over from the value at its own start. Channels never interfere. By mode adds (Scale By multiplies); To is absolute. Resize grows around the anchor. A first Show hides the layer until it.
- **Easing** is a named preset with an intensity (none, smooth, slow down, accelerate, overshoot, spring) or a custom bezier. Presets are worked out at evaluation, so improving one improves every action. A spring's motion is fitted to the action's duration.
- **Actions follow their layers**: `EditorCommand.apply` drops actions whose layer is gone, whatever command removed it. Grouping and ungrouping remap To values and initial values into the new parent space (`Action.remapped`); duplicating and pasting copy actions through `duplicated(recordingIDs:)` and `actionCopies(for:)`.
- **File format 2** is the first with actions. Anything older is refused with a plain message (`ProjectFileError.olderVersion`, whose `failureReason` is what the open alert shows).
- **Fills, strokes and effects are lists** so a future Figma import keeps everything. The MVP UI edits the first.
- **Paths are plain data** (`BezierPath`), for SVG import, boolean operations and morphing later.
- **The window chrome**: `ChromelessWindow` (in `Components/Floating.swift`). The traffic lights are moved by hand to 20pt in, and `TrafficLights.keepPlaced` puts them back after AppKit re-lays out the title bar (it does on every title or edited-state change in a document window). Corrections run a turn later, once per burst, and give up after three misses: correcting synchronously from the frame notification recursed until the app crashed. Do not add a toolbar to lower them instead: a taller title bar makes SwiftUI stretch scroll views up under it, which misaligned clicks in the inspector.
- **Focus**: no field has the keyboard when a window opens, and `ChromelessWindow.sendEvent` ends a text edit when a click lands anywhere outside the field.
- **Saving**: autosave in place, plus a save one second after changes stop (`ProjectDocument.scheduleSaveSoon`). `NSDocument`'s read and save overrides are `nonisolated` and step onto the main actor; the package `FileWrapper` is kept and reused so media is never rewritten.
- **Menus** are the app's own (`Components/Menus.swift`), drawn on the panel card. One `MenuHost` per window.
- **Canvas**: `CanvasNSView` owns a `CoreAnimationRenderer` whose root sits in a `world` layer scaled and moved for zoom and pan; the selection is drawn by `CanvasOverlay` in view points. It renders from `show(...)`, which `updateNSView` calls, and never writes to the model there. A plain drag on a layer always moves it; moving the anchor needs Command, because the anchor sits where moves start. Resizing a group changes its scale, not its size.
- **Colour picking** is the app's own `ColorPicker` (saturation square, hue and alpha bars, eyedropper, hex) on a `PopupCard`, raised by `ColorWell` through `MenuHost.showPopup`. No third-party code: Flip vendors a library for this; eMotion does not.
- **Playback**: the canvas owns a `CADisplayLink` only while playing and calls `EditorController.advance(by:)`. The canvas and timeline representables read `editor.time` inside `updateNSView`, so a new playhead time updates them without re-running the whole window's SwiftUI. Bare playback keys live in `PlaybackKeys`, handled by the canvas and the timeline, never as menu keys, so a space typed in a field stays a space.
- **Timeline**: for now only the transport, the ruler (`TimelineRulerView`) and an empty tracks view (`TimelineTracksView`) sharing `TimelineViewport`; redesign milestone 4 rewrites it around action rows. `editor.focus` records whether the canvas or the timeline was clicked last.

## Icons

Placeholder SVGs in `Icons/`, 24x24, stroked, `M L H V C Z` only. Regenerate after editing:

```bash
python3 Tools/svg_to_swift.py --icons Icons --out Packages/MotionKit/Sources/Theme/Icons.swift
```

The app icon is a placeholder drawn by `Tools/make-placeholder-icon.swift`.
