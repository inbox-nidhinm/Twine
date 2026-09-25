# eMotion

A native macOS app for motion design, in the spirit of Jitter, in Flip's design language.

## Running it

```bash
./make-app.sh
open build/eMotion.app
```

`./make-app.sh debug` makes a debug build. `./test.sh` runs the unit tests. The project also opens in Xcode (`eMotion.xcodeproj`), where Run works as usual.

## Where things are

Projects live in `~/Documents/eMotion Creations`. A new project is written there the moment it is made and saves itself about a second after every change, so nothing is ever unsaved and closing a window never asks a question. File > Revert To browses older versions.

A project file (`Name.emotion`) is a folder that the Finder shows as one file:

```
Name.emotion/
    document.json    the project, with a formatVersion
    media/           imported images, video and audio
    thumbnail.png    for the home screen (from milestone 2)
```

## The interface

- **Home** opens at launch and whenever the last project closes: every project, newest first. Right-click a card to rename, duplicate, show in Finder or move to Trash.
- **The editor** is a full-bleed canvas with panels floating over it. The layers panel is on the left, with the project's name at its head (click it to rename). The inspector is on the right.
- **Design and Animate** switch at the head of the inspector (⌥⌘1, ⌥⌘2). Design shows the tools along the bottom. Animate hides them and brings up the timeline.
- With nothing selected, the inspector shows the composition: size, frame rate, duration, background colour and transparency. With a layer selected it shows the layer: transform, shape, fill, stroke and effects.
- ⌘1 and ⌘2 hide and show the two panels.

## Drawing and editing

| | |
|---|---|
| V | Select |
| R, O, L, Y, S | Rectangle, ellipse, line, polygon, star |
| Drag | Draw. Shift: square, circle or 45° line. Option: from the centre. A click makes a standard size. |
| Click, Shift-click, drag on empty canvas | Select, add to the selection, marquee |
| ⌘-click, double-click | Reach a layer inside a group |
| Drag a layer | Move. Shift keeps to one axis. |
| Drag a handle | Resize. Shift keeps proportions, Option resizes from the centre. |
| Just outside a corner | Rotate. Shift snaps to 15°. |
| ⌘-drag the anchor marker | Move the anchor |
| Arrows | Nudge 1px, 10px with Shift |
| ⌫ | Delete |
| ⌘D, ⌘G, ⇧⌘G, ⌘R | Duplicate, group, ungroup, rename |
| ⌘], ⌘[, ⌥⌘], ⌥⌘[ | Forward, backward, to front, to back |
| Pinch, ⌘-scroll | Zoom about the pointer |
| Two-finger scroll | Pan |
| ⌘0, ⌥⌘0, ⌘=, ⌘- | Fit, actual size, zoom in, zoom out |

## Animating

Animation is being rebuilt around Jitter-style actions (see `docs/redesign.md`). A layer's own properties are its design state; an action is one timed instruction on top of it, such as "move by 200 px over 0.5 s, smoothly", with an optional starting value and an end value. Projects already store and play actions; adding and editing them in the app arrives with redesign milestones 4 and 5.

For now, Animate (⌥⌘2) shows the timeline's transport and ruler:

| | |
|---|---|
| Space | Play or pause |
| [ and ] | Previous and next frame |
| Home, End | Go to the start or the end |
| Click or drag the ruler | Scrub |
| ⌘-scroll or pinch on the tracks | Zoom the time axis |
| Click the time readout | Switch between seconds and frames |

## Status

Original milestones 1 to 4 (foundation, evaluation and rendering, canvas and shapes, timeline and playback), then redesign milestone 2 of 8: the action model and its evaluation. See `docs/brief.md` for the original plan, `docs/redesign.md` and `docs/redesign-decisions.md` for the redesign, and Version History on the home screen for what each build changed.
