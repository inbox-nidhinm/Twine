# Templates: a plan

17 October 2026. Milestone 1, the spike, is done; its results are below. The decisions are at the end, before the appendix.

## What Animos has

Animos (animos.app) is a browser tool for showing designs in motion. You pick a template, drop pictures or videos into its slots, change its sliders and export a loop. It has 69 templates in nine groups:

| Group | Count | Templates |
|---|---|---|
| 3D & Perspective | 12 | Showcase Stream, Sphere Wall, Card Globe, Orbit Globe, Sphere Cascade, Totem Wall, Parallax Totem, Card Tunnel, Spiral Stream, Depth Stack Scroll, Cover Ring, Cover Ring Vertical |
| Multiscene | 13 | Bloom Belt, Lens Orbit, Stairway, Grid Dive, Pop Parade, Triple Scene, Collage Reel, Fan Shuffle, Sweep Ring, Scatter Dial, Grid Zoom Strip, Spread Rows, Spread Columns |
| Isometric | 3 | Iso Cascade, Iso Focus, Iso Orbit |
| Orbit | 8 | Orbit Showcase, Orbit Bloom, Orbit Carousel, Photo Orbit, Focus Orbit, Vortex Spin, Wheel Spin, Wheel Spin Bottom |
| Carousel & Flow | 10 | Card Totem, Film Strip, Wheel Carousel, Cover Flow, Cover Flow Vertical, Carousel Flow, Diagonal Carousel, Focus Slider, Mosaic Marquee, Hero Reel |
| Grid | 8 | Grid Reveal, Spotlight Zoom, Flip Grid, Pop Grid, Ticker Loop, Ticker Tilt, Column Drift, Feed Scroll |
| Spotlight & Focus | 4 | Center Stage, Focus Shift, Deck Peel, Zoom Parallax |
| Reveal & Wipe | 4 | Diagonal Wipe, Stripe Reveal, Split Reveal, Mosaic Wipe |
| Stack & Scatter | 7 | Stack Slide, Cascade Drop, Cascade Deck, Image Trail, Poster Burst, Card Toss, Position Dance |

Every template shares the same frame around it:

- **Slots**: 3 to 20 pictures or videos, in order. Some templates draw more cards than slots (Spiral Stream draws 24 cards from 12 slots) and go round the slots again.
- **Background**: colour, gradient or picture.
- **Loop length** (5 to 30 s, 16 by default): every template loops without a seam.
- **Card look**: corner radius, padding, card ratio (Auto, 1:1, 4:3, 3:4, 4:5, 16:9, 9:16), shadow.
- **Its own settings**: sliders (ring size, tilt, perspective, back fade, curvature, gap...), choices (direction, Continuous or Stepped, card style Curved or Flat) and an easing from the same list as Twine's (plus Snappy).
- Any slider can be keyframed over the loop.

Each template's full list of settings, as read from the editor, is in the appendix.

## What Twine has, and what is missing

Twine already has a lot of what these need: Tilt with depth (a flat layer turned in perspective), Twist, Page Turn and Page Curl, Mask presets and reveals, motion blur, the easing list, picture fills with crops, frames, shadows, presets as one bar with settings, and preset tiles that play the real thing.

What it lacks is a **shared 3D space**. Today every tilted layer is its own little scene, seen through its own camera, and a group flattens what is inside it. A ring of twelve cards needs one camera looking at all twelve, with each card nearer or further, and the near ones drawn over the far ones as the ring turns. That is the main new piece, and almost every Animos template stands on it.

The building blocks, in the order the templates need them:

