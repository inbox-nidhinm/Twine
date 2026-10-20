# Glass: handoff notes

19 and 20 October 2026, v0.2.35 to v0.2.40. Figma's Glass effect, built in Twine as an effect and an action. These notes are for whoever carries the work on: what is built, how it works, every problem met on the way and why it happened, what is still open, and how to test it. The short version of the design is in `CLAUDE.md` under **Glass**; this is the long one.

## What the user asked for

"Support for liquid glass in effects, the same or similar to how Figma has implemented it", with a Glass action to animate it. Later, from the user: Depth is limited to 100 px.

## What is built

- **The effect** (`EffectKind.glass(Glass)`, file format 10): shapes and frames only, the first one switched on counting, as with background blur. Figma's panel settings, in Figma's order: Light (angle on Figma's dial, 0 at the top and -45 the top left, plus intensity), Refraction, Depth (0 to 100 px), Dispersion, Frost (px of blur, Figma's blur units) and Splay. `Glass()` is Figma's new glass (-45°, 80%, 80, 20, 50, 4, 0); `Glass.noGlass` is none; `Glass.held` clamps a file's numbers.
- **The inspector**: Effects + menu > Glass. `GlassControls` (`Twine/Components/PaintControls.swift`) draws the settings for both the effect and the action. The app says `Glass` through a typealias to MotionModel's, because SwiftUI on macOS 26 has a `Glass` of its own and the names clash.
- **The action** (`GlassAction`, the `glass` channel, listed under Blur): every setting blends, the light turning the shorter way round. From no glass it brings Figma's new glass in; on a layer with glass it takes it away. The swap button works.
- **Figma**: the plugin copies `GLASS` effects (`FigmaPlugin/code.js`), and `FigmaImport.effect` reads them. Figma's frost is the effect's `radius`. Figma's plugin API has no Splay yet, so pasted glass has Splay 0.
- **The AI tools**: `ProjectOutline` names the effect `glass`; the action list comes from `ActionFactory`, so it is already there.

## How it draws

All in `Packages/MotionKit/Sources/MotionRendering/Glass.swift`, whose header comment holds the spike's findings. It uses the private pieces macOS 26 builds its own Liquid Glass from. Twine is internal only, so private APIs are fine.

1. **Backdrops.** A `CABackdropLayer` shows what is behind the layer through Core Animation's `displacementMap` filter (Refraction). Over it, a second backdrop shows that through `chromaticAberrationMap` (Dispersion) and then `gaussianBlur` (Frost). It has to be two backdrops. A map filter that comes after another filter on the same backdrop reads its map out of place: the colours split in a cyan band along the top and bottom edges, and the bend disappeared.
2. **The field.** Each backdrop has a sublayer named `glassField`: a `CASDFLayer` (a distance field of the outline) holding one `CASDFElementLayer`, run through a `CASDFGlassDisplacementEffect`. Its `height` is Depth, and its `curvature` is 1 + 3 × Splay. A field that no filter reads draws itself as a blue card, and a hidden field bends nothing, so each is shown exactly while a filter reads it.
3. **The outline.** A box with every corner rounded alike (`ResolvedShape.roundedBox`: uniform rectangles, and circles filling a square box) uses the element's own `bounds` mode with a `cornerRadius`. It is exact and costs nothing. Every other outline (stars, ovals, polygons, pen paths, uneven corners) is a picture the element reads in its `contents` mode (`GlassField.picture`):
   - red is the signed distance, mapped between `contentsZeroValueDistance` and `contentsOneValueDistance`;
   - green and blue are the way out to the nearest edge, 0.5 plus half the unit direction (with green and blue at 0.5 nothing bends; with them at 0 the bend leans to one side);
   - it must be 16 bit and tagged sRGB, or the values are colour converted and the edge moves inward;
   - it is worked out at the canvas's pixels per point (zoom included, rounded up to a power of two, at most 2048 texels a side), 20 to 50 ms in release. At one texel per point a small star zoomed in bent in blotches.
