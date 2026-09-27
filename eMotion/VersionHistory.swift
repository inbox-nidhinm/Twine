import SwiftUI
import Theme

/// What the app has been, newest first.
///
/// Every change to the app gets an entry here, kept current as part of the
/// work rather than caught up with later. Put a new build at the top of
/// `builds`; the numbers count themselves off the list. `make-app.sh` reads the
/// same count into the bundle's version, so nothing else needs editing.
enum VersionHistory {
    static var version: String { "\(builds.count)" }

    struct Build: Identifiable {
        let date: String
        let title: String
        let changes: [String]
        var id: String { date + title }
    }

    static func number(of build: Build) -> Int {
        guard let i = builds.firstIndex(where: { $0.id == build.id }) else { return 0 }
        return builds.count - i
    }

    static let builds: [Build] = [
        .init(date: "27 September 2026", title: "The .twine file", changes: [
            "New projects end in .twine, shown in Finder as Twine projects. Projects that still end in .emotion open and save just as before.",
        ]),
        .init(date: "27 September 2026", title: "Twine", changes: [
            "The app is now called Twine, with a new icon: in the Dock, in Finder, in the menus and on the home screen.",
            "Projects keep their .emotion ending and stay in the eMotion Creations folder, so everything made so far opens as before, and every setting is kept.",
            "The export counter steps each digit up once as it changes, rather than rolling like an odometer.",
        ]),
        .init(date: "27 September 2026", title: "Export panel lined up", changes: [
            "The export panel's settings column is now as wide as the layers panel, so its edge lines up with it.",
            "The counter's digits step up once each time they change, instead of rolling like an odometer, and fade softly in and out rather than being cut off at a hard edge.",
        ]),
        .init(date: "27 September 2026", title: "A new export panel", changes: [
            "Export is a blue button at the foot of the right panel, in Design and Animate. It opens a panel over the whole window: the settings on the left, and on the right a preview of exactly what will be exported, which plays with its sound (Space plays and pauses).",
            "Choose the size (50%, 100%, 200% or any percentage, up to 4K), the format, a frame rate for the movie (the composition's own, or 24, 25, 30, 50 or 60 fps), the range, and whether to include sound. Quality is always High.",
            "Exporting sends the preview up and out and brings a big percentage counter up from below, its digits rolling on like an odometer. When it finishes they trade places back, and the button offers Export again, with Show in Finder under it.",
            "Cancel stops an export part way, as do the cross and Escape, which close the panel. Nothing half-written is left behind.",
        ]),
        .init(date: "27 September 2026", title: "Any export size", changes: [
            "Under the Size menu in Export, type any percentage of the composition, such as 150% or 33.3%, as well as picking 50%, 100% or 200%. Size shows the pixels it will be.",
            "Exports never go past 4K (3840 × 2160, either way round): a size that would is greyed out in the menu, and a larger composition exports at 4K. Movies still round to even numbers of pixels.",
            "The Volume slider in Design stops at 100%, the file's own level, as the Volume action does.",
        ]),
        .init(date: "27 September 2026", title: "Volume fades", changes: [
            "A new Volume action, under Media in Animate, fades a video's or a sound's level to anywhere from 0% to 100%, following its easing. It is heard as the timeline plays and in exported movies.",
            "Add Preset has Fade Sound In and Fade Sound Out, each a second long.",
            "Volume, the sound presets and the Sound section in Design only appear for sounds and for video that has a sound track.",
            "A Play bar's waveform tapers where the sound fades.",
        ]),
        .init(date: "27 September 2026", title: "Pen tool and point editing", changes: [
            "The Pen (P) is back in the toolbar. Click to place points, drag to pull out curve handles, and click the first point to close the shape; Escape or Return leaves it open, as a line. The pointer shows when a click will add a point to a line, move a point, or join onto an end.",
            "Double-click a shape, or press Return, to edit its points as in Figma: pick them by clicking or with a box, drag points, handles or segments, ⌘-click to make a point sharp or smooth, ⌘-drag to pull out handles, Option-drag to move one handle alone, and Delete to take points out. Rectangles, ellipses, lines, polygons and stars turn into paths when their points change.",
            "A new Path action, under Shape in Animate, morphs a path into a new shape: select it and drag the end shape's points on the canvas.",
            "Resizing a path stretches it, in Design and with a Resize action.",
        ]),
        .init(date: "26 September 2026", title: "Pointers on the timeline", changes: [
            "The timeline's top edge shows the up-and-down arrows, and the scene's end on the ruler the sideways arrows, reliably now: the window's SwiftUI had been putting its arrow back over them.",
            "The playhead's pill is a handle: the open hand over it, the closed hand while it is held, and it drags from where it was grabbed instead of jumping to the pointer.",
        ]),
        .init(date: "26 September 2026", title: "Faster with busy scenes", changes: [
            "Measured on a scene of 200 layers and 990 actions: dragging a layer is about twice as quick (15 to 7 milliseconds a step), dragging a timeline bar a fifth quicker, and scrubbing about a third quicker. Playback holds 60 frames a second.",
            "Working out a frame takes less than half as long as before, and a still layout under a fifth, which also speeds up exports.",
            "Text is measured once for each set of words and style and remembered, the canvas only redraws layers that changed, and the layers panel no longer checks every layer for every row.",
        ]),
        .init(date: "26 September 2026", title: "Presets", changes: [
            "Add Preset, under Add Action in Animate, applies a ready-made animation at the playhead: entrances (fade, slide in from each side, scale pop, rotate in, blur in, drop in), exits (fade, slide out to each side, scale out, blur out) and emphasis (pulse, bounce, shake, wiggle).",
            "A preset only adds ordinary actions, on new rows, selected and played through, so every part of it can be retimed, re-eased or deleted like any other action. It works from the layer as it looks at the playhead, wherever it is and however faded.",
        ]),
        .init(date: "26 September 2026", title: "Keyboard shortcuts card", changes: [
            "Help > Keyboard Shortcuts (⌘/) shows every eMotion shortcut on one card, grouped by where it works: modes and tools, view, the canvas, arranging, playback, the timeline and the project. Escape, ⌘/ or a click outside closes it.",
            "The Pen tool's greyed-out button is gone from the toolbar, since the pen tool is no longer planned.",
        ]),
        .init(date: "26 September 2026", title: "Export part of the scene", changes: [
            "Export > Range exports the whole scene or only part of it: choose Part of the scene and type where it starts and ends. The movie starts at the From time, and its sound comes with it, in step.",
        ]),
        .init(date: "26 September 2026", title: "Option-drag to duplicate", changes: [
            "In Design, hold Option and drag a layer to leave it where it is and drag away a copy, animation included, as in Figma. The copy snaps to the original like any other layer, and one Undo takes it back. An Option-click that never moves makes no copy.",
        ]),
        .init(date: "26 September 2026", title: "Hover everywhere on the canvas", changes: [
            "Fixed: hover failed over the upper part of the canvas, worst in Animate, where a layer near the top did not respond and a tall one only answered over its lower half. The check for whether the pointer was over a panel looked at the spot mirrored top to bottom, which in Animate landed on the timeline.",
            "The same mix-up could end typing in a text field when clicking inside it; that is fixed too.",
        ]),
        .init(date: "26 September 2026", title: "Clearer hover", changes: [
            "Hovering a layer on the canvas now gives it a faint wash inside a thin white outline with a dark edge, which shows on artwork of any colour (a grey layer hid the first grey version) and never reads as a selection.",
            "A selected layer answers the pointer too: it takes the wash inside its blue outline.",
            "Its row in the layers panel shows the full hover state, solo, lock and eye switches included, just as when the pointer is on the row itself.",
        ]),
        .init(date: "26 September 2026", title: "New rows come into view", changes: [
            "When a new action's row lands below what the timeline shows, the timeline scrolls down to it, so you always see what you added.",
            "eMotion's arrow now really is the pointer over the side panels and the timeline too. Those parts put the system arrow back on every move; the app now hands them its own whenever they ask for the arrow.",
        ]),
        .init(date: "26 September 2026", title: "One pointer", changes: [
            "eMotion's own arrow is the pointer everywhere in the app: panels, timeline, home screen and canvas. It no longer switches to the system arrow as it crosses from one to another. Text fields keep the text cursor.",
        ]),
        .init(date: "26 September 2026", title: "Gliding playhead", changes: [
            "A click on the ruler or on empty timeline slides the playhead to that point in a fifth of a second, rather than jumping. Dragging still scrubs directly.",
            "Adding an action plays it: the playhead runs from its start to its end at real speed (a long one hurried to a second) and waits there, so the next action you add follows on.",
        ]),
        .init(date: "26 September 2026", title: "Hover and pointers", changes: [
            "Hovering a layer on the canvas outlines it and lights up its row in the layers panel; hovering a row outlines its layer on the canvas.",
            "New pointers: an arrow and a crosshair for the canvas, resize arrows that follow a turned layer's handles, turn arrows that curl round each corner, and resize arrows on the timeline's bar ends, the scene's end and the timeline's top edge.",
            "Hold Space in Design and drag to pan the canvas, with a hand pointer; the middle mouse button pans too. Option-dragging the timeline shows the hand while it pans.",
            "Click an empty part of the timeline to move the playhead there.",
        ]),
        .init(date: "26 September 2026", title: "Timeline hover", changes: [
            "Hovering a bar shows a handle at each end. Grab a handle to change when the action starts or ends; the pointer turns into a resize arrow over them.",
            "A timeline label lights up under the pointer, as a layers panel row does, and shows its eye only then. An action switched off shows as a dimmed label and bar.",
        ]),
        .init(date: "26 September 2026", title: "Smart guides and alignment", changes: [
            "Moving, resizing and drawing snap to the composition's edges and centre and to other layers' edges and centres, with red guides showing what lined up.",
            "Moving also snaps to even spacing: centred between two neighbours, or one gap on from a row that already keeps one. The equal gaps show with their size.",
            "Hold ⌘ while dragging to place freely. View > Smart Guides turns snapping off altogether.",
            "Align and distribute from the new Arrange menu, the buttons across the top of the inspector, or Figma's keys: ⌥A, ⌥H, ⌥D, ⌥W, ⌥V, ⌥S, and ⌃⌥H and ⌃⌥V to space three or more layers evenly. One layer aligns with the composition; several with each other.",
        ]),
        .init(date: "26 September 2026", title: "Masks", changes: [
            "Any layer can be masked by another: press + under Mask in the inspector and pick the mask. The layer shows only where the mask draws, and the mask itself stops drawing. Invert shows it everywhere else.",
            "Shapes, text, pictures and video can all be masks, and a group can be masked by a layer inside it.",
            "Masks animate: move, scale, fade or blur the mask and the reveal follows. It all carries through to export.",
            "A mask shows its own icon in the layers panel. Select it there to move it on the canvas. Clicks on the canvas only pick what a mask lets show.",
        ]),
        .init(date: "26 September 2026", title: "Timeline touches", changes: [
            "The timeline's label column is as wide as the layers panel, so its divider lines up with the panel's right edge.",
            "The timeline stops at 0s: it no longer scrolls back into time before the start.",
            "The ruler labels whole seconds only, with dots between.",
        ]),
        .init(date: "26 September 2026", title: "A new timeline", changes: [
            "Labels down the left name each row's layer and action, with the play controls above them. Rows are taller and the bars simpler, with a faint line between rows.",
            "Rows run in the order actions were added, whatever their layer: a new action goes to the bottom. Drag a row's label, or its bar, up or down to put it anywhere.",
            "The playhead is teal, with the time in a pill on the ruler. The ruler shows seconds with dots between.",
            "A selected action lights up its whole row. Hover a label to find its eye, which switches the action off; the eye stays while it is off. Double-click a label to rename.",
            "Right-click the timeline for Stagger, Show Only Selected Layers and Show Times as Frames.",
        ]),
        .init(date: "26 September 2026", title: "Typing on the canvas", changes: [
            "Type straight onto the canvas. The Text tool places a text layer ready to type over; double-click a text layer to type where you clicked; press Return with a text layer selected to edit all of it. Escape, or a click away, finishes.",
            "The caret and selection sit exactly on the letters, at any zoom and on turned text. Click to move the caret, drag or Shift-click to select, double-click for a word, triple-click for everything.",
            "Every Mac typing habit works: arrows with Option and Command, Shift to select, Delete by letter or word, Copy, Cut and Paste, accents by holding a key, and input methods for other languages.",
            "While typing, Undo steps back through your typing; afterwards the whole edit undoes as one step. A text left empty is removed.",
        ]),
        .init(date: "26 September 2026", title: "Pictures, video and sound", changes: [
            "Import pictures, video and sound with File > Import… (⌘I), or drop them on the canvas. Each becomes a layer; the file is copied into the project, so moving or deleting the original does no harm, and importing the same file twice keeps one copy.",
            "Video and sound get a Play bar on the timeline. Drag it to set when it plays. Drag its left end to trim the start of the clip, its right end to trim the end; neither goes past the clip's own ends. A video shows its first frame before its bar and its last frame after.",
            "Sound plays with the timeline, and a sound's waveform shows in its Play bar. Volume and mute are in Design, under Sound.",
            "Exports include the sound (switch it off under Export > Audio) and every video frame exactly as it falls on the timeline.",
            "Copy Easing and Paste Easing (Option-Command-C and V, in the Edit menu) give one action's easing to others.",
            "The timeline stays quick with thousands of actions.",
        ]),
        .init(date: "26 September 2026", title: "Text, and text and shape actions", changes: [
            "Text layers. Pick the Text tool (T) and click: a text layer appears with its words selected in the inspector, ready to type over. Double-click a text layer to edit its words again. The layer's name follows its words until you rename it.",
            "The Text section sets the font (a searchable list of every font on this Mac, each shown in itself), weight, size, colour, alignment, letter spacing, line height, and auto or fixed width. A font this Mac does not have shows crossed out, and the text draws in SF Pro. Dragging a text box's side makes it fixed width.",
            "Text actions: Letter Spacing, Line Height, Counter and Change Text. Colour, Shadow and Layer Blur work on text too.",
            "Counter counts in the text's own style: \"$1,200.50\" counts in dollars and cents, \"007\" keeps its zeros. It can snap, fade or slide from number to number, with evenly spaced digits so the text does not jiggle.",
            "Change Text swaps the words with a transition out and in (none, fade, slide or scale), one after the other or overlapping.",
            "Ellipses gain Start, Sweep and Ratio in Design, for pie slices and rings, and an Arc action. Stars gain a corner radius, and a Star action for points, inner radius and corners.",
            "Text boxes grow the way their alignment reads: left-aligned text to the right, centred both ways, right-aligned to the left.",
        ]),
        .init(date: "26 September 2026", title: "Style and blur actions", changes: [
            "Seven new actions, listed under Style and Blur in Add Action: Colour, Stroke, Trim, Corner Radius, Shadow, Layer Blur and Background Blur. Each is offered only where it applies: Stroke and Trim for shapes with a stroke, Corner Radius for rectangles, Background Blur for shapes.",
            "Colour changes the first fill, to a colour or a linear or radial gradient. Gradients blend their colours, stops and direction, even between different numbers of stops.",
            "Trim draws a stroke on; a new one starts from nothing and draws the whole line. Stroke changes its width and colour together.",
            "Shadow and Background Blur on a layer designed without one fade in from nothing. A shadow set to start from nothing keeps its colour, so only its opacity needs raising.",
            "Design mode gains Background Blur (frosted glass, with a blend) under Effects, and Spread for drop shadows.",
            "Blurs are now centred where they belong. They used to sit about 9 px off, down and to the left, on the canvas and in exports alike. Blur amounts follow Figma's measure, so existing blurs and shadows look about half as soft as before.",
            "Add Action's menu is grouped under Transform, Style and Blur.",
        ]),
        .init(date: "26 September 2026", title: "Export", changes: [
            "Export movies: MP4 in H.264 or HEVC, or MOV in HEVC with transparency, ProRes 422 or ProRes 4444. Or save the current frame as a PNG.",
            "With nothing selected in Design, the Export section under Composition picks the format, the size (50%, 100% or 200%) and, for H.264 and HEVC, the quality. It remembers them for next time.",
            "Export… (⌘E) asks where to save and exports with those settings. Export Current Frame… (Shift-⌘E) saves a PNG of what the canvas shows: the frame at the playhead in Animate, the layout in Design.",
            "Exports run in the background with a progress bar at the top of the window and a button to cancel; you can keep working. When it's done, Show in Finder takes you to the file.",
            "A transparent background stays transparent in HEVC with transparency, ProRes 4444 and PNG, with clean soft edges in editing apps. The other formats fill it with the background colour.",
            "Every frame is drawn by the same renderer as the canvas, one after another, so an export matches what you see and is the same every time. A cancelled export never leaves half a file or replaces the old one.",
        ]),
        .init(date: "26 September 2026", title: "Editing actions", changes: [
            "Select an action and the inspector shows only its fields: start and length, easing, To or By, where it starts and where it ends. Several actions of one kind edit together.",
            "Easing: None, Smooth, Slow down, Accelerate, Overshoot and Spring, each with an intensity, or a Custom curve with handles to drag.",
            "A starting value can be left empty, and then it starts from wherever the layer is; the greyed number shows what that will be. Switching between To and By keeps the motion as it was.",
            "A selected Move shows its path on the canvas. Drag the layer or the end dot to set where it ends, turn on Curved path and drag its handles to bend it, and drag the start dot (with Command, over the layer) to set where it starts.",
            "A selected Resize, Scale or Rotate shows the layer as it will be at its end, with handles to drag.",
            "Moving a layer's design position carries all of its moves along, To moves included.",
            "Clicking anywhere in a number box starts typing, not just on the number. After a click in the timeline, Delete only removes actions.",
        ]),
        .init(date: "26 September 2026", title: "The action timeline", changes: [
            "In Animate the timeline runs the full width of the window, with the panels above it. Drag its top edge to change its height; every window remembers it.",
            "One row per action, under a divider for its layer, in the layers panel's order. Each bar shows its action, name and layer; hide and show are small markers.",
            "Drag a bar to move it in time, or onto another of its layer's rows to reorder. Drag an end to change its length, with Option for both ends. Bars snap to the playhead, the scene's ends and other actions, and land on frames.",
            "Click, Shift-click, Command-click or drag a box to select; the actions' layers are selected with them. Click an eye to switch an action off. Double-click a bar to rename it.",
            "Delete, copy, paste at the playhead onto the selected layers, and duplicate after the originals. Arrow keys move selected actions a frame, Shift ten. Stagger spaces selected actions by a gap you choose.",
            "Comma and full stop step a frame (Shift for ten, Option for the previous or next action edge). Drag the end marker on the ruler to change the scene's length. Option-drag or scroll sideways to pan.",
            "The filter in the timeline's header shows only the selected layers' actions. Copying and pasting a layer brings its actions with it.",
        ]),
        .init(date: "26 September 2026", title: "Design and Animate, apart", changes: [
            "Press M to switch modes. Design shows the layout as designed, with no animation, and only design settings. Animate shows the moment at the playhead and never shows design settings.",
            "In Animate, select a layer and use Add Action to add a move, scale, rotate, opacity, resize or hide/show at the playhead, half a second long. The inspector lists the layer's actions.",
            "In Animate, the canvas only selects and moves. Dragging a layer moves where it is designed, and its animation comes with it. Resizing, turning and drawing belong to Design.",
            "Playback is for Animate; Space does nothing in Design.",
        ]),
        .init(date: "26 September 2026", title: "Actions underneath", changes: [
            "Animation now works like Jitter underneath: a layer's properties are how it is designed, and actions (move, scale, rotate, opacity, resize, hide and show) change them over time. Adding and editing actions in the app comes with the next builds.",
            "Keyframes, stopwatches and layer in and out bars are gone. The inspector shows each layer as designed.",
            "Duplicating, pasting, grouping and ungrouping keep each layer's actions with it.",
            "Projects from earlier builds show a plain message and no longer open.",
        ]),
        .init(date: "25 September 2026", title: "Fixes to fields and easing", changes: [
            "A number typed into a field and confirmed with Return no longer goes back to the old value when you click somewhere else. The same for hex colours.",
            "The Easing menu is greyed out when only a property's last keyframe is selected, since easing shapes the move to the next keyframe and there is none.",
            "Menus open on every click.",
        ]),
        .init(date: "25 September 2026", title: "The timeline", changes: [
            "Animate mode's timeline: a row per layer, with its bar from in point to out point, and its animated properties underneath when opened. Drag a bar to move the layer in time, or an end to trim it. Drag the timeline's top edge to make it taller.",
            "Keyframes on the timeline: click, Shift-click or drag a box to select, drag to move them, landing on frames and snapping to the playhead, other keyframes and the ends of layers. Delete, copy, paste at the playhead and duplicate follow whichever you clicked last, the timeline or the canvas.",
            "A stopwatch beside every property in the inspector. On, it keys the value at the playhead; after that, any change in Animate mode keys it at the playhead, from the canvas or the inspector. In Design mode a change moves the whole animation instead. Off, the keyframes go and the value at the playhead stays.",
            "Easing for the selected keyframes: linear, hold, twelve presets, a custom curve with handles to drag, or a spring with its stiffness, damping and mass, and how long it takes to settle. A spring moves the next keyframe to where it settles.",
            "Playback in real time. Space plays and pauses, [ and ] step a frame, Home and End go to the ends, and it loops unless you switch that off. Click or drag the ruler to scrub. Click the time to read it in frames.",
            "Trim start and end on strokes, so a line can draw itself on.",
            "The app's own colour picker, drawn on the panel card like Flip's, in place of the system colour panel.",
        ]),
        .init(date: "25 September 2026", title: "Drawing on the canvas", changes: [
            "The canvas draws the composition with the real renderer. Pinch or Command-scroll to zoom about the pointer, scroll with two fingers to pan, Command-0 to fit, Option-Command-0 for actual size.",
            "Rectangle, ellipse, line, polygon and star: drag to draw, Shift for a square, a circle or a 45 degree line, Option to draw from the centre, or click for a standard size. The tool hands back to the arrow when you finish.",
            "Select by clicking, Shift-click to add, or drag a marquee over empty canvas. A click inside a group picks the group; Command-click or a double-click reaches the shape inside.",
            "Drag to move, Shift to keep to one axis. Eight handles resize from the opposite side, Shift keeps proportions, Option resizes from the centre. Just outside a corner turns the layer, Shift in 15 degree steps. Command-drag the anchor marker to move the anchor.",
            "Arrow keys nudge by a pixel, Shift by ten. Delete removes. Duplicate, group, ungroup, copy, paste and restacking are in the Edit menu with their usual keys.",
            "The layers panel lists the tree front to back, with groups that fold, hide, lock and solo on each row, a right-click menu, renaming, and drag to restack or drop into a group.",
            "The inspector edits the selected layer: position, size, rotation, scale, anchor and opacity; corner radius, sides and points; a solid or gradient fill; a stroke with its width, alignment, caps, joins and dashes; drop shadows and blur.",
            "The pen and text tools are shown but switched off until their milestones.",
        ]),
        .init(date: "25 September 2026", title: "Everything worked out at any moment", changes: [
            "Every property can now be worked out at any moment of the animation, between frames included: keyframes, the easing presets, custom curves, holds and springs.",
            "Colours blend through a perceptual colour space, so red to blue passes through purple rather than grey.",
            "A spring keeps its own natural length; stretch the segment and the bounce stretches with it rather than jumping.",
            "The renderer that draws the canvas also draws off screen, which is how the export will draw, so what you see is what you get.",
            "Home screen cards show each project's first frame.",
        ]),
        .init(date: "25 September 2026", title: "Clicks land where they should", changes: [
            "The Design and Animate switch, the Composition header and the tools answer clicks again. The inspector's list had been stretching up under the title bar and catching clicks meant for the controls above it, and even sent some to the width field.",
            "Nothing takes the keyboard when a window opens, so typing no longer goes into the composition's width.",
            "Clicking anywhere outside a text field ends the edit and keeps what was typed.",
            "The traffic lights stay in the left panel's corner without the loop that crashed the app when a project opened in the background.",
            "Section headers are real buttons, so a click anywhere on the row folds them.",
        ]),
        .init(date: "25 September 2026", title: "The foundation", changes: [
            "A home screen of every project in eMotion Creations, newest first, with open, rename, duplicate, show in Finder and move to Trash.",
            "New projects are written to disk the moment they are made and save themselves from then on. Closing a window never asks a question, and File > Revert To browses older versions.",
            "The project file is a package: document.json with a format version, and a media folder for imported files.",
            "Every change goes through one set of commands, so every change can be undone. A drag or a colour pick undoes as one step.",
            "The editor's shell: the canvas full-bleed, the layers panel and the inspector floating over it, and the Design and Animate switch at the head of the inspector.",
            "Composition settings: size, frame rate (including 23.976, 29.97, 59.94 and custom rates), duration, and a background colour or transparency.",
            "Flip's design system, with a light blue accent, from the Figma file: its colours, type, metrics, grain and controls.",
        ]),
    ]
}

/// The list, on the same floating card as everything else.
struct VersionHistoryCard: View {
    let dismiss: () -> Void

    private let cardWidth: CGFloat = 600
    private let pad: CGFloat = 18

    var body: some View {
        ZStack {
            Theme.badge
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Version History")
                        .font(ThemeFont.labelStrong)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 0)
                    IconButton(icon: .close, help: "Close (Esc)", action: dismiss)
                }
                .padding(.horizontal, pad)
                .frame(height: 38)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(VersionHistory.builds) { build in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(build.title)
                                        .displayTitle(20)
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer(minLength: 0)
                                    Text("Build \(VersionHistory.number(of: build)) · \(build.date)")
                                        .font(ThemeFont.caption)
                                        .foregroundStyle(Theme.textTertiary)
                                }
                                ForEach(build.changes, id: \.self) { change in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Circle().fill(Theme.textTertiary).frame(width: 3, height: 3)
                                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 }
                                        Text(change)
                                            .font(ThemeFont.label)
                                            .foregroundStyle(Theme.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                    .padding(pad)
                }
                .frame(maxHeight: 520)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: cardWidth)
            .floatingPanel()
            .onExitCommand(perform: dismiss)
        }
    }
}
