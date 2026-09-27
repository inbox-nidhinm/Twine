# Twine: redesign the animation model and UI around Jitter-style actions

The user's redesign brief of 26 September 2026, kept as written. Answers to the audit questions are in `docs/redesign-decisions.md`, which wins where the two differ.

Twine currently animates like After Effects: each layer carries its own set of keyframed properties, with stopwatch toggles, keyframe diamonds and auto keyframing. I want to replace that with the model Jitter uses. This document explains the new model, the UI changes, what to remove, and the order to do it in.

## 1. How to work with me

* Start by auditing the current codebase. Read the document model, evaluation engine, renderer, timeline, inspector and mode handling. Then give me a short report: how things work today, what can be kept, what must be rewritten, and any risks.
* Then ask me every clarifying question you have, grouped by topic. I prefer to clear doubts upfront rather than have you assume.
* After my answers, write an implementation plan (milestones, files, key types) and wait for my approval.
* Work milestone by milestone (section 11). Each milestone ends with a clean build, passing tests, a runnable app, a commit, and a short list of things for me to try.
* Keep the existing architecture: pure document model, a pure `evaluate(document, at time:)` that works at any fractional time, `ResolvedScene`, the `SceneRenderer` protocol, and deterministic export. The redesign changes the model and the UI, not those boundaries.
* Keep Flip's design language exactly as the app has it now.
* Old project files do not need to be migrated. Bump `formatVersion` and show a plain message if an old file is opened.
* If a platform limitation blocks something here, stop and tell me.
* Never use em dashes anywhere: UI strings, comments, docs, commit messages.

## 2. The new model in one paragraph

Every layer has a design state: how it looks when nothing animates it. Design mode edits only that state. Animation mode adds actions on top of it. An action is a single timed instruction to one layer, such as "move to here over 600 ms with Smooth easing". Actions are not keyframes: each has one optional initial value and one end value, nothing in between. The timeline shows actions, not layers. Every action is its own bar on its own row. Layers live only in the layer panel. Layers exist for the whole scene and are never trimmed on the timeline; they appear and disappear through actions (Opacity, Hide/Show, and so on).

## 3. Document model changes

Remove per-property keyframe tracks from layers entirely. Remove layer in and out points. Add a flat list of actions to the document.

An `Action` has:

* `id` (stable UUID) and `targetLayerID`
* `type` (see the catalog in section 5)
* `start` and `duration` in seconds. Duration may be zero, which means an instant change.
* `easing` (section 6). Ignored for instant actions and for Hide/Show.
* `initialValue`: optional. Empty means inherit (section 4).
* `endValue`: required.
* Type-specific parameters (for example the mode of a Move, or the transition style of a Change Text).
* `name` (defaults to the action type, renamable), `isEnabled` (the eye toggle in the timeline), and `rowOrder` for manual ordering.

Values are typed per action (a point for Move, a percentage for Opacity, a color or gradient for Color, and so on). Keep the value types in the model layer with no UI imports.

## 4. Evaluation semantics

This is the heart of the redesign, so implement it as pure, well-tested code.

For each layer and each animatable property:

1. Start from the design state value.
2. Take all enabled actions that affect that property on that layer, sorted by `start` (ties broken by `rowOrder`).
3. Walk them in order. For each action:
   * Its starting value is its explicit `initialValue` if set. Otherwise it inherits the property's value at the moment the action starts, meaning the design state plus everything earlier actions have done. So a second Move continues from wherever the first one ended.
   * Before it starts: it has no effect, with one exception. If it has an explicit initial value and no earlier action touches this property, the initial value holds from the start of the scene. This is what makes an entrance work: an Opacity action from 0% to 100% at 2 s keeps the layer invisible until 2 s.
   * While running: interpolate from the starting value to the end value using its easing.
   * After it ends: the end value holds until a later action changes the property.
4. Overlapping actions on the same property: the later-starting action takes over from the value at its own start. Document this rule in code.

Additional rules:

* Instant actions (zero duration) and Hide/Show jump at their start time with no easing.
* Move, Scale and Rotate support two modes: To (absolute value) and By (relative to the starting value). Default Move to By, so that moving a layer's design position carries its whole animation with it.
* Rotation values are not wrapped: rotating to 720° spins twice, and negative values are allowed.
* Evaluation must work at any fractional time (future motion blur depends on this).

Write unit tests for: inherited versus explicit initial values, entrance behavior before start, chained actions, overlaps, instant actions, To versus By modes, disabled actions, and every value type's interpolation.

## 5. Action catalog

The action dropdown only lists actions that make sense for the selected layer type. Each action shows only its own fields.

Transform (most layers)

* Move: X and Y. Mode To or By. Optional curved path: a checkbox that reveals bezier handles on the canvas for the motion path.
* Scale: X and Y in percent, linked by default. Mode To or By.
* Rotate: degrees. Mode To or By.
* Opacity: percent.
* Resize: width and height in pixels, linked or unlinked.
* Hide / Show: instant visibility change. Field: target state (hidden or visible). No duration, no easing.

Style

* Color: fill as solid, linear or radial gradient. Gradients interpolate stop colors, stop positions and gradient geometry. If stop counts differ, resample so the transition stays smooth.
* Stroke: weight and color (color may be a gradient, same rules as Color).
* Corner radius: linked or per corner.
* Shadow: color, X offset, Y offset, blur, spread if supported.

Blur

* Layer blur: radius.
* Background blur: radius and blend. Verify early that Core Animation renders this correctly in both the live canvas and offscreen export. Report back before building UI for it if it does not.

Text (text layers only)

* Letter spacing and Line height.
* Counter: From, To and Step. Detect number format from the text: prefix and suffix (such as `$` or `%`), decimals, thousands separators and zero padding. Transition per step: none, fade or slide, applied to the whole layer (per-letter effects remain out of scope).
* Change text: the new string, plus Out and In transitions (none, fade, slide, scale) applied to the whole layer, with an option for Out and In to overlap.

Shape

* Arc (ellipses): start angle, end angle, and inner radius ratio for donuts.
* Star (stars): number of points, inner radius ratio, corner radius.

If the design mode inspector does not yet expose ellipse arc properties or star properties, add them to Design mode first, since every action property needs a matching design state property.

Media

* Video and audio layers get a single Play bar in the timeline. Dragging it sets when playback starts; trimming its edges trims the media. Volume and other media settings stay in Design mode.

Glass, Morph and shader effects are out of scope for this redesign.

## 6. Easing

Replace the current easing UI with Jitter-style presets, each with an intensity slider:

* Smooth (default), Natural, Slow down, Accelerate, Elastic, Bounce, Overshoot, Impulse, Swing, None (linear), and Custom (cubic bezier with a curve editor).

Reuse the existing bezier and spring math where it fits. Allow copying an easing from one action and pasting it onto others.

## 7. Strict separation of modes

A single mode switch toggles between Design and Animation (shortcut `M`). The two modes must never share controls.

Design mode

* The canvas shows the design state, with no animations applied.
* The inspector shows design properties only: position, size, rotation, fill, stroke, corner radius, shadow, blur, text properties, media settings, and so on.
* No animation logic anywhere: no action controls, no keyframes, no timing fields.
* The timeline is hidden and the side panels use the full height.

Animation mode

* The canvas shows the scene at the playhead time, with all actions applied.
* The inspector never shows design properties like fill or stroke sections. It shows:
  * With a layer selected and no action selected: an action dropdown. Choosing an action adds it to that layer at the playhead with a default duration of 500 ms, selects it, and shows its fields.
  * With an action selected (in the timeline or right after adding it): that one action's fields only. Timing (start, duration), easing, initial value (empty means inherit; show the inherited value as placeholder text), and end value.
  * With several layers selected: the dropdown adds the same action to each.
  * With several actions of the same type selected: edit them together.