1. **A 3D frame.** A frame (or group) switched to 3D has a camera: perspective (how strong), vanishing point, and an Orthographic choice for the isometric templates. Layers inside it get a **Z position** (towards or away from you) and turn on all three axes (Tilt's x and y become real 3D turns inside it). Twine works out each layer's place in 3D, sorts them by depth every frame and draws the nearest on top. Outside a 3D frame nothing changes.
2. **Depth effects on the 3D frame**: Depth fade (further is fainter), Depth blur, and Back faces (show, dim, hide) for cards facing away. Animos's "Back fade" and "Depth fade" are these.
3. **Bend.** Several templates bend each card round the ring or sphere (Sphere Wall's Curvature, Spiral Stream's "Curved (3D bend)", Vortex Spin's Curved, Card Totem's 3D curve). A flat turn cannot bend a picture, so this is its own effect, drawn with Core Animation's mesh warp (the spike's choice, below).
4. **Camera moves**: the camera can orbit, dolly in and out, and pan, which is how the Multiscene templates move from one layout to the next.

## Three layers of things

As you asked, the 3D work comes in at every level, each built from the one below:

### Effects and actions (the building blocks)

- **Properties**: Z position (in Position), 3D on a frame (perspective, vanishing point, orthographic, depth fade, depth blur, back faces), Bend (in Effects, like Skew and Tilt).
- **Actions**: Depth (z towards or away, its own action and channel), Rotate 3D (the Tilt action, which inside a 3D frame turns in the shared space), Bend, and camera actions on a 3D frame: Orbit Camera, Dolly, Perspective.

### Presets (a new 3D group)

One bar each, with settings, as every preset is, and letter by letter on text where it makes sense (letters flipping in is a strong one):

