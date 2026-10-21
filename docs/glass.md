# Glass: handoff notes

19 to 21 October 2026, v0.2.35 to v0.2.41. Figma's Glass effect, built in Twine as an effect and an action. These notes are for whoever carries the work on: what is built, how it works, every problem met on the way and why it happened, what is still open, and how to test it. The short version of the design is in `CLAUDE.md` under **Glass**; this is the long one.

## What the user asked for

"Support for liquid glass in effects, the same or similar to how Figma has implemented it", with a Glass action to animate it. Later, from the user: Depth is limited to 100 px. On 21 October 2026, after the screen kept showing through: "do the rebuild, draw behind the glass yourself".

## What is built

- **The effect** (`EffectKind.glass(Glass)`, file format 10): shapes and frames only, the first one switched on counting, as with background blur. Figma's panel settings, in Figma's order: Light (angle on Figma's dial, 0 at the top and -45 the top left, plus intensity), Refraction, Depth (0 to 100 px), Dispersion, Frost (px of blur, Figma's blur units) and Splay. `Glass()` is Figma's new glass (-45°, 80%, 80, 20, 50, 4, 0); `Glass.noGlass` is none; `Glass.held` clamps a file's numbers.
- **The inspector**: Effects + menu > Glass. `GlassControls` (`Twine/Components/PaintControls.swift`) draws the settings for both the effect and the action. The app says `Glass` through a typealias to MotionModel's, because SwiftUI on macOS 26 has a `Glass` of its own and the names clash.
- **The action** (`GlassAction`, the `glass` channel, listed under Blur): every setting blends, the light turning the shorter way round. From no glass it brings Figma's new glass in; on a layer with glass it takes it away. The swap button works.
- **Figma**: the plugin copies `GLASS` effects (`FigmaPlugin/code.js`), and `FigmaImport.effect` reads them. Figma's frost is the effect's `radius`. Figma's plugin API has no Splay yet, so pasted glass has Splay 0.
- **The AI tools**: `ProjectOutline` names the effect `glass`; the action list comes from `ActionFactory`, so it is already there.

## How it draws