* Canvas dragging in Animation mode works like Jitter: dragging a layer moves it and updates its design position, so the change also shows in Design mode. Apply the drag as a delta in the layer's parent space so the layer stays under the cursor even while actions are affecting it. Other design edits (resizing, recoloring, text editing) are only possible in Design mode.
* When a Move action is selected, show its motion path on the canvas with start and end handles. Dragging the end handle edits the end value; dragging the start handle sets the initial value. These handles are the only way the canvas edits an action.

Remove everywhere

* Stopwatch toggles on every property, in both modes.
* Per-layer keyframe tracks, keyframe diamonds and auto keyframing.
* Layer in and out bars.
* Presets (for now).

## 8. Timeline

The timeline exists only in Animation mode.

Layout

* It spans the full width of the window, along the bottom. It is not sandwiched between the side panels.
* The left layer panel and right inspector panel shrink in height to sit above it.
* Its height is adjustable with a drag handle along its top edge, with sensible minimum and maximum heights. Remember the height app-wide.
* Rows are compact, so a scene with many actions is easy to scan.

Rows and bars

* One row per action. Each bar shows the action's icon, its name and its target layer's name.
* Rows are ordered by layer order in the layer panel, then by start time. Allow manual reordering within a layer.
* Selecting a layer in the layer panel highlights and scrolls to its bars. Selecting a bar selects its layer.
* A toggle to show only the selected layer's actions.
* Instant actions (zero duration and Hide/Show) appear as a compact marker instead of a bar.
* An eye toggle per row disables an action without deleting it.

Interactions

* Drag a bar to move it in time. Drag either edge to change duration. Hold `⌥` to resize symmetrically.
* Snapping to the playhead, to other bars' edges and to the scene end.
* Click, shift-click, `⌘`-click and marquee selection.
* `←` `→` nudge selected actions by 10 ms, with `⇧` by 100 ms.
* Delete, duplicate (`⌘D`), copy and paste. Pasting with a different layer selected applies the actions to that layer.
* Double-click a bar to rename it.
* Stagger: with several actions selected, offset their start times evenly.
* Playhead scrubbing, timeline zoom and panning (scroll and click-drag), a draggable scene duration marker, and looping playback by default.
* `,` and `.` move the playhead by 10 ms, with `⇧` by 100 ms. `⌥` `,` and `.` jump to the previous or next action edge.

## 9. Rendering and export

Rendering and export should not need structural changes, since they consume `ResolvedScene`. After the model change, confirm that the canvas and exported MP4 and ProRes 4444 files still match frame for frame, including transparency.

## 10. What stays out of scope

Figma import, SVG import, custom Metal renderer, motion blur, per-letter text effects, Morph, Glass, shaders, boolean operations, graph editor and presets. Do not build them, and do not make choices that block them.

## 11. Milestones

1. Audit and plan: codebase report, questions, approved plan.
2. Model and evaluation: `Action` type, removal of keyframe tracks and layer in and out points, evaluation semantics from section 4, full test suite.
3. Mode separation: Design and Animation modes with separate inspectors, `M` shortcut, stopwatch and keyframe UI removed everywhere.
4. Timeline rewrite: full-width, height-adjustable timeline with action rows and all interactions from section 8.
5. Animation inspector and Transform actions: action dropdown, action fields, easing presets with intensity, Move (including To and By modes and the canvas motion path), Scale, Rotate, Opacity, Resize, Hide/Show, and canvas dragging behavior.
6. Style and Blur actions: Color with gradients, Stroke, Corner radius, Shadow, Layer blur, Background blur (after the feasibility check).
7. Text and Shape actions: Letter spacing, Line height, Counter, Change text, Arc, Star, plus any missing design properties for them.
8. Media and polish: Play bars for video and audio, copy and paste of actions and easings, stagger, export parity check, performance with many actions.

## 12. Definition of done

In Design mode I build a static layout with no animation controls in sight. I press `M`, select a layer, pick one action from a dropdown, and see only that action's fields with an optional starting value and a required end value. Every action is its own bar in a full-width timeline I can resize. No stopwatches anywhere. Dragging a layer in Animation mode moves its design position, and the animation follows. Export matches the canvas exactly.
