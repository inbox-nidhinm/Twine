import SwiftUI
import Theme

/// What the app has been, newest first.
///
/// A build is a release: a stretch of work you would install and try, not one
/// change. Each lists what it added (`features`), what it mended (`fixes`) and
/// anything else worth knowing (`misc`, left out when empty). Work goes into the
/// top build's lists as it is done; a new build is put at the top of `builds`
/// only when the user says to cut one. The numbers count themselves off the
/// list, and `make-app.sh` reads the same count into the bundle's version, so
/// nothing else needs editing.
enum VersionHistory {
    static var version: String { "\(builds.count)" }

    /// How many pushes to GitHub the app has had, this one included. Raise it by
    /// one with every push: the first was v0.0.01, the 100th is v0.1.00. It matches the repo's commit count once the commit that raises it is made.
    static let pushes = 145

    static var release: String { String(format: "v0.%d.%02d", pushes / 100, pushes % 100) }

    struct Build: Identifiable {
        let date: String
        let title: String
        var features: [String] = []
        var fixes: [String] = []
        var misc: [String] = []
        var id: String { title }

        /// The lists that have something in them, under their headings.
        var sections: [(heading: String, items: [String])] {
            [("Feature updates", features), ("Bug fixes", fixes), ("Misc", misc)]
                .filter { !$0.1.isEmpty }
        }
    }

    static func number(of build: Build) -> Int {
        guard let i = builds.firstIndex(where: { $0.id == build.id }) else { return 0 }
        return builds.count - i
    }

