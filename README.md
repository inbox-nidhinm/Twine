# Twine

A native macOS app for motion design with Figma import via plugin.

## Running it

```bash
./make-app.sh
open build/Twine.app
```

`./make-app.sh debug` makes a debug build. `./test.sh` runs the unit tests. The project also opens in Xcode (`Twine.xcodeproj`), where Run works as usual.

### The font

Titles are set in AA Bridge Slab, a typeface of its own kept in a separate repo, [AA-Bridge](https://github.com/inbox-nidhinm/AA-Bridge), which Twine includes as a git submodule at `Vendor/AA-Bridge`. You do not need it to build: copies of the three files Twine uses (the variable font, its licence and the web font for the Figma plugin) are kept in this repo. If you have access to AA-Bridge, `git submodule update --init` fetches it, and from then on `./make-app.sh` refreshes those copies from it before each build (`Tools/update-fonts.sh` does the copying). Without it, the build uses the copies as they are.

## Where things are

Projects live in `~/Documents/Twine Creations`. A new project is written there the moment it is made and saves itself about a second after every change, so nothing is ever unsaved and closing a window never asks a question. File > Revert To browses older versions.

A project file (`Name.twine`) is a folder that the Finder shows as one file.

```
Name.twine/
    document.json    the project, with a formatVersion
    media/           imported images, video and audio
    thumbnail.png    for the home screen (from milestone 2)
```

## Status

Original milestones 1 to 4 (foundation, evaluation and rendering, canvas and shapes, timeline and playback), then all 8 redesign milestones and export: the action model and its evaluation, separate Design and Animate modes, the action timeline, editing actions in the inspector and on the canvas, MP4, MOV and PNG export, Style and Blur actions, text layers with Text and Shape actions, and pictures, video and sound with Play bars. After those: masks; snapping and alignment; hover, cursors and timeline polish; exporting part of the scene; the ⌘/ shortcuts card; presets made of actions; and a performance pass. Then the pen tool with point editing and the Path action, and the Volume action for fading sound. And any export size, as a percentage, up to 4K. Twine is for internal use only, never the App Store. See `docs/brief.md` for the original plan, `docs/redesign.md` and `docs/redesign-decisions.md` for the redesign, and Version History on the home screen for what each build changed.

## License

[MIT](LICENSE). The bundled AA Bridge Slab font (also embedded in the Figma plugin's panel), built from Montagu Slab, is not covered: it is under the SIL Open Font License (`Packages/MotionKit/Sources/Theme/Resources/Fonts/AABridgeSlab-OFL.txt`).
