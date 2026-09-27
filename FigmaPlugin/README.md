# Twine for Figma

A Figma plugin that copies the selected frames and layers so Twine can paste them as editable layers.

## Adding it to Figma (once)

1. Open the Figma desktop app (development plugins only run there, not in the browser).
2. Open any design file, then choose **Plugins > Development > Import plugin from manifest…**
3. Pick `manifest.json` in this folder.

It then appears under **Plugins > Development > Twine**.

## Using it

Select a frame or some layers, run the plugin, and press **Copy**. In Twine, press ⌘V.

- Into an empty project, the composition takes the copy's size and it lines up exactly.
- Into a project with layers, it comes in centred, at its exact size.
- Text in one style comes in as Twine text. If its font is not on the Mac, a stand-in shows until it is installed, and Twine says which fonts are missing.
- What Twine cannot hold comes in as a sharp picture Figma drew: text with mixed styles, italics, underlines or lists; angular and diamond gradients; picture filters; luminance masks; skewed layers; FigJam items. Vectors painted region by region come in through Figma's own SVG.
- Figma's newer effects (noise, texture, glass) and frames' uneven borders are left out, and Twine says so.

## Files

- `code.js` reads the selection (Figma's plugin sandbox).
- `ui.src.html` is the panel. After editing it, run `python3 build.py` here, which writes `ui.html` with PP Kyoto embedded (Figma wants the panel as one file). PP Kyoto is a paid font; keep this folder, like the rest of Twine, private.
- `test/run.js` runs `code.js` against a stand-in for Figma and writes `test/sample-payload.json`, which Twine's tests read, so the two halves are checked against each other: `node FigmaPlugin/test/run.js`.

The copy is JSON on the clipboard, `{"format": "twine.figma", "version": 1, ...}`, read by `FigmaImport` in `Packages/MotionKit/Sources/MotionImport/FigmaImport.swift`.