    static let builds: [Build] = [
        .init(date: "30 September 2026", title: "Motion blur", features: [
            "Motion blur on actions. Any action or preset that moves, scales, turns, skews or tilts a layer has a Motion blur switch under Easing. While it plays, the layer smears along its movement, as a camera's shutter does.",
            "Amount sets how long the shutter stays open: 50% is a 180° shutter, 100% a whole frame.",
            "Only what that action moves smears; anything else the layer does at the same time stays sharp. Text presets that move letter by letter blur each letter by its own motion.",
            "Swap Preset. With a preset selected, Swap Preset puts another in its place. The bar keeps when it starts and takes the new preset's name, easing and length unless you had changed them.",
            "Copy actions from one layer onto another. Copy bars in the timeline (Command-C, or Cut and Copy on a bar's right-click menu), then paste onto another layer with Command-V, Paste on a timeline row's right-click menu, or Paste Action on a layer's right-click menu. Each lands at the playhead on a row just under that layer's others, with the same length, easing and settings, and makes the same motion from where the new layer stands: a Move to a spot travels as far the same way.",
            "Duplicate in the timeline, from the right-click menu or Command-D. The copy goes on the row just below its original, starting where the original ends, and is selected.",
            "A plainer tool bar. The tools sit straight on the bar without the darker tray behind them, the hover highlight slides from tool to tool as the pointer moves along the bar, and the blue of the tool in hand slides to the next tool picked, by a click or its key.",
        ], fixes: [
            "Presets copied in the timeline paste onto other layers too. Before, only ordinary actions did.",
            "Delete in a layer's right-click menu deletes it at once. After a click in the timeline it deleted the selected actions instead, often none, so it took several tries. Clicking a layer in the layers panel also makes Delete, Duplicate and Copy act on layers again.",
            "Renaming the project above the layers panel shows the new name at once. It used to go back to the old name for a few seconds while the file was moved.",
            "In exports, a light layer no longer turns white while it blurs. Exports draw each moment across the shutter in full and average them exactly, so groups, masks and blend modes inside a blurring layer look right too.",
            "A layer with motion blur no longer flashes somewhere else for a frame where its motion jumps, as when a Move starts from a From of its own, or where it turns out of edge-on. Those frames are drawn sharp.",
            "Once its blur ends, a layer is drawn exactly as it was before it blurred.",
            "Playing a project with many sound clips no longer stutters. With a dozen clicks and sounds, asking the sound player where it was held up every frame for most of a second, so playback ran at two frames a second and the sound kept restarting. It now plays at a full 60, with the sound within a hundredth of a second of the playhead.",
            "The tool bar's hover highlight slides as smoothly right to left as left to right. Going leftwards it could stick to the tool just left.",
            "Duplicating a sound's bar in the timeline no longer crashes or freezes Twine. A copy that landed out of view sent its waveform drawing into a loop that never ended, or, before that, a place in the sound too large to count; a bar out of view now draws no waveform.",
        ], misc: [
            "The close buttons on the Keyboard Shortcuts and Version History cards sit as far in from the right as they sit down from the top, tucked into the corner.",
            "On the home screen, the build number beside Version History sits as far in from the right as the words do from the left.",
            "Version History breathes: more room between the lines of each point (about 155%), between points, between sections and their headings, and between builds.",
            "The canvas shows a lighter motion blur as you play and scrub; exports draw it at full quality, so frames with motion blur take longer to export.",
            "An action switched off in the timeline always shows its crossed-out eye, not only under the pointer, as a hidden layer does in the layers panel. Clicking it switches the action back on.",
            "Back to Presets and the plus beside an action's name are gone. New Action and Select Preset stay at the foot of the inspector.",
        ]),
        .init(date: "29 September 2026", title: "Steadier and safer", features: [
            "Onboarding. The first time Twine opens, a card introduces it in three pages, as Flip's does: what Twine is, where it keeps your projects, and five things it does. The pages turn like the leaves of a book. The pictures are placeholders for now, ready to be swapped for videos.",
            "The second page chooses the folder Twine keeps projects in. Projects already made stay where they are. Help > Show Onboarding brings it back; Escape leaves it at any page and Return turns the page.",
            "Swap From and To. An action's To row has a button that swaps its From and To, so it plays backwards: a Resize from 300 to 360 becomes one from 360 to 300. An empty From is filled in with where the layer would have started. It works for every action with a start and an end, and a curved Move runs its same path the other way.",
            "Hover follows the shape. The layer under the pointer is outlined in the selection's thin blue line, following its own shape (a circle's circle, a star's points, a frame's rounded corners), as in Figma. Text and groups still show their box.",
            "Double-clicking a layer in the layers panel renames it, as in Figma.",
            "Volume in Animate. A selected sound or video with sound shows its Sound section, the volume slider, over its actions, and under the fields when its Play bar is selected. It is the same level as in Design, the one every Volume action starts from. The mute button is gone in both modes; a sound muted before comes back as soon as its slider is moved.",
            "A real typewriter. Typewriter puts each letter on at once, one after another, rather than fading them up, spread evenly across the bar so its length sets how fast it types. It has an Out, which takes the letters away one at a time, and typewriters added before this type too, as long as their settings were not changed.",
            "The Solid, Linear, Radial and Image choices for a fill are the designer's icons, with their names as tooltips, in the Fill section and wherever a colour or gradient is picked. Icons can draw some of their lines fainter, as the linear icon's dots fade across.",
        ], fixes: [
            "Blend modes now blend with the composition's background, as in Figma. Before, a layer over nothing but the background drew as Normal whatever its mode, on the canvas and in exports, so Overlay seemed to do nothing. Now Overlay or Screen over a white background turns white, and Multiply over it keeps the layer's own colour.",
            "Text inside a frame or group that is scaled up stays sharp, on the canvas and in exports. It was drawn at its own size and stretched, so a Figma frame scaled to 300% had soft words while its shapes stayed crisp.",
            "Numbers and hex codes sit centred in their fields, as the words in menus do. They were a pixel low, most visibly on screens that are not Retina.",
            "Duplicating, pasting or Option-dragging a layer keeps its blend mode and its width and height link.",
            "A layer and its mask duplicated or pasted together come out as a new pair: the copy is masked by the mask's copy, not the original. Ungrouping keeps the masks of layers outside the group that use a layer inside it.",
            "A layer taken out of a flipped group, by ungrouping or by dragging it out, stays exactly as it showed, turns and slants included.",
            "Changing something in the inspector while typing on the canvas is its own undo step, in the order it happened.",
            "Durations and action times are held to a day, so typing a huge number no longer crashes Twine.",
            "Saving after importing a large video no longer freezes Twine: an 844 MB clip took three seconds to save, and now takes a tenth of one.",
            "If a project can't be saved when you leave it, Twine says so and offers to try again, rather than closing it and losing the changes. A file that can't be kept in the project is named in a notice rather than dropped without a word.",
            "A damaged WebM can no longer leave its conversion stuck, and leaving a project stops a conversion still under way. An import still finishing when you leave a project no longer changes it after it has closed.",
            "Large SVGs and Figma pastes are read without freezing the app, and the home screen reads only projects saved since it last looked. The copies Twine makes of imported files are cleared away when the project closes, instead of piling up.",
            "Scenes with a mask play much faster: a thousand layers and one mask took 45 ms a frame to work out, and now take under 2 ms.",
            "An export that fails part way stops reading its sounds too, and can no longer wait for ever on a sound that will never finish. A video that fails to restart after a jump tries again on the next frame, rather than showing nothing.",
            "Shapes with pictures and inner shadows or background blur redraw less when nothing about them has changed, and texts stay laid out while a Counter runs. The home screen's thumbnails keep open only the current project's videos.",
        ], misc: [
            "The anchor picker beside rotation has no outline, just its nine points, with a little less room around them.",
            "Double-clicking a row or a bar in the timeline no longer renames the action. It selects it, as one click does.",
            "The Keyboard Shortcuts card lists Duplicate project, full screen and Command-click to add or take away an action in the timeline.",
        ]),
        .init(date: "28 September 2026", title: "Presets, text and easing", features: [
            "Presets you can see. In Animate, a selected layer shows two tiles, New Action and Select Preset. Select Preset opens every preset as a tile that plays it on a small square, so you can see what each does before picking it. Picking one adds it at the playhead and shows its settings.",
            "Presets in pairs. Fade, Slide, Scale, Rotate, Blur, Drop and Sound Fade are each one preset, with In and Out in its settings; their tiles play the way in, then the way out. New: Rotate Out and Drop Out. Turning a preset from In to Out renames its bar and gives it the Out version's length and easing, unless you changed them.",
            "The preset picker is in groups: Fade, Scale, Mask, Blur, Emphasis, Text and Sound. With text selected, the Text presets show first.",
            "New presets: Shrink, Twist, Move & Scale, Blur & Slide, Blur & Scale, and five Mask presets that reveal the layer inside its own box: Mask Reveal, Mask Center, Mask Resize, Mask & Slide and Mask Shrink. Scale is now called Grow and Rotate is Spin.",
            "On a text, any preset can move its letters, words or lines one by one: Apply to, Order (forward, backward, from the centre, from the edges or random) and Delay are in its settings. New text presets: Typewriter, Letters Rise, Letters Pop, Words Blur and Lines Reveal.",
            "A preset's From and To show arrows instead of Left, Right, Top and Bottom.",
            "The easing card. Easing is picked from a card of tiles beside the inspector, each showing its curve; under the pointer, a tile plays a small box moving with that easing. Picking a tile keeps the card open, and clicking the picked tile again shows its graph and an Intensity slider. Custom opens its graph straight away, with both handles to drag and its four numbers to type.",
            "New easings: Natural, Bounce, Impulse and Swing. Spring is now called Elastic, and the even-speed easing is called Linear rather than None. Every easing is the designer's own curve at the standard intensity of 50.",
            "Text in Fill and Stroke. The Text section is laid out afresh: the font, then weight and size, then left, centre and right alignment beside Auto or Fixed, with letter spacing and line height behind its settings button. Justify is no longer offered. A text's colour is its Fill, which can be hidden, and a text can have a Stroke round its letters: centred, inside or outside, with its corners in the stroke's settings. Words are typed on the canvas; the inspector no longer has a box for them.",
            "Show and Hide always count. A Show or Hide is kept whatever presets or other actions come before or after it. A layer shown before an In preset stays as designed until the preset starts, then plays it. A Show after a fade out brings the layer back to its opacity, and an In preset after a Hide shows the layer again as it plays. A Show hides nothing before it: to make a layer appear later, put a Hide at the start or use an In preset.",
            "Shift-click on the timeline selects every action between the last one you clicked and this one. With several actions selected, dragging the end of one of them lengthens or shortens them all by the same time.",
            "An action's settings end with New Action and Select Preset, two small buttons one over the other, so you can add another to the same layer straight away.",
            "Undo keeps the last 200 steps, and on very large projects drops the oldest sooner so it never takes more than about 512 MB.",
            "WebM videos can be imported, converted with the ffmpeg installed on this Mac. Transparency is kept.",
        ], fixes: [
            "Portrait videos from a phone no longer come in upside down.",
            "Exported sound never clips: loud clips that overlap are held just under full volume, and quieter sound is left exactly as it was. Every sound track in a file is heard, not only the first, and an export stops with a clear message naming any sound it cannot read, instead of making a movie without it.",
            "Pictures, videos and waveforms that no layer uses any more are let go from memory a second after you stop editing, so deleting a big picture gives its memory back. Undo brings it back from the project. Saving no longer reads every picture again to draw the project's thumbnail.",
            "Words typed on the canvas are kept when you go Home, open another project, close the window or quit before you finish typing. They were lost before.",
            "An SVG that refers to itself, nests or repeats past what any drawing needs, or holds numbers too large to draw is refused or read safely, rather than crashing Twine. An SVG can no longer pull a file from the Mac, or a web address, into the drawing.",
            "A Figma paste with extreme values reads safely too: stars and polygons keep at most 60 points, and anything placed impossibly far away is left out.",
            "Text presets set to letters, words or lines no longer drag slivers of the lines above and below along with each piece, which made text look doubled and glitchy. Letters that reach past their own box, such as an f or an italic's tail, are no longer cut off while they move.",
            "Pasting from Figma into an empty project no longer resizes the composition to fit. The copy comes in centred at its exact size, and the composition stays as you set it.",
            "On the timeline, a long layer name is cut short so the action's or preset's name always shows beside it.",
        ], misc: [
            "Every kind of action in the New Action menu, and every effect in the Effects section's add menu, shows its icon beside its name.",
            "The export's percentage moves the way a Counter with the Slide transition does: each number rises and fades away as the next rises in from below. It is set in PP Kyoto Thin.",
            "On the timeline a Show is drawn as a dot and a Hide as a square. The play controls are smaller and further apart, turn white under the pointer, and Loop shows it is on in grey rather than blue.",
            "Waveforms show every sound track in a file.",
            "Clicking a hex field selects its digits, so typing or pasting replaces them straight away. A short hex code fills out the rest: 0 becomes 000000, 1a becomes 1A1A1A and abc becomes AABBCC.",
            "An empty section, such as Stroke, Effects or Mask with nothing added, has its name centred between its lines. The last section in the layer inspector has a line under it too.",
            "Add Action and Add Preset no longer grey out when a sound is selected along with other layers: they offer what the other layers share, each gets its own bar at the playhead, and the sound is left as it is.",
        ]),
        .init(date: "28 September 2026", title: "A new inspector", features: [
            "The layer inspector is in sections: Position (alignment, X and Y, rotation and the anchor), Layout (width and height with the proportions link between them, scale, corners and Clip content) and Appearance (blend mode and opacity side by side). Several selected layers can share a blend mode as well as an opacity.",
            "Position like Figma: the alignment buttons sit in two trays, left to right and top to bottom, and distributing is in a menu from the button beside them. Scale always shows both ways, SX and SY, with its own link between them.",
            "The link between width and height is its own setting, off for new layers: when on, typing one changes the other, and resizing on the canvas keeps the proportions too.",
            "Drag across any number field to change it, as in Figma: positions, sizes, scale, corner radius, angles, percentages, an action's From, To and By, and the rest. Shift moves ten times as fast, Option a tenth as fast, and each drag undoes in one step. A click still lets you type, with the number selected.",
            "An action's From, To and By have their names above the fields, so the fields take the whole width and long numbers show in full. To or By is chosen from a small menu on the row's name.",
            "A curved Move can Rotate along path, turning the layer as the path turns, from its own angle.",
            "The anchor is picked from nine points, the corners, the middles of the edges and the centre, beside rotation.",
            "A selected shape shows its own outline in blue on the canvas, so you can see its shape even when it is blurred or faded.",
            "Stroke shows its alignment as a menu with the width beside it; trim, ends, corners and dashes are in a card from the settings button next to them. Skew and Tilt moved into Effects, added from its + menu, and every effect shows an icon for what it is.",
            "The inspector's grid. Every row stops at the same edge, with a column at the right for the button that acts on that row: the links, the corners button, show and hide, the stroke's settings, distribute, and in Animate the links and the button that empties a starting value. Section headers only add or remove. An ellipse's start, sweep and inner ratio are one joined field, as in Figma, with the sweep as a share of a full turn.",
            "The field you are typing in has a thin blue outline, and units such as px, % and ° sit fixed at the end of each field.",
            "New icons. Every icon in the app is the designer's own: the tools, the layers panel, the inspector, the effects, presets and the timeline's playback buttons. The fields for each corner's radius show a drawing of their corner instead of TL, TR, BL and BR.",
        ], misc: [
            "A quieter inspector: it no longer uses blue. The chosen tab in a row of choices is a lighter grey, switches that are on sit in the same grey, and the easing curve is drawn in white. Blue is kept for the selection on the canvas, the layers panel and the Export button.",
            "Icon lines are drawn at 1.6 points on the tools and playback buttons, and in the same proportion at every other size.",
            "Every button at the right of the inspector lines up with the sections' add and remove buttons, and the fields grew a little to keep the same gap before them.",
        ]),
        .init(date: "28 September 2026", title: "One bar per preset, skew and tilt", features: [
            "One bar per preset. A preset goes on as one bar in the timeline, as in Jitter. Click it to set everything it offers in the inspector: its timing and easing, and settings such as where a slide comes from, how far it travels, how big a pop starts and whether it fades. Dragging a preset bar's ends stretches the whole preset, fades and all.",
            "Slide In and Slide Out are one preset each, with a From or To choice of left, right, top or bottom.",
            "Right-click a preset bar in the timeline and choose Split into Actions to edit its parts one by one. Presets added before this stay as separate actions.",
            "New Skew and Tilt actions: Skew slants a layer each way, and Tilt turns it in depth, back and forth or side to side, seen in perspective, with a Depth setting for how strong the perspective looks. Half a turn shows its back.",
            "Layers can be designed skewed or tilted too: Skew and Tilt fields under rotation, which the actions animate from. Skewed and tilted layers export exactly as they show, their outline on the canvas follows their shape, and clicks land on what is drawn. A tilted layer shows no resize handles; set its size in the inspector.",
            "Magnetic timeline. Moving or trimming a bar lines it up softly with the start or end of bars on the rows you can see, the playhead and the scene's start and end. A guide line shows what it lined up with, the trackpad gives a small bump as it catches, and it holds gently until pulled a little further. Hold ⌘ to move a bar freely; the canvas's Snapping switch turns timeline snapping off too.",
            "Right-click (or Control-click) a layer on the canvas for the same menu as the layers panel: rename, duplicate, group, frame, ungroup, solo, lock, hide and delete. Right-click empty canvas to paste. Escape closes the menu.",
            "⌘⌫ ungroups groups and frames, as in Figma, alongside ⇧⌘G. It no longer deletes the selection.",
            "A sound or video and its Play bar go together: deleting the last Play bar in the timeline deletes the layer too, and a project with a sound or video missing its bar gets one back when it opens.",
            "Figma pastes. Layers skewed in Figma paste in as editable Twine layers, slanted exactly as in Figma, instead of pictures: shapes, frames with everything inside them, vectors and text.",
            "A Figma frame whose background is a picture pastes in with the picture as its own layer, Background, at the bottom of the frame, so it shows in the layers panel and can be selected, replaced and animated. Pictures stacked on one layer in Figma come in as the top one only, which keeps copies and projects smaller.",
            "The Fill section shows and edits a layer's top fill, the one you see, and the Colour action changes that one too.",
            "The Figma plugin looks like Twine: a dark panel with a picture of what is selected, its size and how many layers it holds, and a blue Copy button. While it copies, the percentage and a progress bar show in the preview, and a check shows in its corner once copied.",
            "The old name is gone: the projects folder is now Twine Creations in Documents, moved there with everything in it the first time this build opens, and settings carry over. Projects ending in .emotion are no longer opened; none were left.",
        ], fixes: [
            "The Figma plugin's percentage no longer steps back while it copies pictures.",
        ], misc: [
            "Playback works out each frame about a tenth faster.",
        ]),
        .init(date: "27 September 2026", title: "Ready for Figma", features: [
            "Pictures are fills, as in Figma: an imported picture is a rectangle filled with it, so it can have rounded corners, a stroke and shadows, and any shape can be filled with a picture by choosing Image under Fill. Pictures in older projects become picture-filled rectangles when opened, looking just as they did, with their actions and masks kept.",
            "Choose how the picture fills its shape: Fill covers it, Fit shows the whole picture, Crop places it by hand, and Tile repeats it at a scale. The turn button beside the choice turns it a quarter at a time, and a picture has its own opacity.",
            "Double-click a picture, or choose Crop, to crop it on the canvas: the rest of the picture shows faintly, drag it to move it, drag its corners to scale it, and drag the layer's handles to show more or less of it. Escape or a click away finishes.",
            "Replace, under the picture in Design, swaps in another picture and keeps the layer, its size and every action on it. Videos have Replace too, and a Fill or Fit choice for a clip of another shape; a play that would run past a shorter clip's end starts earlier in it.",
            "Frames, as in Figma: the Frame tool (F) draws a white frame that clips what spills over its edges, and takes in the layers it is drawn around. Arrange > Frame Selection (⌥⌘G) puts the selection in a frame.",
            "A frame has its own fill, stroke, corner radius, shadows and blurs, with its fill behind what it holds and its stroke in front. It clips to its rounded corners, and resizing it changes its size rather than stretching what is inside. Shapes, frames and text drawn inside a frame go into it, and frames take Colour, Stroke, Corner Radius and Resize actions, like rectangles.",
            "Double-clicking goes one level into a group or frame at a time, and once inside, clicks and drags stay at that level. Dragging layers into or out of a group or frame in the layers panel keeps them where they are on the canvas, with their actions.",
            "Every layer has a blend mode, under Opacity in Design: Figma's full list, from Multiply and Screen to Overlay, Difference and Luminosity. A group or frame left at Normal lets what is inside it blend through, as Figma's Pass Through does.",
            "Inner shadows, from the Effects menu on shapes and frames: a shadow cast inward from the edge, with its offset, blur, spread and colour.",
            "Shapes and frames draw every drop shadow they have, not only the first, as Figma cards often stack two. Their shadows never show through a see-through fill, and are as faint as the fill is, as in Figma.",
            "SVG import. Import an SVG file (File > Import, or drop it on the canvas) and it comes in as layers you can edit, in a frame named after the file: shapes, groups, colours, gradients, strokes, clip paths and masks, pictures inside it, and holes in shapes. Rectangles and circles stay rectangles and ellipses where they can; other outlines become paths whose points can be edited.",
            "Figma's exported shadows and blurs come in as Twine's own effects. Text, and anything else Twine cannot edit, comes in as a sharp picture of itself, in its place. An SVG larger than the composition is shrunk to fit.",
            "Paste from Figma. A Twine plugin for Figma (in the FigmaPlugin folder): select a frame or layers, press Copy, then paste in Twine with ⌘V. Frames, groups, shapes, vectors, pictures, gradients, strokes, shadows, blurs, blend modes and masks come in as editable Twine layers; text in one style comes in as Twine text, and anything Twine cannot hold comes in as a sharp picture Figma drew. It comes in centred at its exact size.",
            "A note over the canvas says which fonts are not installed (a stand-in shows until they are) and what had to be left out.",
        ], fixes: [
            "Sound no longer stutters as playback starts: it starts exactly with the playhead instead of catching up in little jumps. Sound comes back on the next loop when it ran out before the end of the scene, and no longer jumps on every frame after it ends.",
            "A group that clips keeps its shadow, and grouping a layer that masks another keeps the mask.",
        ], misc: [
            "A selected layer shows only its box and handles, and the outline under the pointer is just a line, with no light wash over the layer.",
            "Exported frames are about a fifth quicker to draw.",
        ]),
        .init(date: "27 September 2026", title: "Twine", features: [
            "The app is now called Twine, with a new icon: in the Dock, in Finder, in the menus and on the home screen. New projects end in .twine, shown in Finder as Twine projects.",
            "Twine is one window. Opening a project turns the home screen into the editor, and the Home button (or ⇧⌘H) saves the project and turns it back, with a short fade either way. One project is open at a time: opening another, from the home screen or the Finder, saves the first and takes its place. Closing the window quits Twine.",
            "Folders on the home screen, down the left under All Projects. + makes one and names it; right-click a folder to rename it, show it in Finder or move it to the Trash with its projects. Drag a project card onto a folder to put it in, or onto All Projects to take it out, or right-click a card and choose a folder under Move to. Folders are real folders inside the projects folder, so the Finder shows the same.",
            "The home screen looks like re-Flip's: plain rows down the sidebar, and a dim New Folder row under the folders, which you click and type the new folder's name into. Project cards have a bigger thumbnail, keeping the picture's own shape with nothing filling its sides, sit on the background until the pointer is over them, and show the date without the time.",
        ], misc: [
            "Projects kept their old ending and folder for this build, so everything made so far opened as before, and every setting was kept.",
        ]),
        .init(date: "27 September 2026", title: "Pen, volume and the export panel", features: [
            "The Pen (P) is back in the toolbar. Click to place points, drag to pull out curve handles, and click the first point to close the shape; Escape or Return leaves it open, as a line. The pointer shows when a click will add a point to a line, move a point, or join onto an end.",
            "Double-click a shape, or press Return, to edit its points as in Figma: pick them by clicking or with a box, drag points, handles or segments, ⌘-click to make a point sharp or smooth, ⌘-drag to pull out handles, Option-drag to move one handle alone, and Delete to take points out. Rectangles, ellipses, lines, polygons and stars turn into paths when their points change. Resizing a path stretches it, in Design and with a Resize action.",
            "A new Path action, under Shape in Animate, morphs a path into a new shape: select it and drag the end shape's points on the canvas.",
            "A new Volume action, under Media in Animate, fades a video's or a sound's level to anywhere from 0% to 100%, following its easing. It is heard as the timeline plays and in exported movies. Add Preset has Fade Sound In and Fade Sound Out, each a second long, and a Play bar's waveform tapers where the sound fades.",
            "A new export panel. Export is a blue button at the foot of the right panel, in Design and Animate. It opens a panel over the whole window: the settings on the left, and on the right a preview of exactly what will be exported, which plays with its sound (Space plays and pauses).",
            "Choose the size (50%, 100%, 200% or any percentage, such as 150% or 33.3%, up to 4K), the format, a frame rate for the movie (the composition's own, or 24, 25, 30, 50 or 60 fps), the range, and whether to include sound. Quality is always High.",
            "Exporting sends the preview up and out and brings a big percentage counter up from below, its digits stepping up once as they change. When it finishes they trade places back, and the button offers Export again, with Show in Finder under it. Cancel stops an export part way, as do the cross and Escape, which close the panel. Nothing half-written is left behind.",
        ], misc: [
            "Exports never go past 4K (3840 × 2160, either way round): a size that would is greyed out in the menu, and a larger composition exports at 4K. Movies still round to even numbers of pixels.",
            "Volume, the sound presets and the Sound section in Design only appear for sounds and for video that has a sound track. The Volume slider in Design stops at 100%, the file's own level, as the Volume action does.",
            "The export panel's settings column is as wide as the layers panel, so its edge lines up with it.",
        ]),
        .init(date: "26 September 2026", title: "Masks, snapping and presets", features: [
            "Masks. Any layer can be masked by another: press + under Mask in the inspector and pick the mask. The layer shows only where the mask draws, and the mask itself stops drawing. Invert shows it everywhere else. Shapes, text, pictures and video can all be masks, and a group can be masked by a layer inside it. Masks animate, and it all carries through to export.",
            "A mask shows its own icon in the layers panel. Select it there to move it on the canvas. Clicks on the canvas only pick what a mask lets show.",
            "Smart guides and alignment. Moving, resizing and drawing snap to the composition's edges and centre and to other layers' edges and centres, with red guides showing what lined up. Moving also snaps to even spacing, and the equal gaps show with their size. Hold ⌘ while dragging to place freely; View > Smart Guides turns snapping off.",
            "Align and distribute from the new Arrange menu, the buttons across the top of the inspector, or Figma's keys: ⌥A, ⌥H, ⌥D, ⌥W, ⌥V, ⌥S, and ⌃⌥H and ⌃⌥V to space three or more layers evenly. One layer aligns with the composition; several with each other.",
            "A new timeline. Labels down the left name each row's layer and action, with the play controls above them. Rows run in the order actions were added, and a new action goes to the bottom. Drag a row's label, or its bar, up or down to put it anywhere. The playhead is teal, with the time in a pill on the ruler, and a selected action lights up its whole row.",
            "Hovering a bar shows a handle at each end; grab one to change when the action starts or ends. A label lights up under the pointer and shows its eye, which switches the action off; an action switched off shows as a dimmed label and bar. Right-click the timeline for Stagger, Show Only Selected Layers and Show Times as Frames.",
            "A click on the ruler or on empty timeline slides the playhead to that point in a fifth of a second, rather than jumping. Dragging still scrubs directly. Adding an action plays it: the playhead runs from its start to its end and waits there, so the next action you add follows on.",
            "Presets. Add Preset, under Add Action in Animate, applies a ready-made animation at the playhead: entrances (fade, slide in from each side, scale pop, rotate in, blur in, drop in), exits (fade, slide out to each side, scale out, blur out) and emphasis (pulse, bounce, shake, wiggle). A preset only adds ordinary actions, on new rows, so every part of it can be retimed, re-eased or deleted like any other action.",
            "Hover and pointers. Hovering a layer on the canvas outlines it and lights up its row in the layers panel; hovering a row outlines its layer on the canvas. New pointers: an arrow and a crosshair for the canvas, resize arrows that follow a turned layer's handles, turn arrows that curl round each corner, and resize arrows on the timeline's bar ends, the scene's end and the timeline's top edge. Twine's own arrow is the pointer everywhere in the app.",
            "Hold Space in Design and drag to pan the canvas, with a hand pointer; the middle mouse button pans too. The playhead's pill is a handle: the open hand over it, the closed hand while it is held.",
            "In Design, hold Option and drag a layer to leave it where it is and drag away a copy, animation included, as in Figma. One Undo takes it back, and an Option-click that never moves makes no copy.",
            "Export > Range exports the whole scene or only part of it: choose Part of the scene and type where it starts and ends. The movie starts at the From time, and its sound comes with it, in step.",
            "Help > Keyboard Shortcuts (⌘/) shows every Twine shortcut on one card, grouped by where it works. Escape, ⌘/ or a click outside closes it.",
        ], fixes: [
            "Hover failed over the upper part of the canvas, worst in Animate, where a layer near the top did not respond and a tall one only answered over its lower half. The check for whether the pointer was over a panel looked at the spot mirrored top to bottom. The same mix-up could end typing in a text field when clicking inside it.",
            "When a new action's row lands below what the timeline shows, the timeline scrolls down to it, so you always see what you added.",
            "The timeline's top edge shows the up-and-down arrows, and the scene's end on the ruler the sideways arrows, reliably now: the window's SwiftUI had been putting its arrow back over them.",
        ], misc: [
            "Measured on a scene of 200 layers and 990 actions: dragging a layer is about twice as quick (15 to 7 milliseconds a step), dragging a timeline bar a fifth quicker, and scrubbing about a third quicker. Playback holds 60 frames a second. Working out a frame takes less than half as long as before.",
            "The timeline's label column is as wide as the layers panel. It stops at 0s, and the ruler labels whole seconds only, with dots between.",
        ]),
        .init(date: "26 September 2026", title: "Text, media and export", features: [
            "Text layers. Pick the Text tool (T) and click: a text layer appears ready to type over. The Text section sets the font (a searchable list of every font on this Mac, each shown in itself), weight, size, colour, alignment, letter spacing, line height, and auto or fixed width. A font this Mac does not have shows crossed out, and the text draws in SF Pro.",
            "Type straight onto the canvas: double-click a text layer to type where you clicked, or press Return with one selected to edit all of it. The caret and selection sit exactly on the letters, at any zoom and on turned text. Every Mac typing habit works, including accents by holding a key and input methods for other languages. A text left empty is removed.",
            "Text actions: Letter Spacing, Line Height, Counter and Change Text. Counter counts in the text's own style: \"$1,200.50\" counts in dollars and cents, \"007\" keeps its zeros, and it can snap, fade or slide from number to number. Change Text swaps the words with a transition out and in.",
            "Ellipses gain Start, Sweep and Ratio in Design, for pie slices and rings, and an Arc action. Stars gain a corner radius, and a Star action for points, inner radius and corners.",
            "Seven new actions under Style and Blur in Add Action: Colour, Stroke, Trim, Corner Radius, Shadow, Layer Blur and Background Blur. Each is offered only where it applies. Colour changes the first fill, to a colour or a linear or radial gradient, blending colours, stops and direction even between different numbers of stops.",
            "Design mode gains Background Blur (frosted glass, with a blend) under Effects, and Spread for drop shadows. Trim on strokes lets a line draw itself on.",
            "Import pictures, video and sound with File > Import… (⌘I), or drop them on the canvas. Each becomes a layer; the file is copied into the project, so moving or deleting the original does no harm.",
            "Video and sound get a Play bar on the timeline. Drag it to set when it plays, and drag its ends to trim the clip. Sound plays with the timeline and shows its waveform in its Play bar. Volume and mute are in Design, under Sound.",
            "Export movies: MP4 in H.264 or HEVC, or MOV in HEVC with transparency, ProRes 422 or ProRes 4444. Or save the current frame as a PNG. Export… (⌘E) asks where to save; Export Current Frame… (Shift-⌘E) saves a PNG of what the canvas shows. Exports run in the background with a progress bar and a cancel button, and Show in Finder takes you to the file.",
            "Exports include the sound (switch it off under Export > Audio) and every video frame exactly as it falls on the timeline. A transparent background stays transparent in HEVC with transparency, ProRes 4444 and PNG.",
            "Copy Easing and Paste Easing (Option-Command-C and V, in the Edit menu) give one action's easing to others.",
        ], fixes: [
            "Blurs are centred where they belong. They used to sit about 9 px off, down and to the left, on the canvas and in exports alike. Blur amounts follow Figma's measure, so existing blurs and shadows look about half as soft as before.",
        ], misc: [
            "Text boxes grow the way their alignment reads: left-aligned text to the right, centred both ways, right-aligned to the left.",
            "Every frame of an export is drawn by the same renderer as the canvas, so an export matches what you see and is the same every time. A cancelled export never leaves half a file or replaces the old one.",
            "The timeline stays quick with thousands of actions.",
            "Add Action's menu is grouped under Transform, Style and Blur.",
        ]),
        .init(date: "26 September 2026", title: "Actions", features: [
            "Animation works like Jitter underneath: a layer's properties are how it is designed, and actions (move, scale, rotate, opacity, resize, hide and show) change them over time. Keyframes, stopwatches and layer in and out bars are gone.",
            "Press M to switch modes. Design shows the layout as designed, with no animation, and only design settings. Animate shows the moment at the playhead and never shows design settings.",
            "In Animate, select a layer and use Add Action to add a move, scale, rotate, opacity, resize or hide/show at the playhead, half a second long. The canvas only selects and moves there: dragging a layer moves where it is designed, and its animation comes with it.",
            "The action timeline runs the full width of the window in Animate, with one row per action under a divider for its layer. Drag a bar to move it in time or reorder it, and drag an end to change its length. Bars snap to the playhead, the scene's ends and other actions.",
            "Click, Shift-click, Command-click or drag a box to select. Delete, copy, paste at the playhead onto the selected layers, and duplicate. Arrow keys move selected actions a frame, Shift ten. Stagger spaces selected actions by a gap you choose.",
            "Comma and full stop step a frame. Drag the end marker on the ruler to change the scene's length. The filter in the timeline's header shows only the selected layers' actions.",
            "Select an action and the inspector shows only its fields: start and length, easing, To or By, where it starts and where it ends. Several actions of one kind edit together. Easing: None, Smooth, Slow down, Accelerate, Overshoot and Spring, each with an intensity, or a Custom curve with handles to drag.",
            "A starting value can be left empty, and then it starts from wherever the layer is; the greyed number shows what that will be. Switching between To and By keeps the motion as it was.",
            "A selected Move shows its path on the canvas. Drag the layer or the end dot to set where it ends, turn on Curved path and drag its handles to bend it, and drag the start dot (with Command, over the layer) to set where it starts. A selected Resize, Scale or Rotate shows the layer as it will be at its end, with handles to drag.",
        ], fixes: [
            "Moving a layer's design position carries all of its moves along, To moves included.",
            "Clicking anywhere in a number box starts typing, not just on the number. After a click in the timeline, Delete only removes actions.",
        ], misc: [
            "Duplicating, pasting, grouping and ungrouping keep each layer's actions with it.",
            "Projects from earlier builds show a plain message and no longer open.",
            "Playback is for Animate; Space does nothing in Design.",
        ]),
        .init(date: "25 September 2026", title: "Keyframes and playback", features: [
            "Animate mode's timeline: a row per layer, with its bar from in point to out point, and its animated properties underneath when opened. Keyframes on the timeline can be selected, moved, deleted, copied, pasted at the playhead and duplicated, snapping to the playhead, other keyframes and the ends of layers.",
            "A stopwatch beside every property in the inspector keys the value at the playhead; after that, any change in Animate mode keys it there too. In Design mode a change moves the whole animation instead.",
            "Easing for the selected keyframes: linear, hold, twelve presets, a custom curve with handles to drag, or a spring with its stiffness, damping and mass.",
            "Playback in real time. Space plays and pauses, [ and ] step a frame, Home and End go to the ends, and it loops unless you switch that off. Click or drag the ruler to scrub, and click the time to read it in frames.",
            "Trim start and end on strokes, so a line can draw itself on.",
            "The app's own colour picker, drawn on the panel card like Flip's, in place of the system colour panel.",
        ], fixes: [
            "A number typed into a field and confirmed with Return no longer goes back to the old value when you click somewhere else. The same for hex colours.",
            "The Easing menu is greyed out when only a property's last keyframe is selected, since there is no next keyframe to ease to. Menus open on every click.",
        ], misc: [
            "Keyframes were replaced by actions in the next build.",
        ]),
        .init(date: "25 September 2026", title: "The foundation", features: [
            "A home screen of every project in Twine Creations, newest first, with open, rename, duplicate, show in Finder and move to Trash. Cards show each project's first frame.",
            "New projects are written to disk the moment they are made and save themselves from then on. Closing a window never asks a question, and File > Revert To browses older versions. The project file is a package: document.json with a format version, and a media folder for imported files.",
            "Every change goes through one set of commands, so every change can be undone. A drag or a colour pick undoes as one step.",
            "The editor's shell: the canvas full-bleed, the layers panel and the inspector floating over it, and the Design and Animate switch at the head of the inspector. Composition settings: size, frame rate (including 23.976, 29.97, 59.94 and custom rates), duration, and a background colour or transparency.",
            "Drawing on the canvas: rectangle, ellipse, line, polygon and star, drawn by dragging (Shift for a square, a circle or a 45 degree line, Option from the centre). Select by clicking, Shift-click or a marquee; drag to move; eight handles resize; just outside a corner turns the layer; Command-drag the anchor marker to move the anchor.",
            "The canvas draws with the real renderer: pinch or Command-scroll to zoom, scroll to pan, Command-0 to fit. The layers panel lists the tree front to back, with groups that fold, hide, lock and solo on each row, a right-click menu, renaming, and drag to restack or drop into a group.",
            "The inspector edits the selected layer: position, size, rotation, scale, anchor and opacity; corner radius, sides and points; a solid or gradient fill; a stroke with its width, alignment, caps, joins and dashes; drop shadows and blur.",
            "Every property can be worked out at any moment of the animation, between frames included. Colours blend through a perceptual colour space, so red to blue passes through purple rather than grey. The renderer that draws the canvas also draws off screen, which is how exports draw.",
            "Flip's design system, with a light blue accent, from the Figma file: its colours, type, metrics, grain and controls.",
        ], fixes: [
            "The Design and Animate switch, the Composition header and the tools answer clicks again. The inspector's list had been stretching up under the title bar and catching clicks meant for the controls above it.",
            "Nothing takes the keyboard when a window opens, so typing no longer goes into the composition's width. Clicking anywhere outside a text field ends the edit and keeps what was typed.",
            "The traffic lights stay in the left panel's corner without the loop that crashed the app when a project opened in the background. Section headers are real buttons, so a click anywhere on the row folds them.",
        ], misc: [
            "The pen and text tools are shown but switched off until their builds.",
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
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Version History")
                            .font(ThemeFont.labelStrong)
                            .foregroundStyle(Theme.textPrimary)
                        Text(VersionHistory.release)
                            .font(ThemeFont.caption)
                            .foregroundStyle(Theme.textTertiary.opacity(0.6))
                    }
                    Spacer(minLength: 0)
                    IconButton(icon: .close, help: "Close (Esc)", action: dismiss)
                }
                .padding(.leading, pad)
                .padding(.trailing, Theme.sheetCloseInset)
                .frame(height: Theme.sheetHeader)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: Theme.hairline) }

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.readingBlockGap) {
                        ForEach(VersionHistory.builds) { build in
                            VStack(alignment: .leading, spacing: Theme.readingTitleGap) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(build.title)
                                        .displayTitle(20)
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer(minLength: 0)
                                    Text("Build \(VersionHistory.number(of: build)) · \(build.date)")
                                        .font(ThemeFont.caption)
                                        .foregroundStyle(Theme.textTertiary)
                                }
                                VStack(alignment: .leading, spacing: Theme.readingSectionGap) {
                                    ForEach(build.sections, id: \.heading) { section in
                                        VStack(alignment: .leading, spacing: Theme.readingItemGap) {
                                            Text(section.heading)
                                                .font(ThemeFont.labelStrong)
                                                .foregroundStyle(Theme.textPrimary)
                                            ForEach(section.items, id: \.self) { change in
                                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                    Circle().fill(Theme.textTertiary).frame(width: 3, height: 3)
                                                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 }
                                                    Text(change)
                                                        .font(ThemeFont.label)
                                                        .lineSpacing(Theme.readingLineSpacing)
                                                        .foregroundStyle(Theme.textSecondary)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                }
                                            }
                                        }
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