There are two ways, one look. **Exports** (and thumbnails, stills, the AI tools' `render_frame`: everything through `OffscreenRenderer`) bend what is behind the glass with backdrops, which off screen see only the layers drawn before them. **The canvas and the export preview** never let the glass look at the screen: Twine draws a picture of the glass over what is behind it with that same export path, and shows the picture. `CoreAnimationRenderer.drawsGlassBehind` picks the second; `CanvasNSView` and `ExportPreviewView` switch it on.

### The glass itself (backdrops, as exports draw it)

All in `Packages/MotionKit/Sources/MotionRendering/Glass.swift`, whose header comment holds the spike's findings. It uses the private pieces macOS 26 builds its own Liquid Glass from. Twine is internal only, so private APIs are fine.

1. **Backdrops.** A `CABackdropLayer` shows what is behind the layer through Core Animation's `displacementMap` filter (Refraction). Over it, a second backdrop shows that through `chromaticAberrationMap` (Dispersion) and then `gaussianBlur` (Frost). It has to be two backdrops. A map filter that comes after another filter on the same backdrop reads its map out of place: the colours split in a cyan band along the top and bottom edges, and the bend disappeared.
2. **The field.** Each backdrop has a sublayer named `glassField`: a `CASDFLayer` (a distance field of the outline) holding one `CASDFElementLayer`, run through a `CASDFGlassDisplacementEffect`. Its `height` is Depth, and its `curvature` is 1 + 3 × Splay. A field that no filter reads draws itself as a blue card, and a hidden field bends nothing, so each is shown exactly while a filter reads it.
3. **The outline.** A box with every corner rounded alike (`ResolvedShape.roundedBox`: uniform rectangles, and circles filling a square box) uses the element's own `bounds` mode with a `cornerRadius`. It is exact and costs nothing. Every other outline (stars, ovals, polygons, pen paths, uneven corners) is a picture the element reads in its `contents` mode (`GlassField.picture`):
   - red is the signed distance, mapped between `contentsZeroValueDistance` and `contentsOneValueDistance`;
   - green and blue are the way out to the nearest edge, 0.5 plus half the unit direction (with green and blue at 0.5 nothing bends; with them at 0 the bend leans to one side);
   - it must be 16 bit and tagged sRGB, or the values are colour converted and the edge moves inward;
   - it is worked out at the pixels per point it shows at (zoom included, rounded up to a power of two, at most 2048 texels a side), 20 to 50 ms in release. At one texel per point a small star zoomed in bent in blotches.
4. **The light.** Over the fills, two more distance-field layers with `CASDFGlassHighlightEffect` light the rim from the angle, and from the opposite side at 60%. Each reaches 120° round the rim, about 3 px wide at depth 20.
5. **How far it reaches.** `GlassKit.fitted` holds Depth to half the box's shorter side. `GlassKit.margin` (how far past the box the backdrops, fields and elements reach) is the depth, at most 64 points of frost, and 8 more. The field only exists inside its element's frame, so it must reach past the shape; cut off at the edge, the bend went one-sided.

Strength constants are in `GlassKit` and were picked by eye, not matched to Figma: `refractionPerDepth` 1.0 (pixels the edge moves things, per pixel of depth, at full refraction), `dispersionPerDepth` 0.5, `oppositeLight` 0.6, `lightSpread` 120°.

### On screen: the picture (v0.2.41)

`CoreAnimationRenderer.drawGlassBehind`, run by `render` after its own transaction, for each glass layer at index `i` of the scene:

1. **What is behind** is `layers[..<i]`: the scene is flat, back to front, each group before its children, so that is everything drawn before the glass (earlier siblings, and its groups' own fills). Then `glassOnly(layer)`: the glass layer with no fills, strokes, shadows, blurs, mask, reveal, curl, motion blur, fade or blend, and its light off. Time is set to 0, so a still background is not drawn again.
2. **Drawn** by a `GlassBehind` (`GlassBehind.swift`, one per glass layer): its own `CoreAnimationRenderer` (backdrops, as exports) through a `CARenderer` into an `IOSurface`-backed Metal texture, two of them used in turn so the screen never shows one half drawn and always sees a new picture as new. The same scene, transform and size as last time draws nothing.
3. **Upright, over the composition.** The picture covers the box round the glass's working area (`GlassLayers.whole`, through `worldProjection`), clipped to the composition, snapped to whole pixels, at the canvas's pixels a point (`Node.pixelScale`: the window's backing scale times the zoom, up to 8), at most `GlassBehind.largestSide` (4096) a side. Upright, so its pixels meet the screen's: drawn in the layer's own turned points, a turned card's stripes came out soft.
4. **Shown** by `GlassLayers.show(_:area:toLocal:)`: in drawn mode the glass is one plain holder (no filters, no backdrop) under the fills, clipped to the outline, holding the picture placed through the inverse of the layer's world projection (turned over off screen, as other pictures). The clip reaches a pixel past the outline (`mask.lineWidth`), so the picture's own smoothed edge is not smoothed again. The light layers stay the layer's own, over its fills.

So on screen the glass can only ever show the composition, the same at every zoom and up to every edge of the window, and the canvas is the export, pixel for pixel (`glassDrawingWhatIsBehindItMatchesTheBackdrops`).

**Traps met building it:**

- **Never flush Core Animation on the main thread during a SwiftUI update** (the canvas renders from `updateNSView`; flushing there once stopped the app with a `dispatch_once` trap in the template picker). `GlassBehind.draw` does all its work, flush included, on its own serial queue (`work.sync`): transactions are per thread, so the canvas's are never touched. The main thread waits, so the shared `MediaLibrary` (no locks) is never used from two threads at once.
- **`render` must not be called inside an explicit `CATransaction`** with `drawsGlassBehind` on, or the canvas's changes it depends on are not committed. `OffscreenRenderer.draw` sets its scale and transform in a transaction of its own and calls `render` outside it.
- **Filtering the picture again on the canvas does not work.** A bend holder inside a colour split's holder read the split's map out of place (the old cyan band) and turned cards came out wrong; clipping the inner holder to the outline made the frost and split blur in nothing from past the edge. Hence the picture carries the finished glass.
- **Turning a picture over off screen** with a −1 vertical scale needs the turn about its middle, or it swings out of view (the first drawn glass showed nothing at all). The placement now folds the turn into one transform.
- **An `IOSurface`'s rows must be whole steps of 16 bytes for Metal.** A 2,254 pixel picture (the user's circle at 4×) stopped the app; rows are rounded up to 64 bytes (`aPictureOfWhatIsBehindTakesAnyWidth`).

## Issues met, and how each was fixed

1. **Distance pictures read wrongly** (the spike, 19 October 2026). Uniform values were colour converted (fixed by tagging sRGB); the distance was read from red, with green and blue as the direction (found by trial); and pictures run upside down off screen, so the rows and the vertical direction flip when `flipsContents` is on. The light's angle needs no flip.
2. **The butterfly** (v0.2.37). The user dragged Depth to 639 px on a 248 px circle. The bend then pulled in picture from hundreds of points away, turning the middle inside out into two mirrored lobes. Fixed by `GlassKit.fitted`, and since v0.2.38 by the 100 px cap.
3. **The screen showing through the glass** (v0.2.36 to v0.2.41). The user saw the tab bar, the Dock and the menu bar inside the glass, live, and worst when zoomed in.
   - **Why:** on screen, a backdrop shows whatever the window server has on the screen where it lies, other windows and the Dock included. Glass bends in picture from just past its edge, and zooming in scales that reach (Depth 100 at 4× reaches 400 points), so glass near the window's edge pulled in what was past the window.
   - **Tried, and not enough:** making the canvas its own group (a no-op `colorMatrix` filter, an explicit identity matrix, opacity 0.999 with group opacity, rasterising: a backdrop ignores them all; v0.2.36, taken out in v0.2.37). Cutting what each backdrop looks at to the part of the composition the canvas shows (`visibleArea`, v0.2.38): right at the bottom edge, but at the top, under the title bar, a backdrop still saw what was behind the window (Chrome's tab strip, measured green against the canvas's neutral #1E1E1E). Cutting below the title bar too (v0.2.40) stopped that but left a hard line where the bend stopped, which the user saw as artefacts, and the user still saw the bottom of the screen in the glass. A standalone window with the same backdrops, two stages, a zoomed parent, a titled see-through title bar, the window key and opaque panels over it never leaked, so the cause was never pinned down; it lies in how Twine's window is put together.
   - **Fixed (v0.2.41)** by not looking at the screen at all: see "On screen: the picture" above. `visibleArea` and `GlassLayers.clip(to:)` remain for backdrops on screen (nothing uses them now) and the v0.2.40 title-bar cut is gone.
   - **Learned on the way:** a backdrop cut short does not read the screen past its cut (a filtered backdrop cut at a window edge, with a magenta window just past it, showed no magenta). `CABackdropLayer` also has `backdropRect`, `marginWidth`, `bleedAmount`, `ignoresScreenClip` and `windowServerAware` (off by default), none needed.
4. **Blotchy bends when zoomed in** (v0.2.36): see the texel note in "How it draws" above.
5. **Rebuilding every frame while pinching** (v0.2.36). The canvas changes its pixel scale continuously during a pinch, so the field picture's scale is rounded to powers of two, and a rounded box (no picture) ignores the zoom altogether.

## Still open

- **Not compared with Figma side by side.** The strengths (bend, colour split, rim width and brightness, how Splay spreads) were tuned by eye on stripes. The next step is a Figma frame with a few glass shapes at known settings, rendered in both apps and matched.
- **The light's angle from Figma is unverified.** The importer takes `lightAngle` exactly as Figma's plugin API gives it. If pasted glass is lit from the wrong side, convert it there.
- **What counts as behind** is the flat list before the glass. Inside a 3D frame, where depth decides the order, a card nearer the camera but earlier in the list is still drawn behind the glass. A frame holding the glass draws its own strokes in the picture too (they are in front of its children on the canvas). Group opacity and blends around the glass are not carried into the picture.
- **Memory.** Each glass keeps two pictures, up to 4096 a side (64 MB each) when zoomed far in on a large glass.
- **Performance** was measured on the user's scene only (below). Many glass layers, or a Resize on glass that is not a rounded box (its field picture is worked out again every frame, 3 to 50 ms), are unmeasured.
- **Not supported:** glass on text (Figma may allow it), glass inside motion-blurred copies, and glass on a mask (mask nodes skip it).
- **Bent layers (Bend, `CAMeshTransform`) with glass** were never tried.
- **macOS 26 only.** Without the private classes, the glass draws as its frost alone. Without a GPU the canvas shows no glass at all.
- **Unused:** Core Animation's `glassBackground` and `glassForeground` filters exist, with many parameters, but did nothing useful in the spike. `CASDFGlassHighlightEffect` also has a `global` switch (light fixed to the screen, not the layer) that was not tried.

## How to test it

- **Unit tests:** `GlassRenderingTests` checks pixels through the export renderer: the bend stays near the edge, the colour split, frost, the light's side, non-box outlines, the field picture's values and its zoom, the depth cap, the visible-area clip; and, drawn as the canvas draws it, that it matches the backdrops for bend, Figma's default, split, frost, a star and a turned card, never bends in a layer in front, and takes pictures of any width. `TWINE_GLASS_OUT=folder swift test --filter GlassRenderingTests` writes each picture to look at.
- **Test projects:** `python3 Tools/SelfTest/make-glass-projects.py FOLDER` writes Glass, Mid, User and Edge (see its header), then run `Tools/SelfTest/run.sh FOLDER/User.twine NAME "steps"`. The kit has `zoom F` and `pan DX DY` steps for this. The test copy opens at the frame saved in its own defaults (`NSWindow Frame Main` in `com.nidhin.twine.selftest`); copy the user's from `com.nidhin.twine` to test their window exactly.
- **The canvas no longer depends on the screen**, so the kit's window shots show what the user sees. To prove it on the real screen, bring the test copy to the front and capture: glass across the window's top edge (`key m;zoom 2;zoom 2;wait 1;pan 0 -380` on User.twine) and its bottom (`pan 330 420`). On 21 October 2026, with the user's window under the menu bar, both bent right to the edge with nothing from outside the window. `open -a build/TwineTest.app` brings the window over from another Space where `activate` does not; keep captures brief and say so first, since the user may be working.
- **Playback** (release test copy, `perfplay 5`, the user's scene of a Column Wall template behind a glass circle), drawn glass: 59.8 fps still and animating every frame through a Glass action, 59.6 fps at 4× zoom, 58.8 fps at 8×.
