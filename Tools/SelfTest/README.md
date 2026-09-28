# Testing in the running app

A kit for checking changes in the real app without touching the copy the user has open: a separate test copy of the app, a driver that runs a script of clicks, keys and checks inside it, sample projects, and profiling helpers. Nothing here is built into the app unless the hook is installed.

## The loop

```bash
Tools/SelfTest/install-hook.sh              # puts SelfTest.swift into the app
Tools/SelfTest/make-test-app.sh             # builds build/TwineTest.app (debug; pass release to measure speed)
Tools/SelfTest/run.sh Actions t1 "wait 1;key m;seek 1;shot a"
Tools/SelfTest/remove-hook.sh               # always, before committing
```

The test copy's home screen lists `$OUTROOT/Creations` (or `$TWINE_TEST_CREATIONS`), set through `TWINE_CREATIONS`, so it never sees or changes the projects in use.

`run.sh PROJECT NAME "steps"` copies the project first (from `Projects/`, or any `.twine` path, which is never changed), opens it in the test copy in the background, runs the steps, and prints the state after each one: selection with positions, actions, mode, tool, time, export, menu, hover, first responder. Screenshots from `shot X` go to `$TWINE_TEST_OUT/NAME/X.png` (default a folder in `$TMPDIR`), the log to `NAME.log`. Screenshots come out at 1× or 2×; scale to 1440 wide (`ffmpeg -vf "scale=1440:-1,crop=w:h:x:y"`) to read coordinates, which are window points from the top-left.

Projects: `Actions` (two layers with Move, Rotate, Opacity, Scale, Hide), `Blank`, `Mask` (stripes and a spot), `Style` (bars, card, blob, ring with style and blur actions), `Text`. The heavy performance scene is made by the benchmark: `cd Packages/MotionKit && TWINE_BENCH=1 TWINE_BENCH_OUT=/path/document.json swift test -c release --filter PerformanceTests`, then put that `document.json` in a `Name.twine` folder.

## Steps

Separate steps with `;`. Prefix a mouse or key step with held keys: `shift+`, `cmd+`, `opt+`, `ctrl+`, `dbl+` (double-click), combined with commas, as in `ctrl,opt+keycode 4`.

| Step | Does |
|---|---|
| `shot NAME` | Waits for a screenshot of the window |
| `wait S` | Waits S seconds after this step (the default is half a second) |
| `seek T` | Moves the playhead |
| `click X Y`, `rclick X Y` | A click or right-click |
| `qclick X Y`, `qrclick X Y` | The same, sent through the app's event queue like a real click: needed for right-click menus over SwiftUI views (home screen cards and folders), which look at the current event |
| `drag X1 Y1 X2 Y2` | A drag in ten steps |
| `down X Y`, `to X Y`, `up X Y` | A held drag, a step at a time, for screenshots mid-drag |
| `open X Y`, `pick X Y` | Clicks until the app's menu opens, or closes |
| `key K` | `space`, `enter`, `del`, `left`, `right`, `comma`, `stop`, `esc`, or a letter |
| `keycode N`, `type TEXT`, `clear` | A key by code (Option changes characters), typing, deleting a field |
| `spacedown`, `spaceup` | Holds and releases Space |
| `menukey C` | ⌘C through the main menu |
| `hover X Y`, `rhover X Y`, `chover X Y` | Pointer moves handed straight to the timeline tracks, the ruler or the canvas (`chover` logs `HOVER`) |
| `call NAME` | `duplicate`, `shortcuts`, `copy`, `paste`, `undo`, `focuscanvas`, `copyeasing`, `pasteeasing`, `exportmovie` (opens the export panel; again, exports), `exportframe`, `staggermenu`, `group`, `frameselection` |
| `savepanel PATH`, `waitexport` | Fills and closes a save panel, waits for an export |
| `import PATH`, `save` | Imports media (an `.svg` comes in as layers), saves |
| `actions`, `spec`, `text` | Logs every action, the selected actions' specs, the selected text layer |
| `path`, `path xy` | Logs the selected shape's points, style and box, and whether its points are showing or being drawn; `xy` adds each point's and handle's place in the window, to click on |
| `moveproject NAME FOLDER`, `showfolder FOLDER` | Moves a home screen project into a folder (`-` for out of one), as a drop does; shows a folder (`-` for All Projects) |
| `library` | Logs the home screen's folders (with counts), which is showing, and every project with its folder |
| `home`, `openfile PATH` | Turns the window to the home screen, as the Home button does; opens a project in the window, as the Finder does (never point it at a real project) |
| `replace PATH`, `fillpicture PATH` | Replace in the inspector, or Image as the fill, with the file handed in rather than chosen in the panel |
| `mode M`, `turn` | The selected picture's mode (`fill`, `fit`, `crop`, which starts cropping, `tile`) and a quarter turn |
| `blend M`, `effect inner\|drop DX DY BLUR HEX` | Sets the selection's blend mode (`multiply`, `screen`...); adds a shadow, as the Effects menu does |
| `pastefigma PATH`, `composition` | Pastes a copy from the Figma plugin read from a file (such as `FigmaPlugin/test/sample-payload.json`), leaving the clipboard alone; logs the composition's size and any notice |
| `tree` | Logs every layer under its parent: kind (frame, group, picture...), place, size, scale, clipping, fills and strokes, then the selection and the last undo |
| `picture` | Logs the selected picture or video: file, mode, crop, turns, actions, whether it is being cropped, and while cropping the picture's and the box's corners in the window, to drag |
| `offers` | Logs what Add Action and Add Preset offer for the selection |
| `add KIND` | Adds an action by its kind's name (`move`, `path`, `volume`...), as the Add Action menu does |
| `preset ID`, `split`, `sample T` | Adds a preset by its id (`slide-in`, `shake`...), as Add Preset does; Split into Actions on the selected bars; logs the selected layers' position and opacity at time T |
| `cursor` | Logs which of the app's pointers is current |
| `perfpreview S` | The export panel's preview playing for S seconds (open the panel first with `call exportmovie`) |
| `perfplay S`, `perfscrub N`, `perfdrag N`, `perfdragat X Y N`, `perfselect N` | Timings (`PERF` lines): playback frame rate, seek, canvas drag, drag at a point, select |
| `clicksample X Y`, `addsample move` | Samples the playhead after a click, or after adding an action |

## Profiling

`profile.sh PROJECT NAME "steps" DELAY SECONDS` samples the test copy while a script runs and ranks the app's own functions on the main thread. Use a release test copy.

## What fools a test

- Posted `mouseMoved` events never reach tracking areas: use `hover`, `rhover`, `chover`, which call the view directly.
- The pointer after a cursor-rect refresh follows the real mouse, which is elsewhere during a test, so `cursor` readings taken after one mean nothing. Readings straight after a `mouseMoved` are good.
- Menu shortcuts and responder-chain actions do not reach a window that is not active, and the test copy never is. Call the command through `call`, or say it was not checked.
- SwiftUI reads modifier keys from the real keyboard: a posted Shift-click in the layers panel is a plain click. Shift-click on the canvas instead.
- Build points the right way up. `hitTest` takes the superview's coordinates; see CLAUDE.md. A hook that makes the same mistake as the app passes when it should fail.
- The save panel ignores `directoryURL` once shown and puts the file in its last folder (the test copy's `NSOSPLastRootDirectory`). Check where it went before looking anywhere else, and never let a test file land in the user's folders.
- `pkill -f` with the app's name in your own command line kills your own shell: the scripts use `pkill -x`.
- After changing a MotionKit struct's stored properties, clean builds (`swift package clean`, delete `build/DerivedData`) before trusting a crash.
