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
    static let pushes = 206

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
        .init(date: "1 October 2026", title: "Large projects", features: [
            "Gradients take as many colour stops as you like, as in Figma. The Fill section shows the gradient as a bar with a marker for each stop: click the bar to add a stop in the colour already there, drag a marker to move it, and type its place beside the bar. Each stop has its own row with its colour, hex and opacity, and a button to remove it. Colour and Stroke actions edit their gradients the same way.",
            "Gradient handles on the canvas. Select a layer with a gradient in Design and its line shows on the layer, over its own handles: drag its ends to turn and stretch it (Shift keeps it to steps of 15°), drag the line to move it, drag a stop's dot to slide the stop, and click the line to add a stop there. Delete removes the picked stop; Escape hides the line until you select again. A radial or angular gradient shows its circle, with a handle at its centre and one on its edge.",
            "Angular gradients, as in Figma: a fill or a Colour action can be Angular, its colours going a whole turn clockwise round its centre, starting where its edge handle points.",
            "Masks work as in Figma. Select layers and choose Use as Mask from the right-click menu (or ⌃⌘M): they go into a Mask group, the one at the back becoming the mask, and the layers in front of it show only where it draws. With one layer, it becomes a mask where it is. A mask's inspector has a Mask section whose button removes it. Masks in projects made before this become mask groups when the project opens; an inverted mask is no longer inverted, as Figma has no such mask.",
            "Angular gradients copied from Figma with the Twine plugin come in as Twine's own angular gradients, which you can edit, rather than as pictures.",
            "Moving dashes: a Dashes action sets a dashed or dotted stroke's dashes travelling along the line, at a speed you set and either way, from the playhead to the end of the scene unless you shorten its bar (Linear keeps the flow steady). Follow trim makes them travel the way the trim draws the line, each part towards its growing end.",
            "Trim works by direction now: Start to End, End to Start, Both Ends to Middle or Middle to Both Ends, and how much of the line is drawn, in the stroke's settings and in the Trim action (From and To amounts), in place of the start and end numbers. Older projects keep their trims, read as the nearest of these.",
            "Dotted lines: a stroke's Style is Solid, Dashed or Dotted. Dots are round, the Gap the clear space between them.",
            "Info on a project's right-click menu on the home screen: a card with when it was made and last saved, its size on disk and folder, the composition's size, length and frame rate, how many layers it has of each kind, and how many actions, presets and scenes are on its timeline, with where the last action ends. An open project's card counts its unsaved changes too.",
            "Settings, at the foot of the home screen's sidebar where Version History was (which is now a button at the foot of Settings, beside the build number). Each kind of setting is a card of rows, each with its icon, laid out in three columns when the window has room and two when it is narrower. Change where projects are kept; what a new project starts with (its size, from Landscape, Portrait, Square or 4K or typed, frame rate, length and background); how far the arrow keys nudge, with and without Shift; the easing and length a new action takes; whether times show as frames; whether sound plays while editing; and whether exports ask where to go or go straight into a folder, and are shown in the Finder when done. Each change is kept at once.",
            "Show Sound at the Bottom, on the timeline's right-click menu beside Show Times as Frames: every sound layer's rows move to the foot of the timeline, under everything that draws, keeping their own order, so new actions on other layers go above them. Rows in a scene stay with their scene. While it is on, dragging a row reorders it only among its own kind. Twine remembers the choice.",
            "Page Curl, a new preset in a new Flip group: the layer curls away from a corner like a page of Apple Books, as the pictures turn in Flip's onboarding, showing what is under it, with the back of the page in a lighter shade of the layer's colour and a shadow travelling with the fold. Out curls it off, In lays it down; pick the corner it lifts from in its settings. Half a second, eased in and out as Flip's is, and the same on the canvas and in exports.",
            "Page Turn, beside it in the Flip group: the layer swings on one edge like a page on its spine, the free edge lifting towards you until it is edge-on (Out), or coming down from the far side (In), as the onboarding's pages do. Pick the edge it hinges on in its settings.",
            "A card saying \"Opening\" with the project's name, and a turning ring, shows in the middle of the window while a large project opens, however it is opened (the home screen, the Finder, Open Recent). It keeps turning while Twine builds the editor, and appears only when opening takes longer than a moment, so small projects show nothing.",
            "A deeper blue (#217FD8, from #4C9FEF) for everything that marks what is selected or in hand: the selection on the canvas, selected rows, the tool in hand, the main buttons, and the Figma plugin's panel.",
            "The onboarding's first page shows a looping video of Twine at work in place of its placeholder. The folder page has its own video, of the folder with your chosen folder's name under it: a second after the page turns over, papers go into the folder, and it stays on its last frame. Choosing a different folder plays it again.",
            "Animate is Twine's main mode: a project opens in it, and it is now the left of the switch at the top of the inspector, with Design on the right. The View menu lists them in the same order.",
            "Every row of tabs glides as the tool bar does: the mode switch, a fill's Solid, Linear, Radial and Image, a stroke's Style, Caps and Joins, a preset's direction, corner and In or Out, and the rest. A highlight slides from option to option under the pointer, and the chosen grey slides across to the one you pick.",
            "Paste pictures straight from the clipboard. A screenshot copied with ⌃⇧⌘4, a picture copied in a browser, or a layer copied as PNG in Figma comes in with ⌘V as a picture layer, as if it were imported; the same picture pasted twice is stored once. Files copied in the Finder paste too: pictures, video, sound and SVG drawings come in as they would from File > Import.",
            "The home screen's window no longer grows with every folder. When there are more folders than fit, the sidebar's list scrolls, with a divider and Settings always at its foot, and the window keeps whatever size you give it.",
            "The window can no longer be made too small to work in: its smallest is now 1200 by 760, on the home screen and in a project alike. It could be dragged to half the width, squashing the panels and the timeline; a window left smaller than that grows to it.",
            "Resize from anywhere along a side, as in Figma: press on a selected layer's edge, not only its middle handle, and drag it out or in. The pointer shows which way it goes. A layer too thin to grab inside still moves when dragged.",
            "Gradient handles take the designer's all-direction pointer: over a gradient's ends, its oval handle, its stops and its line, and while dragging them.",
            "A new app icon, the designer's.",
            "Draw and shape things in Animate too. The tool keys work there (R, O, L, Y, S for shapes, F for a frame, P for the pen, T for text; there is no tool bar in Animate, so Escape puts a tool away), drawing where you click, into frames as they are at the playhead. A selected layer shows its handles in Animate as well: resize and turn it where it is at the playhead, and its animation follows, so a Rotate or Resize action's end turns or grows with it. Double-click a text to retype it, and Option-drag to copy layers with their actions. Editing a shape's points, cropping pictures and moving the anchor stay in Design.",
            "Dragging a number no longer stops at the edge of the screen. While you drag, the pointer goes on past the edge and comes back in from the other side, as in Figma, so one drag can change a number by as much as you like; let go and the pointer is where you left it.",
            "Every fill and every stroke in the inspector, as effects already were. The Fill and Stroke sections list each one, the one on top first, each under its own name row with a button to remove it; + in the section's header adds another on top. Each has its own colour or gradient, show and hide, and for strokes alignment, width and settings. Layers copied from Figma with several fills or strokes can now be edited whole.",
            "The sound while you play is kept under full scale as an export's is, so loud overlapping clips no longer crackle or distort in the editor or the export panel's preview. What you hear while editing is now exactly what an export writes: the same mix, the same fades, the same limiter.",
            "Copy Style and Paste Style, as Figma's Copy and Paste Properties (⌥⌘C and ⌥⌘V, in the Edit menu and a layer's right-click menu in Design). Copy a layer's style and paste it onto any number of selected layers: its opacity, blend mode, shadows and blurs, fills and strokes, and for text its font, weight, size, alignment, spacing, colour and stroke, never its words. A shape's colour and stroke paste onto text, and a text's onto a shape.",
            "Radial gradients can be ovals, as in Figma. A radial gradient's line on the canvas has a third handle, across from the end: drag it in or out to squash or stretch the circle into an oval, and turn the line to turn the oval with it. It works for a layer's fill or stroke in Design and for a Colour or Stroke action's gradient in Animate, where an oval blends into another as the action plays. Oval radial gradients copied from Figma, and radial gradients in SVG files that are wider than they are tall, now come in as ovals rather than circles.",
            "Copy Easing and Paste Easing are now ⇧⌘C and ⇧⌘V, so ⌥⌘C and ⌥⌘V can copy and paste style as in Figma.",
            "Two more easings, Ease out back and Ease in back, at the end of the easing card before Linear. Ease out back passes the end and comes back onto it; Ease in back pulls back below the start, then goes. Their curves are 0.45, 1.45, 0.8, 1 and 0.3, -0.05, 0.7, -0.5, and Intensity makes them pull further or less.",
            "An Inner Shadow action, under Style, for shapes and frames: it animates the layer's first inner shadow (colour, offset, blur and spread), or brings one in from nothing when the layer has none.",
            "The Stroke action works on text with a stroke: its width and colour animate as a shape's do.",
            "Gradients in Animate have their handles on the canvas. Select a Colour or Stroke action that ends on a gradient and its line shows on the layer as it is when the action ends: drag the ends to turn and stretch the gradient it ends on, drag the line to move it, slide or add stops, as in Design. Grabbing it takes the playhead to the action's end, so you see what you set. When only the starting value is a gradient, the line sets that, at the action's start.",
            "Copy a scene onto another layer. Click a scene's row, copy, select another layer and paste: the scene's actions go onto that layer at the same times, each making its motion from where the new layer stands, as a scene of their own called \"Scene 1 copy\". Pasted onto several layers, each gets its own. Duplicating a whole scene, or a layer whose actions make a whole scene, also makes a new scene; copies of only some of a scene's actions still join it.",
            "Search with ⌘K, on the home screen and in a project. On the home screen it finds projects by name (Return opens one; Tab shows Rename, Duplicate, Info, Show in Finder, Move to a folder and Move to Trash), folders, New Folder and Settings. In a project it finds the actions and presets the selection can take (Fade In and Fade Out each by name), the tools, the timeline's own commands, every menu command that can be used at that moment with its shortcut, and layers and scenes by name. Type a value to use it directly: `opacity 50`, `w 400`, `x 120`, `rotate 45`, `scale 150`, `radius 8` or `length 6s` set the selected layers or the scene, and `2.5s` or `f120` move the playhead. What you chose lately comes first.",
            "Corner radius on every shape with corners, as in Figma: polygons have a Radius field beside their sides, and paths one too. Double-click a shape to edit its points, pick one or several, and the Radius field rounds just those corners, showing the largest dimmed when they differ. A rectangle keeps its four corners; a polygon or star becomes a path once its points differ. The outline you edit shows the rounding, with each point at the corner it rounds, and rounded shapes keep their corners when they turn into paths. The Corner Radius action works on polygons too, and a Path action carries each point's radius along, so corners can round and sharpen as it plays.",
        ], fixes: [
            "Rounded corners copied from Figma with the Twine plugin come in rounded. A vector's rounded points arrived sharp, since Figma keeps their radius apart from the outline the plugin copied; they now come in carrying their radius, which you can change point by point. Rounded polygons come in as polygons with their radius, rather than as a flattened outline.",
            "A menu opened from inside a card, such as the Trim menu in the stroke's settings, opens over the card and leaves it up, rather than closing it.",
            "The playhead's time and the ruler's numbers no longer spill over the play controls when the timeline is scrolled or the playhead is near the start: the ruler keeps to its own area, and the time stays whole at either end while the playhead is in view.",
            "Opening a project with text is far quicker on a Mac with many fonts. Each new text style asked macOS for the list of every installed font, about a tenth of a second each time; the list is now kept until fonts are added or removed. A large project of 316 texts in 16 styles opens in 0.8 s, from 2.6 s, and selecting text no longer waits on it either.",
            "Very large projects are far quicker. In a project of 5,000 layers with 550 actions, playback runs at a full 60 frames a second (it was 25), scrubbing keeps up (8 ms a step, from 105), dragging a layer takes about 25 ms a step (from 50), and each edit is applied in under 2 ms. Twine now keeps everything no action moves as it was worked out last time, rather than working all of it out again every frame.",
            "Pressing on the canvas in a project with thousands of layers no longer freezes Twine for several seconds before a drag starts. Lining up the snapping guides looked up every layer's groups by searching the whole project, once per layer.",
            "Pointing at and clicking layers stays quick in a project with thousands of layers. Each layer under the pointer was checked for a locked group by searching the whole project.",
            "Saving a very large project no longer pauses Twine for half a second after each edit. Its picture on the home screen is drawn as the project closes, rather than with every save.",
            "Projects with more than 512 texts no longer lay all their text out again on every edit and frame.",
            "Playback no longer stutters while a large group moves with motion blur. Each of the blur's eight copies drew every layer in the group again, so a group of 500 layers was 4,000 layers a frame and slowed the whole Mac; the group is now drawn once and its copies made from that picture. In a project whose screens slide in with motion blur, the slowest frames draw in about 50 ms, from 400.",
            "Shift-dragging a selected layer moves it straight across or straight up and down, as in Figma. Shift took the layer out of the selection as soon as it was pressed, so there was nothing left to drag; now it leaves the selection only when Shift-clicked without dragging.",
            "A project from someone else can no longer reach files outside itself. A picture or video in a project is found by its file name, and a name with a path in it, or a file that was a link elsewhere on the Mac, made Twine show that outside file and copy it into the project when saving. Such a picture now shows grey, and nothing outside the project is read or copied.",
            "A damaged or hand-edited project no longer stops Twine as it opens. Numbers far past anything Twine makes, such as a Volume fade billions of years long, a star with a trillion points or an enormous type size, are brought back to the largest Twine allows as the file is read.",
            "SVG files and Figma pastes made to stall Twine are refused, rather than freezing it or filling the memory: an SVG saved in UTF-16 could hide entities that grow a few bytes into gigabytes, and a small one could make macOS's drawing of its text repeat its definitions for hours. Each picture drawn for an SVG now carries only the definitions it uses, and the drawing for one import or paste is held to a limit.",
            "A Figma paste with numbers far past anything Figma makes, such as an enormous type size, no longer stops Twine; they are held to the same limits as a project file, as are layers and actions pasted from Twine's own copy. Pictures over 16,384 pixels a side or 100 million pixels inside an SVG or a paste are left out.",
            "Importing a WebM that is really something else is refused with a note, rather than handed to ffmpeg to work out: a file named .webm that was a list of other files made ffmpeg read those into the movie, which the project then kept.",
            "Very large pictures are safe to import. Over 16,384 pixels a side or 100 million pixels, a picture is shown at that size, so a big photo still comes in; past 400 million pixels or 65,535 a side it is refused with a note, since even shrinking it as it opens takes seconds and gigabytes. Projects that already hold one show it the same way.",
        ], misc: [
            "Twine runs with macOS's hardened runtime, so other programs on the Mac cannot slip their code into it or attach to it while it runs.",
            "The test tools' driver can no longer end up in the app by being left in: it is built only into the separate test copy, and building the app refuses while it is in place.",
            "The picture at the top of a project's Info card fills the card's width at its own shape, rather than shrinking to a fixed height with space at its sides; a tall one is cut to a square, as on the home screen's cards.",
            "Settings' cards lie flat on the page, with no shadow under them.",
            "Cancel in the export window is a plain grey button while an export runs, rather than blue: it is not the thing the window is for.",
            "Twine builds with Xcode 27, whose stricter checks needed a few small changes inside; nothing you use changed.",
            "The Figma plugin has its new plugin id (1688993758222572916).",
            "The small icon buttons in the panels (the width and height link, the scale link, the corners button, and the add and remove buttons) are drawn in the same grey as the other controls, not the dim grey that reads as switched off. Only a button that cannot be used is dimmed.",
        ]),
        .init(date: "30 September 2026", title: "Scenes and GIFs", features: [
            "Scenes on the timeline. Pick actions from any layers and choose Group into Scene (in the inspector, or the timeline's right-click menu): they gather under a row with the scene's name, how long it runs and a deep blue bar across its whole span. Drag that bar to move everything in the scene together, or drag its ends to stretch or squeeze it all in proportion. A scene folds with its chevron; double-click its name to rename it there, or use Rename Scene… on the right-click menu, beside Ungroup Scene. Duplicating or pasting an action in a scene, or a layer with actions in one, puts the copies in the same scene. Scenes are saved with the project.",
            "GIF and WebM exports. GIF (animated) is for Slack, Notion and prototypes: silent, at most 50 frames a second, each frame with its own colours, flat colour kept exact and gradients finely dithered; on an opaque background only what changes is stored, so a 5-second 4K GIF of shapes moving came out at 630 KB. WebM (VP9) keeps transparency and sound, and is made by the ffmpeg installed on this Mac.",
            "Fold the timeline by layer. A layer with more than one action has a chevron on its first row: click it to gather all its rows into one, its bars side by side, which still click, move and trim. Clicking the folded row's name selects all its actions. Fold All Layers and Unfold All Layers are on the timeline's right-click menu, and adding an action to a folded layer opens it.",
            "Document colours. The colour picker shows the colours the project already uses, most used first, as swatches under the hex. A click takes one.",
            "Search in the preset picker. It opens ready to type: \"slide\" or \"blur\" narrows the tiles to the presets named so (their Out names and groups count too), and Return adds the first.",
            "New Project on the home screen, or ⌘N there, makes the project in the folder you are looking at.",
        ], fixes: [
            "The colour picker follows a colour taken from the eyedropper or typed as a hex: its square and bars stayed on the colour it opened with.",
            "Duplicating or pasting a layer keeps motion blur on its actions. It was switched off on the copies.",
        ], misc: [
            "Where \"scene\" meant the whole animation, it now says so: the export range is Whole animation or Part of the animation.",
            "The project's name at the top of the export window is smaller, 24 points rather than 32.",
        ]),
        .init(date: "30 September 2026", title: "Motion blur", features: [
            "Motion blur on actions. Any action or preset that moves, scales, turns, skews or tilts a layer has a Motion blur switch under Easing. While it plays, the layer smears along its movement, as a camera's shutter does.",
            "Amount sets how long the shutter stays open: 50% is a 180° shutter, 100% a whole frame.",
            "Only what that action moves smears; anything else the layer does at the same time stays sharp. Text presets that move letter by letter blur each letter by its own motion.",
            "Swap Preset. With a preset selected, Swap Preset puts another in its place. The bar keeps when it starts and takes the new preset's name, easing and length unless you had changed them.",
            "Copy actions from one layer onto another. Copy bars in the timeline (Command-C, or Cut and Copy on a bar's right-click menu), then paste onto another layer with Command-V, Paste on a timeline row's right-click menu, or Paste Action on a layer's right-click menu. Each lands at the playhead on a row just under that layer's others, with the same length, easing and settings, and makes the same motion from where the new layer stands: a Move to a spot travels as far the same way.",
            "Duplicate in the timeline, from the right-click menu or Command-D. The copy goes on the row just below its original, starting where the original ends, and is selected.",
            "The export's percentage counts like an odometer: each digit that changes rolls, and the percent sign stays still. It never shows more than 100%, nor a number it never reached on the way (it could flash 109% just before 100%).",
            "Importing shows how it is going. When a picture, video or sound takes more than a moment to come in, a note at the top says so with a loader, and a WebM's conversion shows how far it has got. Once done, the note says so for three seconds before it goes.",
            "Arrow keys in number fields, as in Figma. With a field clicked into, Up and Down change its number by one (a tenth of a second for times), and by eight with Shift.",
            "An action's Start and Duration (which was Length) have their names above their fields, so the numbers are never cut off.",
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
