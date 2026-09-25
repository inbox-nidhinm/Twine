# Redesign decisions

Answers to the audit questions for the Jitter-style redesign (26 September 2026). The redesign brief itself is `docs/redesign.md`. Where this file and the brief disagree, this file wins.

## Order

- Export (MP4 H.264, ProRes 4444, HEVC with alpha, current-frame PNG) is built right after redesign milestone 5, so real videos come as early as possible.
- Text layers are built at the start of milestone 7; image, video and audio layers at the start of milestone 8.
- Masks, snapping and alignment, and the pen tool from the original brief come after milestone 8.
- Presets are postponed. When they return they are made of actions.

## Model and evaluation

- The overlap rule applies only to actions on the same property of the same layer. Actions on different properties (a Move and an Opacity, say) always run together.
- On the same property, once a later action starts, the earlier one stops having any effect. No blending.
- An explicit initial value jumps into place at the action's start when an earlier action has changed the property; with nothing earlier, it holds from the start of the scene (entrance rule).
- In By mode, the initial value is absolute, and the action runs from it by the offset.
- A layer whose first visibility action is Show is hidden from the start of the scene.
- The anchor point is design state only; no action for it.
- Resize grows around the anchor point.
- A Trim action (start, end) is added under Style, for strokes that draw on.
- Color and Stroke act on a layer's first fill and first stroke. Stroke is not offered for a layer with no stroke.
- Shadow and Blur on a layer with none in its design animate in from nothing (transparent shadow, zero blur).
- Action times snap to frames. Actions may run past the scene's end and are cut off there.
- Actions can target groups.

## Easing

- A small set of presets for now: None, Smooth (default), Slow down, Accelerate, Overshoot, Spring, and Custom curve. Every action has an easing field, except instant actions and Hide/Show.
- A spring's motion is fitted to the action's duration; the bar never resizes itself.

## Modes and inspector

- A bare M key switches modes whenever no text field is being typed in. The Design and Animate menu items show M.
- Animation mode with nothing selected shows an empty inspector. Composition settings live in Design mode only.
- Animation mode has no drawing tools. The layers panel keeps renaming, reordering, grouping, hiding and locking.
- New actions get a visible default end value (for example Move by 100 px right, Opacity to 0%, Scale to 120%).
- The action dropdown is grouped by category and lists only actions that apply to every selected layer.

## Canvas editing in Animation mode

- With no action selected, dragging a layer moves its design position, and the animation follows. If a Move in To mode controls the layer, its To value shifts by the same amount so the layer stays under the cursor.
- With an action selected, the canvas edits that action. The layer's resting place is the start (the initial value stays empty, so it keeps inheriting), and where the user drops it is the end value. Selecting a Resize bar and dragging the size handles sets its end value; Scale and Rotate work the same way through their handles.

## Timeline

- One row per action, with a thin divider carrying the layer's name between each layer's rows.
- Stagger is a menu item that asks for a gap and spaces the selected actions in row order.
- Space plays and pauses. `,` and `.` step one frame (Shift for ten frames), `⌥,` and `⌥.` jump to the previous or next action edge. Home and End stay. `[` and `]` go.
- Arrow keys nudge the layer's design position after a click on the canvas, and the selected actions by a frame (Shift for ten) after a click on the timeline.

## Text, shape, media

- Counters use the font's evenly spaced digits where it has them.
- A video shows its first frame before its Play bar and its last frame after.
- Export includes audio.

## Housekeeping

- Old projects show a plain message and do not open. My test projects in eMotion Creations may be deleted.
