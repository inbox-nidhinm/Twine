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
        .init(date: "29 September 2026", title: "Faster masks, sturdier export", changes: [
            "Scenes with a mask play much faster: a thousand layers and one mask took 45 ms a frame to work out, and now take under 2 ms.",
            "An export that fails part way stops reading its sounds too, and can no longer wait for ever on a sound that will never finish.",
            "A video that fails to restart after a jump tries again on the next frame, rather than showing nothing.",
            "Shapes with pictures and inner shadows or background blur redraw less when nothing about them has changed, and texts stay laid out while a Counter runs.",
            "The home screen's thumbnails keep open only the current project's videos.",
        ]),
        .init(date: "29 September 2026", title: "Steadier saving and importing", changes: [
            "Saving after importing a large video no longer freezes Twine: an 844 MB clip took three seconds to save, and now takes a tenth of one.",
            "If a project can't be saved when you leave it, Twine says so and offers to try again, rather than closing it and losing the changes.",
            "A file that can't be kept in the project is named in a notice rather than dropped without a word.",
            "A damaged WebM can no longer leave its conversion stuck, and leaving a project stops a conversion still under way.",
            "An import still finishing when you leave a project no longer changes it after it has closed.",
            "Large SVGs and Figma pastes are read without freezing the app, and the home screen reads only projects saved since it last looked.",
            "The copies Twine makes of imported files are cleared away when the project closes, instead of piling up.",
        ]),
        .init(date: "29 September 2026", title: "Copies, masks and undo", changes: [
            "Duplicating, pasting or Option-dragging a layer keeps its blend mode and its width and height link.",
            "A layer and its mask duplicated or pasted together come out as a new pair: the copy is masked by the mask's copy, not the original.",
            "Ungrouping keeps the masks of layers outside the group that use a layer inside it.",
            "A layer taken out of a flipped group, by ungrouping or by dragging it out, stays exactly as it showed, turns and slants included.",
            "Changing something in the inspector while typing on the canvas is its own undo step, in the order it happened.",
            "Durations and action times are held to a day, so typing a huge number no longer crashes Twine.",
        ]),
        .init(date: "28 September 2026", title: "Safer typing and imports", changes: [
            "Words typed on the canvas are kept when you go Home, open another project, close the window or quit before you finish typing. They were lost before.",
            "An SVG that refers to itself, nests or repeats past what any drawing needs, or holds numbers too large to draw is refused or read safely, rather than crashing Twine.",
            "An SVG can no longer pull a file from the Mac, or a web address, into the drawing.",
            "A Figma paste with extreme values reads safely too: stars and polygons keep at most 60 points, and anything placed impossibly far away is left out.",
        ]),
        .init(date: "28 September 2026", title: "Tidier inspector sections", changes: [
            "An empty section, such as Stroke, Effects or Mask with nothing added, has its name centred between its lines.",
            "The last section in the layer inspector has a line under it too.",
            "Back to Presets has a line under it, apart from the action's own settings.",
        ]),
        .init(date: "28 September 2026", title: "Quicker hex fields", changes: [
            "Clicking a hex field selects its digits, so typing or pasting replaces them straight away, as number fields already did.",
            "A short hex code fills out the rest: 0 becomes 000000, 1a becomes 1A1A1A and abc becomes AABBCC.",
        ]),
        .init(date: "28 September 2026", title: "Linear", changes: [
            "The easing that runs at an even speed is called Linear rather than None.",
        ]),
        .init(date: "28 September 2026", title: "The easing card", changes: [
            "Easing is picked from a card of tiles beside the inspector, each showing its curve. Under the pointer, a tile plays a small box moving with that easing.",
            "Picking a tile keeps the card open. Clicking the picked tile again shows its graph and an Intensity slider.",
            "Custom opens its graph straight away, with both handles to drag and its four numbers to type.",
            "New easings: Natural, Bounce, Impulse and Swing. Spring is now called Elastic.",
            "Every easing is the designer's own curve at the standard intensity of 50.",
        ]),
        .init(date: "28 September 2026", title: "Long layer names on the timeline", changes: [
            "On the timeline, a long layer name is cut short so the action's or preset's name always shows beside it.",
        ]),
        .init(date: "28 September 2026", title: "Clean letter by letter animation", changes: [
            "Text presets set to letters, words or lines no longer drag slivers of the lines above and below along with each piece, which made text look doubled and glitchy.",
            "Letters that reach past their own box, such as an f or an italic's tail, are no longer cut off while they move.",
        ]),
        .init(date: "28 September 2026", title: "Shift-click and trimming together", changes: [
            "Shift-click on the timeline selects every action between the last one you clicked and this one. Command-click still adds or takes away one.",
            "With several actions selected, dragging the end of one of them lengthens or shortens them all by the same time.",
        ]),
        .init(date: "28 September 2026", title: "Smaller add buttons", changes: [
            "New Action and Select Preset at the foot of an action's settings are two small buttons, one over the other, rather than big tiles.",
        ]),
        .init(date: "28 September 2026", title: "Add another from an action", changes: [
            "An action's settings end with New Action and Select Preset, so you can add another to the same layer straight away.",
        ]),
        .init(date: "28 September 2026", title: "The composition keeps its size", changes: [
            "Pasting from Figma into an empty project no longer resizes the composition to fit. The copy comes in centred at its exact size, and the composition stays as you set it.",
        ]),
        .init(date: "28 September 2026", title: "Icons in the Effects menu", changes: [
            "The Effects section's add menu shows each effect's icon, as the New Action menu does.",
        ]),
        .init(date: "28 September 2026", title: "A Show hides nothing before it", changes: [
            "A Show no longer hides a layer before it. A layer is shown until something hides it, so everything that happens before a Show still plays. To make a layer appear later, put a Hide at the start or use an In preset.",
        ]),
        .init(date: "28 September 2026", title: "Show and Hide always count", changes: [
            "A Show or Hide is kept whatever presets or other actions come before or after it.",
            "A layer shown before an In preset stays as designed until the preset starts, then plays it, rather than waiting unseen from the start of the scene.",
            "A Show after a fade out brings the layer back to its opacity. Where it is and how big it is stay as the preset left them.",
            "An In preset after a Hide shows the layer again as it plays.",
        ]),
        .init(date: "28 September 2026", title: "Memory let go", changes: [
            "Pictures, videos and waveforms that no layer uses any more are let go from memory a second after you stop editing, so deleting a big picture gives its memory back. Undo brings it back from the project.",
            "Saving no longer reads every picture again to draw the project's thumbnail.",
            "Waveforms show every sound track in a file.",
        ]),
        .init(date: "28 September 2026", title: "Sound, phone videos, WebM and undo", changes: [
            "Portrait videos from a phone no longer come in upside down.",
            "Exported sound never clips: loud clips that overlap are held just under full volume, and quieter sound is left exactly as it was.",
            "Every sound track in a file is heard, not only the first.",
            "An export stops with a clear message naming any sound it cannot read, instead of making a movie without it.",
            "WebM videos can be imported, converted with the ffmpeg installed on this Mac. Transparency is kept.",
            "Undo keeps the last 200 steps, and on very large projects drops the oldest sooner so it never takes more than about 512 MB.",
        ]),
        .init(date: "28 September 2026", title: "Text in Fill and Stroke", changes: [
            "The Text section is laid out afresh: the font, then weight and size, then left, centre and right alignment beside Auto or Fixed, with letter spacing and line height behind its settings button. Justify is no longer offered.",
            "A text's colour is now its Fill, which can be hidden, and a text can have a Stroke round its letters: centred, inside or outside, with its corners in the stroke's settings.",
            "Words are typed on the canvas; the inspector no longer has a box for them.",
        ]),
        .init(date: "28 September 2026", title: "Show is a dot", changes: [
            "On the timeline a Show is drawn as a dot and a Hide as a square, so the two tell apart at a glance.",
        ]),
        .init(date: "28 September 2026", title: "Smaller play controls", changes: [
            "The timeline's play controls are smaller, turn white under the pointer, and the pause button shows white while playing.",
        ]),
        .init(date: "28 September 2026", title: "Back to Presets", changes: [
            "An action's settings have Back to Presets at the top, in place of the presets button beside its name.",
        ]),
        .init(date: "28 September 2026", title: "Arrows for directions, text presets first", changes: [
            "A preset's From and To show arrows instead of Left, Right, Top and Bottom.",
            "With text selected, the preset picker shows the Text presets first.",
        ]),
        .init(date: "28 September 2026", title: "More presets, in groups, and text letter by letter", changes: [
            "The preset picker is in groups: Fade, Scale, Mask, Blur, Emphasis, Text and Sound.",
            "New presets: Shrink, Twist, Move & Scale, Blur & Slide, Blur & Scale, and five Mask presets that reveal the layer inside its own box: Mask Reveal, Mask Center, Mask Resize, Mask & Slide and Mask Shrink. Scale is now called Grow and Rotate is Spin.",
            "On a text, any preset can move its letters, words or lines one by one: Apply to, Order (forward, backward, from the centre, from the edges or random) and Delay are in its settings.",
            "Text presets for text layers: Typewriter, Letters Rise, Letters Pop, Words Blur and Lines Reveal.",
        ]),
        .init(date: "28 September 2026", title: "Icons in the action menu", changes: [
            "Every kind of action in the New Action menu shows its icon beside its name.",
        ]),
        .init(date: "28 September 2026", title: "Roomier play controls", changes: [
            "The timeline's play controls sit further apart, and Loop shows it is on in grey rather than blue, as switches in the inspector do.",
        ]),
        .init(date: "28 September 2026", title: "Icons a little lighter", changes: [
            "Icon lines are a touch lighter than in the last build: 1.6 points on the tools and playback buttons, and lighter in the same proportion at every other size.",
        ]),
        .init(date: "28 September 2026", title: "The export counter slides", changes: [
            "The export's percentage moves the way a Counter with the Slide transition does: each number rises and fades away as the next rises in from below.",
            "The percentage is set in PP Kyoto Thin.",
        ]),
        .init(date: "28 September 2026", title: "Heavier icons", changes: [
            "Icons are drawn with a heavier line: 2 points on the tools and playback buttons, and heavier in the same proportion at every other size.",
        ]),
        .init(date: "28 September 2026", title: "New icons", changes: [
            "Every icon in the app is now the designer's own: the tools, the layers panel, the inspector, the effects, presets and the timeline's playback buttons.",
            "The fields for each corner's radius show a drawing of their corner instead of TL, TR, BL and BR.",
        ]),
        .init(date: "28 September 2026", title: "Buttons in one line", changes: [
            "Every button at the right of the inspector now lines up with the sections' add and remove buttons, and the fields grew a little to keep the same gap before them.",
        ]),
        .init(date: "28 September 2026", title: "The inspector's grid", changes: [
            "Every row in the inspector stops at the same edge, with a column at the right for the button that acts on that row: the links, the corners button, show and hide, the stroke's settings, distribute, mute, and in Animate the links and the button that empties a starting value.",
            "Section headers only add or remove; showing and hiding moved onto the fill's, stroke's or effect's first row.",
            "An ellipse's start, sweep and inner ratio are one joined field, as in Figma, with the sweep as a share of a full turn.",
        ]),
        .init(date: "28 September 2026", title: "Inspector list, part two", changes: [
            "Easing is just the curve you pick: the Intensity slider is gone.",
            "To or By is chosen from a small menu on the row's name.",
            "A curved Move can Rotate along path, turning the layer as the path turns, from its own angle.",
            "With an action selected, the + and preset buttons in its header add another action or a preset to the layer.",
            "The field you are typing in has a thin blue outline, and units such as px, % and ° sit fixed at the end of each field.",
            "A selected shape shows its own outline in blue on the canvas, so you can see its shape even when it is blurred or faded.",
            "The anchor is picked from nine points, the corners, the middles of the edges and the centre, beside rotation.",
        ]),
        .init(date: "28 September 2026", title: "Drag to change numbers", changes: [
            "Drag across any number field to change it, as in Figma: positions, sizes, scale, corner radius, angles, percentages, an action's From, To and By, and the rest. Shift moves ten times as fast, Option a tenth as fast, and each drag undoes in one step. A click still lets you type, with the number selected.",
            "An action's From, To and By have their names above the fields, so the fields take the whole width and long numbers show in full.",
        ]),
        .init(date: "28 September 2026", title: "Position like Figma", changes: [
            "The alignment buttons sit in two trays, left to right and top to bottom, as in Figma; distributing is in a menu from the button beside them.",
            "Scale always shows both ways, SX and SY, with its own link between them.",
            "The link between width and height is now its own setting, off for new layers: when on, typing one changes the other, and resizing on the canvas keeps the proportions too.",
        ]),
        .init(date: "28 September 2026", title: "Presets in pairs", changes: [
            "Presets are no longer grouped into entrances, exits and emphasis. Fade, Slide, Scale, Rotate, Blur, Drop and Sound Fade are each one preset, with In and Out in its settings; their tiles play the way in, then the way out.",
            "New: Rotate Out and Drop Out, so every preset that brings a layer on can also take it off.",
            "Turning a preset from In to Out renames its bar and gives it the Out version's length and easing, unless you changed them.",
        ]),
        .init(date: "28 September 2026", title: "Presets you can see", changes: [
            "In Animate, a selected layer shows two tiles, New Action and Select Preset, in place of the two menus.",
            "Select Preset opens every preset as a tile that plays it on a small square, grouped into entrances, exits, emphasis and sound, so you can see what each does before picking it. Picking one adds it at the playhead and shows its settings.",
        ]),
        .init(date: "28 September 2026", title: "The inspector rearranged", changes: [
            "The layer inspector is now in sections: Position (alignment, X and Y, rotation and the anchor), Layout (width and height with the proportions link between them, scale, corners and Clip content) and Appearance (blend mode and opacity side by side).",
            "With the link on, typing a width or height changes the other to keep the proportions.",
            "Clip content is a check mark.",
            "Stroke shows its alignment as a menu with the width beside it; trim, ends, corners and dashes are in a card from the settings button next to them.",
            "Skew and Tilt moved into Effects, added from its + menu, and every effect shows an icon for what it is.",
            "Several selected layers can share a blend mode as well as an opacity.",
        ]),
        .init(date: "28 September 2026", title: "A quieter inspector", changes: [
            "The inspector no longer uses blue: the chosen tab in a row of choices is a lighter grey, switches that are on sit in the same grey, and the easing curve is drawn in white.",
            "Blue is kept for the selection on the canvas, the layers panel and the Export button.",
        ]),
        .init(date: "28 September 2026", title: "Pictures from Figma", changes: [
            "A Figma frame whose background is a picture now pastes in with the picture as its own layer, Background, at the bottom of the frame, so it shows in the layers panel and can be selected, replaced and animated.",
            "Pictures stacked on one layer in Figma come in as the top one only; the ones under it are not copied, which keeps copies and projects smaller.",
            "The Fill section shows and edits a layer's top fill, the one you see, and the Colour action changes that one too.",
            "The Figma plugin's percentage no longer steps back while it copies pictures.",
        ]),
        .init(date: "28 September 2026", title: "Figma plugin, Twine's look", changes: [
            "The Figma plugin now looks like Twine: a dark panel with a picture of what is selected, its size and how many layers it holds, and a blue Copy button.",
            "While it copies, the percentage and a progress bar show in the preview; once copied, a check shows in its corner.",
        ]),
        .init(date: "28 September 2026", title: "Skew from Figma", changes: [
            "Layers skewed in Figma paste in as editable Twine layers, slanted exactly as in Figma, instead of pictures: shapes, frames with everything inside them, vectors and text.",
        ]),
        .init(date: "28 September 2026", title: "Skew and tilt", changes: [
            "New Skew and Tilt actions: Skew slants a layer each way, and Tilt turns it in depth, back and forth or side to side, seen in perspective, with a Depth setting for how strong the perspective looks. Half a turn shows its back.",
            "Layers can be designed skewed or tilted too: Skew and Tilt fields in the Layer section, under rotation, which the actions animate from.",
            "Skewed and tilted layers export exactly as they show. Their outline on the canvas follows their shape, and clicks land on what is drawn. A tilted layer shows no resize handles; set its size in the inspector.",
            "Playback works out each frame about a tenth faster.",
        ]),
        .init(date: "28 September 2026", title: "Magnetic timeline", changes: [
            "Moving or trimming a bar in the timeline lines it up softly with the start or end of bars on the rows you can see, the playhead and the scene's start and end.",
            "A guide line shows what it lined up with, the trackpad gives a small bump as it catches, and it holds gently until pulled a little further.",
            "Hold ⌘ while dragging to move a bar freely. The canvas's Snapping switch turns timeline snapping off too.",
        ]),
        .init(date: "28 September 2026", title: "Presets on one bar", changes: [
            "A preset now goes on as one bar in the timeline, as in Jitter. Click it to set everything it offers in the inspector: its timing and easing, and settings such as where a slide comes from, how far it travels, how big a pop starts and whether it fades.",
            "Slide In and Slide Out are one preset each, with a From or To choice of left, right, top or bottom.",
            "Dragging a preset bar's ends stretches the whole preset, fades and all.",
            "Right-click a preset bar in the timeline and choose Split into Actions to edit its parts one by one. Presets added before this stay as separate actions.",
        ]),
        .init(date: "28 September 2026", title: "Actions for several layers", changes: [
            "Add Action and Add Preset no longer grey out when a sound is selected along with other layers: they offer what the other layers share, each gets its own bar at the playhead, and the sound is left as it is.",
        ]),
        .init(date: "28 September 2026", title: "Right-click on the canvas", changes: [
            "Right-click (or Control-click) a layer on the canvas for the same menu as the layers panel: rename, duplicate, group, frame, ungroup, solo, lock, hide and delete. Right-click empty canvas to paste. Escape closes the menu.",
            "⌘⌫ ungroups groups and frames, as in Figma, alongside ⇧⌘G. It no longer deletes the selection.",
            "A sound or video and its Play bar go together: deleting the last Play bar in the timeline deletes the layer too, and a project with a sound or video missing its bar gets one back when it opens.",
        ]),
        .init(date: "28 September 2026", title: "Twine everywhere", changes: [
            "The old name is gone: the projects folder is now Twine Creations in Documents, moved there with everything in it the first time this build opens, and settings carry over.",
            "Projects ending in .emotion are no longer opened; none were left.",
        ]),
        .init(date: "27 September 2026", title: "Steady sound", changes: [
            "The outline under the pointer on the canvas is just a line now, with no light wash over the layer.",
            "Sound no longer stutters as playback starts: it starts exactly with the playhead instead of catching up in little jumps.",
            "Sound comes back on the next loop when it ran out before the end of the scene, and no longer jumps on every frame after it ends.",
        ]),
        .init(date: "27 September 2026", title: "Plain selection", changes: [
            "A selected layer shows only its box and handles: the light wash that came over it under the pointer is gone. Layers that are not selected still light up under the pointer.",
        ]),
        .init(date: "27 September 2026", title: "Paste from Figma", changes: [
            "A Twine plugin for Figma (in the FigmaPlugin folder): select a frame or layers, press Copy, then paste in Twine with ⌘V.",
            "Frames, groups, shapes, vectors, pictures, gradients, strokes, shadows, blurs, blend modes and masks come in as editable Twine layers. Text in one style comes in as Twine text; anything Twine cannot hold comes in as a sharp picture Figma drew.",
            "Pasted into an empty project, the composition takes the copy's size and it lines up exactly; into a project with layers, it comes in centred at its exact size.",
            "A note over the canvas says which fonts are not installed (a stand-in shows until they are) and what had to be left out.",
        ]),
        .init(date: "27 September 2026", title: "SVG import", changes: [
            "Import an SVG file (File > Import, or drop it on the canvas) and it comes in as layers you can edit, in a frame named after the file: shapes, groups, colours, gradients, strokes, clip paths and masks, pictures inside it, and holes in shapes.",
            "Rectangles and circles stay rectangles and ellipses where they can, with their corners, so they resize and animate as ones drawn in Twine do; other outlines become paths whose points can be edited.",
            "Figma's exported shadows and blurs come in as Twine's own effects. Text comes in as a sharp picture of itself, in its place, as does anything else Twine cannot edit.",
            "An SVG larger than the composition is shrunk to fit.",
        ]),
        .init(date: "27 September 2026", title: "Blend modes and shadows", changes: [
            "Every layer has a blend mode, under Opacity in Design: Figma's full list, from Multiply and Screen to Overlay, Difference and Luminosity. A group or frame left at Normal lets what is inside it blend through, as Figma's Pass Through does.",
            "Inner shadows, from the Effects menu on shapes and frames: a shadow cast inward from the edge, with its offset, blur, spread and colour.",
            "Shapes and frames draw every drop shadow they have, not only the first, as Figma cards often stack two. Their shadows never show through a see-through fill, and are as faint as the fill is, as in Figma.",
            "Exported frames are about a fifth quicker to draw.",
        ]),
        .init(date: "27 September 2026", title: "Frames", changes: [
            "Frames, as in Figma: the Frame tool (F) draws a white frame that clips what spills over its edges, and takes in the layers it is drawn around. Arrange > Frame Selection (⌥⌘G) puts the selection in a frame.",
            "A frame has its own fill, stroke, corner radius, shadows and blurs, with its fill behind what it holds and its stroke in front. It clips to its rounded corners, and resizing it changes its size rather than stretching what is inside.",
            "Shapes, frames and text drawn inside a frame go into it. Frames take Colour, Stroke, Corner Radius and Resize actions, like rectangles.",
            "Double-clicking goes one level into a group or frame at a time, and once inside, clicks and drags stay at that level: the selected layer, or one beside it, moves rather than the whole group.",
            "Dragging layers into or out of a group or frame in the layers panel keeps them where they are on the canvas, with their actions. A group that clips keeps its shadow, and grouping a layer that masks another keeps the mask.",
        ]),
        .init(date: "27 September 2026", title: "Pictures as fills", changes: [
            "A picture is now a fill, as in Figma: an imported picture is a rectangle filled with it, so it can have rounded corners, a stroke and shadows, and any shape can be filled with a picture by choosing Image under Fill.",
            "Choose how the picture fills its shape: Fill covers it, Fit shows the whole picture, Crop places it by hand, and Tile repeats it at a scale. The turn button beside the choice turns it a quarter at a time, and a picture has its own opacity.",
            "Double-click a picture, or choose Crop, to crop it on the canvas: the rest of the picture shows faintly, drag it to move it, drag its corners to scale it, and drag the layer's handles to show more or less of it. Escape or a click away finishes.",
            "Replace, under the picture in Design, swaps in another picture and keeps the layer, its size and every action on it. Videos have Replace too, and a Fill or Fit choice for a clip of another shape; a play that would run past a shorter clip's end starts earlier in it.",
            "Pictures in older projects become picture-filled rectangles when opened, looking just as they did, with their actions and masks kept.",
        ]),
        .init(date: "27 September 2026", title: "Home screen like re-Flip's", changes: [
            "The home screen now looks like re-Flip's: plain rows down the sidebar, and a dim New Folder row under the folders, which you click and type the new folder's name into.",
            "Project cards have a bigger thumbnail, keeping the picture's own shape with nothing filling its sides, sit on the background until the pointer is over them, and show the date without the time.",
        ]),
        .init(date: "27 September 2026", title: "Folders", changes: [
            "The home screen has folders, down the left under All Projects. + makes one and names it; right-click a folder to rename it, show it in Finder or move it to the Trash with its projects.",
            "Drag a project card onto a folder to put it in, or onto All Projects to take it out, or right-click a card and choose a folder under Move to.",
            "All Projects still shows every project, and each card says which folder it is in. Folders are real folders inside Twine Creations, so the Finder shows the same.",
        ]),
        .init(date: "27 September 2026", title: "One window", changes: [
            "Twine is one window now. Opening a project turns the home screen into the editor, and the Home button (or ⇧⌘H) saves the project and turns it back, with a short fade either way.",
            "One project is open at a time: opening another, from the home screen or the Finder, saves the first and takes its place. Closing the window quits Twine.",
        ]),
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
            "Help > Keyboard Shortcuts (⌘/) shows every Twine shortcut on one card, grouped by where it works: modes and tools, view, the canvas, arranging, playback, the timeline and the project. Escape, ⌘/ or a click outside closes it.",
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
            "Twine's arrow now really is the pointer over the side panels and the timeline too. Those parts put the system arrow back on every move; the app now hands them its own whenever they ask for the arrow.",
        ]),
        .init(date: "26 September 2026", title: "One pointer", changes: [
            "Twine's own arrow is the pointer everywhere in the app: panels, timeline, home screen and canvas. It no longer switches to the system arrow as it crosses from one to another. Text fields keep the text cursor.",
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
            "A home screen of every project in Twine Creations, newest first, with open, rename, duplicate, show in Finder and move to Trash.",
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
