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
