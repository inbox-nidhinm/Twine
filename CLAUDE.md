# eMotion: notes for working on it

The full brief is `docs/brief.md`. Read it before a milestone. This file is the map and the rules.

## Rules

- **No em dashes anywhere**: UI strings, comments, docs, commit messages.
- No third-party dependencies without asking.
- Every milestone ends with: `./make-app.sh` with no warnings, `./test.sh` passing, a new entry at the top of `eMotion/VersionHistory.swift`, a commit, and a push to `inbox-nidhinm/eMotion`.
- The user is a designer, not an engineer. Explain in plain terms.
- No help text in the UI. States are shown, not explained. Put explanations in `.help()` tooltips.
- Views never write literals: every colour, size and radius comes from `Theme` (in `Packages/MotionKit/Sources/Theme`). Values come from the "Flip Design System" page of Figma file `2XErpBfGuIGNU0DkL58Ute` (node 171:2055), with a light blue accent (#4C9FEF) in place of Flip's green.
- When driving the running app to verify, the user is often working in other apps. Launch with `open -g`, use accessibility presses (`click button N of ...`) rather than synthetic keys or clicks, and never type unless eMotion is frontmost. Setting a SwiftUI text field's value through accessibility does not reach its binding.

## Layers of the code

| Where | What | May import |
|---|---|---|
| `Packages/MotionKit/Sources/MotionModel` | The document: plain `Codable`, `Sendable` value types. File format and migrations in `FileFormat.swift`. | Foundation |
| `Packages/MotionKit/Sources/MotionEditing` | `EditorCommand` (every allowed change) and `ProjectStore` (applies commands, snapshot undo, continuous changes) | Foundation, MotionModel |
| `Packages/MotionKit/Sources/Theme` | Tokens, type, grain, icons (`Icons.swift` is generated) | SwiftUI |
| `eMotion/` | The app: AppKit lifecycle, `NSDocument`, SwiftUI views | everything |

Milestones 2, 4 and 5 add `MotionEvaluation`, `MotionRendering` and `MotionExport` as package targets.

## Decisions worth knowing

- **Undo is by snapshot.** `ProjectStore` records the whole `Project` before each command. Drags and sliders use `beginContinuousChange` / `updateContinuousChange` / `endContinuousChange` so they undo as one step.
- **Layers are stored back to front** (last in the array is in front). The layers panel shows them reversed.
- **Coordinates are Figma's**: origin top-left, y down, rotation clockwise in degrees. Anchor is in pixels from the layer's top-left. Scale 1 is 100%, opacity 0 to 1.
- **Keyframe easing belongs to the segment after the keyframe.** Springs: applying one moves the next keyframe to the settle point (derived); dragging it afterwards stretches the spring to fit (override). Nothing extra is stored.
- **Fills, strokes and effects are lists** so a future Figma import keeps everything. The MVP UI edits the first.
- **Paths are plain data** (`BezierPath`) and animatable, for SVG import, boolean operations and morphing later.
- **The window chrome**: an empty unified toolbar puts the traffic lights about 18pt in from the corner, inside the left panel. Do not move the buttons by hand: document windows re-lay the title bar out on every title or edited-state change, and fighting that crashed the app once.
- **Saving**: autosave in place, plus a save one second after changes stop (`ProjectDocument.scheduleSaveSoon`). `NSDocument`'s read and save overrides are `nonisolated` and step onto the main actor; the package `FileWrapper` is kept and reused so media is never rewritten.
- **Menus** are the app's own (`Components/Menus.swift`), drawn on the panel card. One `MenuHost` per window.
- **Colour picking** uses the system colour panel for now, through `ColorPanelBridge`. Milestone 3 replaces it with Flip's own picker card.

## Icons

Placeholder SVGs in `Icons/`, 24x24, stroked, `M L H V C Z` only. Regenerate after editing:

```bash
python3 Tools/svg_to_swift.py --icons Icons --out Packages/MotionKit/Sources/Theme/Icons.swift
```

The app icon is a placeholder drawn by `Tools/make-placeholder-icon.swift`.