4. **The light.** Over the fills, two more distance-field layers with `CASDFGlassHighlightEffect` light the rim from the angle, and from the opposite side at 60%. Each reaches 120° round the rim, about 3 px wide at depth 20.
5. **How far it reaches.** `GlassKit.fitted` holds Depth to half the box's shorter side. `GlassKit.margin` (how far past the box the backdrops, fields and elements reach) is the depth, at most 64 points of frost, and 8 more. The field only exists inside its element's frame, so it must reach past the shape; cut off at the edge, the bend went one-sided.
6. **On screen only:** what each backdrop looks at is cut to `CoreAnimationRenderer.visibleArea` (see issue 3 below).

Strength constants are in `GlassKit` and were picked by eye, not matched to Figma: `refractionPerDepth` 1.0 (pixels the edge moves things, per pixel of depth, at full refraction), `dispersionPerDepth` 0.5, `oppositeLight` 0.6, `lightSpread` 120°.

## Issues met, and how each was fixed

1. **Distance pictures read wrongly** (the spike, 19 October 2026). Uniform values were colour converted (fixed by tagging sRGB); the distance was read from red, with green and blue as the direction (found by trial); and pictures run upside down off screen, so the rows and the vertical direction flip when `flipsContents` is on. The light's angle needs no flip.
2. **The butterfly** (v0.2.37). The user dragged Depth to 639 px on a 248 px circle. The bend then pulled in picture from hundreds of points away, turning the middle inside out into two mirrored lobes. Fixed by `GlassKit.fitted`, and since v0.2.38 by the 100 px cap.
3. **The screen showing through the glass** (v0.2.36 to v0.2.38). The user saw the tab bar, the Dock and the menu bar inside the glass, live, and worst when zoomed in.
   - **Why:** on screen, a backdrop shows whatever the window server has on the screen where it lies, other windows and the Dock included. Glass bends in picture from just past its edge, and zooming in scales that reach (Depth 100 at 4× reaches 400 points), so glass near the window's edge pulled in what was past the window.
   - **What does not work:** making the canvas its own group. All four ways were tried on the real screen with the same result (a no-op `colorMatrix` filter, an explicit identity matrix, opacity 0.999 with group opacity, and rasterising). A backdrop ignores them all. This went out in v0.2.36 and was taken out again in v0.2.37.
   - **What works:** cutting what each backdrop looks at to the part of the composition the canvas shows. `CanvasNSView.layoutWorld` sets `visibleArea` from its whole view (clipped to the composition) on every zoom, pan and resize. The export preview sets it to the composition. `clipGlass` carries it into each glass layer's own points through `worldProjection` (turns, groups and 3D). A pan only moves the backdrops (`GlassLayers.clip(to:)`) and never rebuilds their filters. Clipping to the area between the panels instead left a hard line where the bend stopped, round the tool bar.
   - **Still leaking at the top (v0.2.38, fixed in v0.2.40).** Glass pushed across the window's top edge still bent in what was behind the window (Chrome's tab strip, measured green against the canvas's neutral #1E1E1E), while the bottom edge stayed clean. The clip itself was right (logged: the backdrop stopped exactly at the window's top). A standalone window with the same backdrops, two stages, a zoomed parent and a titled, see-through title bar never leaked, so the cause is Twine's window: under its title bar a backdrop sees what is behind the window rather than the canvas. `layoutWorld` now also cuts `visibleArea` to `window.contentLayoutRect`, the window below the title bar (about 28 points). Glass reaching into that strip stops bending at its lower edge.
   - **Learned on the way:** a backdrop cut short does not read the screen past its cut (a filtered backdrop cut at a window edge, with a magenta window just past it, showed no magenta). Wrapping a plain backdrop in a container that carries the bend instead leaves a hole where the bend reaches past the cut, so it was not used. `CABackdropLayer` also has `backdropRect`, `marginWidth`, `bleedAmount`, `ignoresScreenClip` and `windowServerAware` (off by default), none needed.
