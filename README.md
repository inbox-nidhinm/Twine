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
| P | Pen (see Paths below) |
| Drag | Draw. Shift: square, circle or 45° line. Option: from the centre. A click makes a standard size. |
| Click, Shift-click, drag on empty canvas | Select, add to the selection, marquee |
| ⌘-click, double-click | Reach a layer inside a group |
| Drag a layer | Move. Shift keeps to one axis. Option (Design) drags away a copy. |
| Dragging, resizing or drawing | Snaps to the composition's edges and centre, other layers' edges and centres, and even spacing, with red guides. Hold ⌘ to place freely; View > Smart Guides turns snapping off. |
| ⌥A, ⌥H, ⌥D | Align left, horizontal centres, right |
| ⌥W, ⌥V, ⌥S | Align top, vertical centres, bottom |
| ⌃⌥H, ⌃⌥V | Distribute horizontally, vertically (three or more layers) |
| Drag a handle | Resize. Shift keeps proportions, Option resizes from the centre. |
| Just outside a corner | Rotate. Shift snaps to 15°. |
| ⌘-drag the anchor marker | Move the anchor |
| Arrows | Nudge 1px, 10px with Shift |
| ⌫ | Delete |
| ⌘D, ⌘G, ⇧⌘G, ⌘R | Duplicate, group, ungroup, rename |
| ⌘], ⌘[, ⌥⌘], ⌥⌘[ | Forward, backward, to front, to back |
| Pinch, ⌘-scroll | Zoom about the pointer |
| Two-finger scroll, Space-drag, middle-button drag | Pan |
| ⌘0, ⌥⌘0, ⌘=, ⌘- | Fit, actual size, zoom in, zoom out |
| ⌘/ | Every shortcut, on one card |

One layer aligns with the composition; several align with each other. The same commands are in the Arrange menu and in a row of buttons at the top of the inspector.

## Paths

Pick the Pen (P) and click to place points; click and drag to pull out curve handles as you place one (Option pulls only the handle leading on, Shift keeps to 45°). Click the first point to close the shape, which then takes the usual grey fill; Escape or Return leaves it open, drawn as a line. With the pen, clicking the end of an open path carries it on, and clicking a shape's outline adds a point there. A path finished with only one point is taken away, since it draws nothing.

Double-click a shape, or press Return with it selected, to edit its points, as in Figma: click, Shift-click or drag a box to pick points; drag points, handles or a segment (snapping to guides and to the other points); ⌘-click a point to switch it between sharp and smooth, ⌘-drag to pull out new handles, Option-drag a handle to move it alone; arrows nudge; ⌫ deletes points and joins the gap. Escape, Return or a click away finishes. Rectangles, ellipses, lines, polygons and stars become paths at the first change. A path fills its layer's box, so resizing stretches it.

In Animate, the Path action (under Shape) morphs a path to a new shape. Select its bar and the end shape's points show on the canvas; drag them, their handles or segments to set it, and the playhead goes to the end to show it. The end keeps the design's points, so they can be moved but not added or taken away; the inspector's × puts the end back to the start.

## Text

Pick the Text tool (T) and click the canvas: a text layer appears with its word selected, ready to type over, right on the canvas. Double-click a text layer to type where you clicked, or press Return with it selected to edit all of it; Escape or a click away finishes. All the usual Mac typing keys, Copy and Paste, held-key accents and input methods work, and Undo steps back through your typing while you type. The words can also be typed in the inspector's text box. The Text section sets the font (from a searchable list of the fonts on this Mac), weight, size, colour, alignment, letter spacing, line height and auto or fixed width. A font that is not installed shows crossed out and the text draws in SF Pro. The box always fits the words; dragging its side makes it fixed width.

## Masks

Select a layer and press + under Mask in the inspector to pick another layer as its mask: the layer then shows only where the mask draws, and the mask itself stops drawing. Invert shows it everywhere the mask does not draw. Any shape, text, picture or video can be a mask, and a group can be masked by a layer inside it. The mask's opacity, blur and actions all carry through, so a moving mask reveals as it goes. A mask shows its own icon in the layers panel; select it there to move it on the canvas. Switching a mask off shows the layer whole.

## Pictures, video and sound

File > Import… (⌘I), or drop files on the canvas. Pictures and video come in at their own size (shrunk to fit the composition if larger); sound has no picture and only shows in the layers panel and the timeline. The file is copied into the project package.

Video and sound each get a Play bar on the timeline: drag it to set when it plays; drag its ends to trim the clip. Before its bar a video shows the frame it will start on, after it the frame it stopped on. Sound plays with the timeline and shows its waveform in the bar. Volume (up to 100%, the file's own level) and mute are under Sound in Design (a video only has a Sound section when its file has a sound track). In Animate, the Volume action (under Media) fades the sound to a level from 0% to 100% along its easing, heard in playback and in exports, and the waveform tapers to show it; Add Preset has Fade Sound In and Fade Sound Out. Both are only offered for sounds and for video with sound. Exports include the sound unless Export > Audio is off.

## Animating

Animation is being rebuilt around Jitter-style actions (see `docs/redesign.md`). A layer's own properties are its design state; an action is one timed instruction on top of it, such as "move by 200 px over 0.5 s, smoothly", with an optional starting value and an end value.

Press M to switch between the two modes. They never share a control:

- **Design** shows the layout as designed, with no animation, and its inspector edits the design.
- **Animate** shows the moment at the playhead. Select a layer and use Add Action in the inspector to add an action at the playhead, half a second long; the playhead then runs to its end, so you see it play and the next action follows on. Select an action (on the timeline, or straight after adding it) and the inspector shows only its fields: start and length, easing (None, Smooth, Slow down, Accelerate, Overshoot, Spring, each with an intensity, or a Custom curve), To or By where it applies, the starting value (leave it empty to start from wherever the layer is; the greyed number is what it would start from), and the end value. Several actions of one kind edit together; mixed kinds share timing and easing.

Add Action lists what the selected layers can take, grouped:

- **Transform**: Move, Scale, Rotate, Opacity, Resize, Hide/Show.
- **Style**: Colour (the first fill: a colour or a gradient), Stroke (width and colour), Trim (draws a stroke on), Corner Radius (rectangles), Shadow.
- **Blur**: Layer Blur, Background Blur (frosted glass, for shapes; it shows through a see-through fill).
- **Text**: Letter Spacing, Line Height, Counter (counts in the text's own style, like `$1,200.50`), Change Text (with transitions out and in).
- **Shape**: Arc (ellipses: slices and rings), Star (points, inner radius, corners).
- **Media**: Play (video and sound).

Add Preset, under Add Action, applies a ready-made animation at the playhead: entrances, exits and emphasis such as Slide In from Left, Scale Pop, Blur Out, Pulse or Shake. A preset only adds ordinary actions, so each part can be edited afterwards.

Copy Easing and Paste Easing (⌥⌘C, ⌥⌘V) copy one action's easing onto the selected actions.

Shadows and blurs on a layer designed without them fade in from nothing. Blur amounts use Figma's measure.

On the canvas in Animate:

- With no action selected, dragging a layer moves its design position, and its animation moves with it (To moves included).
- With a Move selected, its path shows: a hollow dot where it starts, a filled dot where it ends, and a curved path's two handles. Drag the layer, or the end dot, to set where it ends; the layer stays where it rests. Drag the handles to bend the path. Drag the start dot to set where it starts (over the layer, hold ⌘).
- With a Resize, Scale or Rotate selected, the layer's outline and handles show it as it will be at the end of the action; drag a handle (or just outside a corner, for Rotate) to set the end, and the playhead goes to the action's end so the layer follows.

The timeline runs the full width of the window in Animate, with the panels above it; drag its top edge to change its height, which every window remembers. The play controls sit over a column of labels naming each row's layer and action; the ruler beside them labels whole seconds and carries the playhead's time in a teal pill. The column lines up with the layers panel above it, and the timeline stops at 0s. Rows run in the order actions were added: a new one goes to the bottom, and dragging a label or bar up or down reorders.

| | |
|---|---|
| M | Switch between Design and Animate |
| Space | Play or pause (Animate) |
| , and . | Previous and next frame (Shift for ten frames) |
| ⌥, and ⌥. | Previous and next start or end of an action |
| Home, End | Go to the start or the end |
| Click the ruler or empty timeline | The playhead slides there |
| Drag the ruler | Scrub |
| Drag the end marker on the ruler | Make the scene longer or shorter |
| Click, Shift-click, ⌘-click, drag a box | Select actions (their layers are selected with them) |
| Drag a bar | Move it in time; drop it on another row to reorder |
| Drag a bar's end (hover it for the handles) | Change its length; with ⌥, both ends move around the middle |
| Hover a label and click its eye | Switch an action off without deleting it |
| Double-click a label or bar | Rename it |
| Drag a label up or down | Reorder the rows |
| Right-click | Stagger, Show Only Selected Layers, Show Times as Frames |
| ← and → | Move the selected actions a frame (Shift for ten) |
| ⌫, ⌘C, ⌘V, ⌘D | Delete, copy, paste at the playhead (onto the selected layers), duplicate after the originals. After a click in the timeline, Delete only ever removes actions |
| Stagger (right-click, or Edit menu) | Start the selected actions a set gap apart, in row order |
| ⌘-scroll or pinch | Zoom the time axis |
| Scroll sideways, or ⌥-drag empty space | Pan |

Bars snap to the playhead, the scene's start and end, and other actions' starts and ends, and always land on frames.

## Exporting

The blue Export button at the foot of the right panel (in Design and Animate), or ⌘E, opens the export panel over the whole window. On the left: the size (50%, 100% or 200%, or Custom… for any percentage, never past 4K: 3840 × 2160 either way round; movies round to even pixels), the format, the frame rate (the composition's, or 24, 25, 30, 50 or 60 fps), the range (the whole scene, or part of it from and to a time) and, when there is sound, Audio. On the right, a preview of exactly what will be written, which plays (Space) at the chosen rate, with its sound. Export asks where to save; the preview then rises out of the way and a counter rolls up to 100% from below, and when it is done they trade back and the button reads Export again, with Show in Finder under it. Cancel, the × or Escape stops an export in flight. Quality is always High. The settings are remembered; the range is kept for the window. File > Export Current Frame (⇧⌘E) still saves a PNG straight away.

| Format | File | Transparency |
|---|---|---|
| H.264 | MP4 | No: a transparent background exports as its colour |
| HEVC | MP4 | No |
| HEVC with transparency | MOV | Yes |
| ProRes 422 | MOV | No |
| ProRes 4444 | MOV | Yes |
| PNG | PNG | Yes |

Export Current Frame… (Shift-⌘E) saves a PNG of what the canvas shows: the frame at the playhead in Animate, the layout in Design. Exports run in the background, with progress and a cancel button at the top of the window, and match the canvas frame for frame. Movies include the sound of video and audio layers unless Audio is off.

## Status

Original milestones 1 to 4 (foundation, evaluation and rendering, canvas and shapes, timeline and playback), then all 8 redesign milestones and export: the action model and its evaluation, separate Design and Animate modes, the action timeline, editing actions in the inspector and on the canvas, MP4, MOV and PNG export, Style and Blur actions, text layers with Text and Shape actions, and pictures, video and sound with Play bars. After those: masks; snapping and alignment; hover, cursors and timeline polish; exporting part of the scene; the ⌘/ shortcuts card; presets made of actions; and a performance pass. Then the pen tool with point editing and the Path action, and the Volume action for fading sound. And any export size, as a percentage, up to 4K. eMotion is for internal use only, never the App Store. See `docs/brief.md` for the original plan, `docs/redesign.md` and `docs/redesign-decisions.md` for the redesign, and Version History on the home screen for what each build changed.