- Flip In and Out (a card turning over on its side or top)
- Swing In and Out (hinged on an edge, falling into place; Page Turn's cousin)
- Fold In and Out
- Tumble In and Out (turning on all axes as it arrives)
- Fly In and Out (from deep in Z, or past the camera)
- Spin 3D (an emphasis: a whole turn on Y)
- Float (an emphasis: a slow drift in Z and tilt)
- Iso Lift (rising out of an isometric plane)

These work on any layer. Inside a 3D frame they use its camera; on their own they bring their own perspective, as Twist does now.

### Templates (the new layer)

A template is a whole scene: many cards, a camera and the motion, from a list of pictures and a handful of settings.

**How a template lives in a project** (my recommendation): as presets do. A template is one frame in the layers panel, holding its slots and settings, and its cards are worked out when it plays, from the template's recipe. So every slider stays live: change Ring size and the whole ring changes, at any time. The frame can be moved, scaled, masked, put among other layers, and have text and a logo over it like anything else. **Split into Layers** (like Split into Actions) turns it into ordinary 3D frames, cards and actions for hand editing, and from then on it is not a template.

The other way, a template that writes ordinary layers and actions as it goes in, is simpler to build but loses the live sliders the moment it is placed, which is most of what makes Animos quick.

**Where templates are picked:**

- In Animate's inspector, a third tile beside New Action and Select Preset: Templates. It opens a picker like the preset picker (a search box, the nine groups, each tile playing the template with sample cards).
- With pictures selected, picking a template puts them into its slots in order (and replaces them, as Use as Mask takes the layers it is given).
- Home: New from Template, which makes a project at the template's size and length.
- ⌘K search lists templates by name.

**Its inspector**: Slots (drop wells, reorder by dragging, the count), Loop length (how long one loop takes; the template's bar on the timeline sets when it plays), Card (ratio, corner radius, padding, shadow), then the template's own settings, grouped as Animos groups them, with rare ones behind a settings button.

**Keyframing settings**: a later step: a Template action that moves one of its settings over time (Ring tilt from -28° to 0°), on its own bar.

## Milestones

Each ends with the usual gate: a clean `./make-app.sh`, `./test.sh` passing, the version history, a commit and a push.

1. **Spike, no interface.** Done: see Spike results.
2. **3D frames.** Done (17 October 2026): the camera on frames, Z position, tilts turning in the shared space (hinged ones too), depth sorting, depth fade and blur, back faces, isometric, file format 6, the 3D section and Z in the inspector, outlines and clicks on the canvas by what is drawn in front, masks and motion blur placed through the camera. Left for later: dragging in perspective (a drag is flat, so a little off, as in a tilted group), handles on 3D layers, and nested 3D (a group inside a 3D frame is a flat card).
3. **3D actions and Bend.** Done (17 October 2026): the Depth action, the Camera action with an orbit that turns the whole space (a ring spins with one action), and Bend as an effect and an action, drawn with the mesh warp (the Tilt action already turns in the shared space). A bent layer's outline runs through its corners, and a bent mask is placed flat.
4. **3D presets.** Done (17 October 2026): Flip, Swing, Fold, Tumble, Fly, Iso Lift, Spin 3D and Float in a 3D group, with playing tiles, letter by letter on text (but Fold). Z and the Depth action now work outside 3D frames too, seen from the layer's own tilt's depth, so these presets suit any layer.
5. **The template engine and the first 23.** Done (17 October 2026): the template frame, slots, settings, the recipes, the bar and its seamless loop, the picker and its playing tiles, the Template section, Split into Layers, and 3D & Perspective (12), Isometric (3) and Orbit (8). Not yet: videos in slots (pictures only), dropping pictures straight onto a slot, and the fuller Animos settings (only the main ones of each are offered). Our names, by Animos's:

   | Animos | Twine | Animos | Twine |
   |---|---|---|---|
   | Showcase Stream | Ring Stream | Iso Cascade | Iso Stream |
   | Sphere Wall | Curved Wall | Iso Focus | Iso Spotlight |
   | Card Globe | Globe | Iso Orbit | Iso Swing |
   | Orbit Globe | Tilted Globe | Orbit Showcase | Orbit |
   | Sphere Cascade | Curved Cascade | Orbit Bloom | Halo |
   | Totem Wall | Column Wall | Orbit Carousel | Quad Orbit |
   | Parallax Totem | Parallax Columns | Photo Orbit | Photo Loop |
   | Card Tunnel | Tunnel | Focus Orbit | Zoom Orbit |
   | Spiral Stream | Spiral | Vortex Spin | Vortex |
   | Depth Stack Scroll | Depth Stack | Wheel Spin | Wheel |
   | Cover Ring | Carousel Ring | Wheel Spin Bottom | Half Wheel |
   | Cover Ring Vertical | Vertical Ring | | |
6. **Flat and nearly flat templates (33).** Carousel & Flow, Grid, Spotlight & Focus, Stack & Scatter, Reveal & Wipe. Many lean on things Twine has (masks, reveals, presets).
7. **Multiscene (13).** The hardest: each moves through several layouts with camera moves between them.
8. **Keyframed settings and New from Template on Home.**

Milestones 2 to 4 are worth having on their own: they give Twine real 3D whether or not templates follow.

## Spike results (milestone 1, 17 October 2026)

What was built, and stays: `Space3D.swift` in MotionEvaluation (`Vec3`, `Pose3D` for where a flat layer sits in the space, `Camera3D` with a distance or none for isometric, and `Placed3D`, a layer's place as drawn and its depth), `ResolvedLayer.placed` (boxed, `.none` for every layer today), and the renderer setting each layer's `zPosition` from its depth. Tests: `Space3DTests` (the maths) and `Space3DRenderingTests` (pixels). Nothing in the model or the app uses it yet; milestone 2 has `evaluate` fill `placed`.

- **One camera for many layers works, exactly.** A flat layer seen in perspective is still a `Projective`, so the camera gives each card its whole transform and the renderer needs nothing new. The shared space agrees with Twine's own Tilt to the last decimal: a tilt is the same turn seen from a camera over the anchor.
- **Sorting by depth is free.** Core Animation orders sibling layers by `zPosition`, and with Twine's transforms that changes only the order, never the place. A ring of 12 tipped 20° draws the nearest card on top at every step of a turn, in exports (pixel tests) and on screen.
- **The canvas matches exports.** The same layer trees, put in a window and captured, differ from the export on 0.76% of pixels (the ring), 0.51% (strips) and 0.45% (mesh), all along edges where smoothing differs. A test process cannot show a window, so the check is `Tools/Spike3D/show-on-screen.swift` on trees the test saves (`TWINE_SPIKE_OUT`).
- **No cost to everything else.** Release build, the 200-layer scene: evaluate 0.95 ms (0.97 before), layer tree 0.18 ms (0.17), a 1080p export frame 10.9 ms (10.9).
- **A ring of 24 flat cards** costs 0.05 ms to place, 0.2 ms for the layer tree and 2.4 ms for a 1080p export frame.
- **Bending: both ways work in exports and on screen.**
  - *Strips* (each card cut into upright strips, each flat along its chord): 24 cards of 16 strips (384 layers) take 0.23 ms to update and 0.66 ms to draw at 1080p; 32 strips 0.48 and 1.2 ms. Public API only. But every join showed a quarter see-through seam until the strips' inner edges were left unsmoothed, and each strip needs its own copy of what it shows, so only a plain picture or video bends cleanly; rounded corners, strokes, shadows and anything inside a frame would have to be cut up too.
  - *Mesh* (Core Animation's private `CAMeshTransform`, one layer a card, a grid of points moved onto the curve): 24 cards at a 16 by 4 grid take 0.25 ms to update and 4.4 ms to draw at 1080p; 8 by 2, 3.5 ms; 32 by 8, 13.8 ms (too dear). No joins, so no seams, and it bends the whole layer with everything inside it, rounded clip included, so text, frames and video bend too. A layer's own clip is applied after its mesh, in its flat box, so the clip must sit one layer in, under the bent one.
  - **Recommendation: the mesh**, at 16 by 4 (finer only for very wide bends), falling back to drawing cards flat if the class is ever missing, as blur falls back. Twine already relies on private Core Animation classes, and the mesh is the only way that bends anything, not just pictures.
- **Still to learn in milestone 2**: shadows and background blur on bent and sorted cards, masks on cards in a 3D frame, hit testing and outlines from `placed`, and motion blur, whose copies assume flat steps.

## Risks

- **Speed.** The spike's 24 bent cards draw in about 4.4 ms at 1080p with the mesh, well inside a frame; a template with many more, or video in every card, needs measuring as it is built. Templates must keep playback at 60 fps.
- **Exports matching the canvas.** The spike showed sorting and both bends match; every new piece (shadows on bent cards, depth fade) gets a pixel test, as tilt has.
- **A private class.** The mesh is not Apple's public API. Twine is internal and already uses several; if it goes, bent cards draw flat.
- **Matching Animos's look.** We are reading their motion from watching it, not from their code. Each template is ours, made to feel like theirs, tuned by eye with you.
- **Animos's terms.** Their templates are their product. We build our own versions of the motion, under our own names, and draw nothing of theirs (no thumbnails or sample pictures).

## Decisions

All made on 17 October 2026.

1. **Live, not baked.** A template is a live frame whose settings stay changeable; Split into Layers turns it into ordinary layers and actions.
2. **The 23 most 3D first.** Milestone 5 builds 3D & Perspective (12), Isometric (3) and Orbit (8); the other 46 wait until those have been tried and judged.
3. **Depth is its own action.** A Depth action on its own channel, with its own timing and easing, as every other property has. Move stays flat, keeping its curved path on the canvas.
4. **Our own names.** Each template is named by us, in plain descriptive words (Ring, Tunnel, Globe), so nothing reads as Animos's product. The names in this document are Animos's, for reference.
5. **A bar for a template's length.** A template has a bar on the timeline, as a video's Play does, as long as the scene when it goes in and looping without a seam inside it. It can be shortened, moved or stretched to sit among other animation; stretching it slows the loop, as a preset's bar stretches its parts.

## Appendix: each template's settings in Animos

Read from animos.app/editor on 17 October 2026. Every template also has the background, slots, loop length, text and logo. "Easing" is the full easing list; "ratio" is the card ratio choice.

**3D & Perspective**
- Showcase Stream (12 slots): padding, corner radius, ring tilt -28°, ring opening 55%, ring size 80%, card size 21%, back fade 70%, perspective 18%, ratio, shadow.
- Sphere Wall (8): zoom 20%, tilt 0°, padding, corner radius, curvature (concave to convex) -100%, gap 5%, edge fade 0%, ratio, motion (Continuous, Waypoints, Waypoints without zoom), direction (Left, Right, Alternate).
- Card Globe (12): corner radius, globe size 70%, card size 20%, gap 2.5%, back fade 55%, tilt 0°, ratio, motion, direction.
- Orbit Globe (12): as Card Globe, globe size 50%, card size 28%, tilt 27°.
- Sphere Cascade (8): as Sphere Wall, direction Up, Down, Alternate.
- Totem Wall (8): zoom 33%, tilt, padding, corner radius, curvature -100%, gap 4.5%, edge fade, ratio, direction Up, Down, Alternate.
- Parallax Totem (8): zoom 50%, scatter 70%, size variation 30%, parallax depth 50%, padding, corner radius, curvature, gap 6.75%, edge fade, ratio, direction Up, Down.
- Card Tunnel (8): corner radius, tunnel size 90%, card length 55%, gap 10%, depth fade 45%, direction Forward, Backward.
- Spiral Stream (12): padding, corner radius, spiral turns 3.75, card count 24, spiral size 62%, taper 0%, card size 33%, back fade 55%, perspective 20%, ring tilt 0°, card gap 28%, scale pulse 0%, easing, direction Downward, Upward, motion (Continuous, Fast-slow-fast, Step per card), ratio, card style (Curved 3D bend, Upright flat), shadow.
- Depth Stack Scroll (12): corner radius, card size 25%, card count 24, depth gap 32%, spread 74%, wobble 0%, depth fade 45%, depth blur 0%, layout (Fan, Scatter), direction Forward, Backward, ratio, shadow.
- Cover Ring (8): padding, corner radius, card size 37%, ring size 131%, tilt 0°, perspective 55%, back fade 55%, easing, ratio, direction (Clockwise, Counter-clockwise), motion (Step per card, Continuous).
- Cover Ring Vertical (8): as Cover Ring with rotate 0°, direction Bottom to top, Top to bottom.

**Multiscene**
- Bloom Belt (8): corner radius, card size, spread, focus size, ring size (all 100%), flip direction, ratio, shadow.
- Lens Orbit (15): corner radius, card size 100%, lens strength 50%, focus size 115%, card gap -20%, flip direction, ratio, shadow.
- Stairway (15): corner radius, tile size 100%, grid gap 14%, stair gap 0%, camera zoom 100%, flip direction, ratio, shadow.
- Grid Dive (15): corner radius, tile size 100%, gap 8.5%, camera zoom 100%, flip direction, ratio, shadow.
- Pop Parade (15): corner radius, card size 100%, camera zoom 100%, flip direction, ratio, shadow.
- Triple Scene (12): corner radius, padding 2%, hero size 58%, hero spacing 4%, columns 3, cards per column 6, card gap 1.5%, column drift 22%, row tilt 17%, row rise 12%, easing, ratio, shadow.
- Collage Reel (8): corner radius, padding 2%, hero size 52%, easing, ratio, collage and reel sections, shadow.
- Fan Shuffle (18): corner radius, deck cards 6, fan spread 7.8%, fan angle -47°, columns 3, card gap 2.5%, row shift 77%, wall pull-back 80%, easing, ratio, shadow.
- Sweep Ring (8): padding, corner radius, row card size 60%, card gap 4%, deck depth 5%, ring card size 30%, ring size 36%, easing, ratio, shadow.
- Scatter Dial (8): padding, corner radius, scatter card size 30%, ring card size 30%, ring size 36%, easing, ratio, shadow.
- Grid Zoom Strip (9): padding, corner radius, zoom 2.0, gap 2%, fade, easing, direction (Horizontal, Vertical), zoom target (Start, Centre), movement (Smooth, Stepped), ratio (with Frame), shadow.
- Spread Rows (12): padding, corner radius, rows 3, row gap 3%, card gap 3%, stack size 50%, camera zoom 50%, drift 16%, row delay 4%, easing, stack style (Single point, Row edges), ratio, shadow.
- Spread Columns (12): as Spread Rows, by columns.

**Isometric**
- Iso Cascade (10): padding, corner radius, card size 42%, tilt 70%, spacing 40%, easing, ratio, motion (Continuous, Stepped), direction (four diagonals), shadow.
- Iso Focus (10): corner radius, card size 42%, tilt 20%, spacing 20%, focus gap 85%, centre scale 100%, easing, ratio, direction (Down-left, Up-right), shadow.
- Iso Orbit (9): padding, corner radius, zoom 85%, spacing 18%, tilt 55%, swing angle 30°, float 2.5%, motion (Swing, Full spin), ratio, shadow.

**Orbit**
- Orbit Showcase (12): padding, corner radius, pulse strength 60%, ring width 64%, ring depth 26%, ring tilt 0°, spread 100%, card size 22%, perspective 55%, back fade 45%, direction, motion (Linear, Fast-slow-fast), ratio, shadow.
- Orbit Bloom (12): as Orbit Showcase with lean to centre 0%, ring width 50%, ring depth 25%, ring tilt -29°, card size 24%, curve (out or in) 0%.
- Orbit Carousel (4): padding, corner radius, spread 70%, depth fade 60%, ratio (with Frame), shadow.
- Photo Orbit (8): padding, corner radius, pulse strength 60%, ring width 56%, ring height 56%, card size 26%, easing, direction, motion (Linear, Fast-slow-fast, Step per card), ratio, shadow.
- Focus Orbit (20): padding, corner radius, pulse strength 60%, zoom 2.4, spin stops 5, ring size 72%, rotate Y 0°, perspective 55%, card size 18%, easing, direction, motion (Smooth, Fast-slow-fast), zoom style (Overlap, Spotlight), rotate Y scope (Always, Zoom only), cards (Face front, Follow rotation), ratio, shadow.
- Vortex Spin (8): corner radius, rings 3, ring size 34%, card size 15%, depth 50%, back fade 35%, ratio, card style (Curved, Flat), direction (Clockwise, Counter-clockwise, Alternate).
- Wheel Spin (8): corner radius 5%, card size 26%, wheel size 92%, rotations a loop 1, direction, ratio, movement (Continuous, Stepped tick), spin style (Follow wheel, Self-rotate, 3D flip), shadow.
- Wheel Spin Bottom (8): as Wheel Spin, card size 20%, wheel size 50%, with easing.

**Carousel & Flow**
- Card Totem (6): corner radius, card size 34%, gap 2.5%, 3D curve (out or in) 70%, easing, ratio, motion (Continuous, Stop at centre).
- Film Strip (6): as Card Totem, card size 32%.
- Wheel Carousel (6): corner radius 5%, card size 70%, wheel size 105%, anticipation 20%, overshoot 10%, hold 33%, easing, direction, ratio, shadow.
- Cover Flow (5): padding, corner radius, card size 46%, gap 4%, side tilt 40°, flow angle 0°, easing, ratio, direction (Right to left, Left to right), motion (Stop at centre, Continuous).
- Cover Flow Vertical (5): as Cover Flow, no flow angle, direction Bottom to top, Top to bottom.
- Carousel Flow (5): padding, corner radius, side card scale 0.82, gap 5%, easing, direction (Horizontal, Vertical), ratio (with Frame), shadow.
- Diagonal Carousel (6): padding, corner radius, card size 40%, overlap 55%, easing, direction (four diagonals), movement (Continuous, Stepped), ratio, shadow.
- Focus Slider (8): padding, corner radius, card size 82%, centre scale 200%, zigzag offset 55%, gap 6%, slide portion 80%, easing, direction, ratio, zigzag mode (Alternate, Fixed), shadow.
- Mosaic Marquee (10): padding, corner radius, card height 55%, gap 3%, ratio, layout (1, 2, 3), direction (Left, Right), shadow.
- Hero Reel (7): padding, corner radius, active lift 1.8, active scale 108%, card spacing 2.0, hero opacity 55%, Ken Burns 60%, hold 55%, easing, background wipe, shadow.

**Grid**
- Grid Reveal (4): padding, corner radius, gap 3%, easing, reveal order (Rows, Columns, Diagonal), shadow.
- Spotlight Zoom (4): padding, corner radius, gap 3%, background dim 45%, easing, shadow.
- Flip Grid (8): padding, corner radius, gap 3%, easing, flip axis (Horizontal, Vertical), shadow.
- Pop Grid (6): padding, corner radius, gap 3%, visible share 62%.
- Ticker Loop (12): corner radius, zoom 45%, tilt -6°, row gap 4%, movement (Continuous, Zoom pulse, Zoom waypoints), orientation, direction (Opposed, Same way), ratio.
- Ticker Tilt (12): corner radius, zoom 32%, tilt 30°, perspective 60%, row gap 4%, easing, flow (Opposed, Same way, Staggered), direction (Left, Right), ratio.
- Column Drift (12): padding, corner radius, gap 3%, ratio.
- Feed Scroll (12): padding, corner radius, card size 52%, spacing 70%, lane spread 100%, flick length 55%, fade in 50%, stagger 0%, easing, motion (Flicks, Steady), card enters by (Fade, Slide), ratio, shadow.

**Spotlight & Focus**
- Center Stage (3): padding, corner radius, travel distance 60%, ghost trail, card size 86%, easing, shadow.
- Focus Shift (4): padding, corner radius, rail size 26%, gap 2.5%, easing, shadow.
- Deck Peel (4): corner radius, card size 48%, stack peek 4%, easing, ratio, shadow.
- Zoom Parallax (3): padding, corner radius, zoom amount 12%, easing, pan direction (Alternate, Left, Right).

**Reveal & Wipe**
- Diagonal Wipe (3): padding, corner radius, edge angle -20°, edge glow 60%, easing.
- Stripe Reveal (3): padding, corner radius, strips 7, easing.
- Split Reveal (4): padding, corner radius, split ratio 50%, gap 2%, easing, shadow.
- Mosaic Wipe (4): padding, corner radius, rows 4, columns 4, stagger 60%, speed variation 0%, easing, style (Grid, Blinds), pattern (Normal, Diagonal, Radial, Spiral, Random).

**Stack & Scatter**
- Stack Slide (4): padding, corner radius, card inset 4%, depth scale 0.95, easing, ratio (with Frame), shadow.
- Cascade Drop (4): padding, corner radius, rotation 100%, card size 78%, ratio (with Frame), shadow.
- Cascade Deck (8): padding, corner radius, card size 80%, overlap 70%, easing, motion (One by one, All together), ratio, shadow.
- Image Trail (12): corner radius 0%, card size 19%, trail length 18, pop from 50%, easing, ratio, shadow.
- Poster Burst (4): corner radius, hold time 30%, ratio (with Frame), flow (One by one, Staggered, Volley), shadow.
- Card Toss (8): padding, corner radius, card size 26%, size variation 20%, throw height 75%, horizontal spread 70%, spin 12°, ratio, flow (One by one, Staggered), shadow.
- Position Dance (6): padding, corner radius 4%, card size 28%, spacing 0%, easing, ratio, shadow.