4. **Blotchy bends when zoomed in** (v0.2.36): see the texel note in "How it draws" above.
5. **Rebuilding every frame while pinching** (v0.2.36). The canvas changes its pixel scale continuously during a pinch, so the field picture's scale is rounded to powers of two, and a rounded box (no picture) ignores the zoom altogether.

## Still open

- **Not compared with Figma side by side.** The strengths (bend, colour split, rim width and brightness, how Splay spreads) were tuned by eye on stripes. The next step is a Figma frame with a few glass shapes at known settings, rendered in both apps and matched.
- **The light's angle from Figma is unverified.** The importer takes `lightAngle` exactly as Figma's plugin API gives it. If pasted glass is lit from the wrong side, convert it there.
- **Glass under the floating panels and tool bar** can bend in a little of that bar, since the clip is the whole canvas view. Left in on purpose (see issue 3).
- **Glass under the title bar** (the window's top 28 points or so, only reached when zoomed or panned up) shows the canvas unbent, with a hard line where the bend starts. Why a backdrop sees behind the window there is not understood (SwiftUI's hosting view, or the window being key, are the differences left from the standalone test); finding it would let the glass bend right up to the edge.
- **Glass straddling the window's edge** has its field cut there. The bend near the window's edge can look one-sided while zoomed in, which is harmless and gone when panned into view.
- **On screen against exports.** Off screen, glass past the composition sees nothing; on screen it is clipped to the visible composition. The two match except right at the composition's edge.
- **Performance during animation is unmeasured.** A Resize action on glass that is not a rounded box rebuilds the field picture every frame (3 to 50 ms each). Rounded boxes cost nothing. Check playback with a few glass stars resizing.
- **Not supported:** glass on text (Figma may allow it), glass inside motion-blurred copies (the rasterised copies' backdrops see nothing, as background blur's do), and glass on a mask (mask nodes skip it).
- **Bent layers (Bend, `CAMeshTransform`) with glass** were never tried.
- **macOS 26 only.** Without the private classes, the glass draws as its frost alone.
- **Unused:** Core Animation's `glassBackground` and `glassForeground` filters exist, with many parameters, but did nothing useful in the spike. `CASDFGlassHighlightEffect` also has a `global` switch (light fixed to the screen, not the layer) that was not tried.

## How to test it

- **Unit tests:** `GlassRenderingTests` checks pixels through the export renderer: the bend stays near the edge, the colour split, frost, the light's side, non-box outlines, the field picture's values and its zoom, the depth cap, and the visible-area clip. `TWINE_GLASS_OUT=folder swift test --filter GlassRenderingTests` writes each picture to look at.
- **Test projects:** `python3 Tools/SelfTest/make-glass-projects.py FOLDER` writes Glass, Mid, User and Edge (see its header), then run `Tools/SelfTest/run.sh FOLDER/User.twine NAME "steps"`. The kit has `zoom F` and `pan DX DY` steps for this.
- **Anything a backdrop pulls in from the screen only shows on the real screen.** Window captures (the kit's `shot`) redraw the window alone, so they never show a leak. Bring the test copy to the front, capture the screen, then quit it:

  ```bash
  osascript -e 'tell application id "com.nidhin.twine.selftest" to activate'; sleep 3; screencapture -x shot.png
  ```

  It comes out black while the Mac is locked. A macOS bug dims parts of some captures; that is not Twine. The user can be working, so keep captures brief and say so first.
- **The deciding leak test:** glass hanging past the window's **top** edge at 4× in Design, where nothing covers the canvas (`key m;zoom 2;zoom 2;wait 1;pan 0 -380` on User.twine), should bend only the composition, with nothing of the window behind inside it. The top is the edge that leaked last; the bottom (`pan 260 470`, clear of the tool bar) is the other open one, and the panels cover the sides. If the test window is on another Space, `open -a build/TwineTest.app` brings it over where `activate` does not.
- **Playback** (release test copy, `perfplay 5`, the user's scene of a Column Wall template behind a glass circle): 59.8 fps with glass off, on, or changing every frame through a Glass action.
