import SwiftUI
import AppKit

/// Every colour, size, radius and type style in Twine, in one place.
///
/// The DialKit look (the `dialkit` branch, 26 November 2026): values from the
/// "dialkit" page of the Twine Figma file (RRnath7INm7WH7CGLOfLdH, node
/// 448:436), which took them from DialKit's own stylesheet (joshpuckett/dialkit,
/// `src/styles/theme.css`). DialKit's surfaces are white at low opacity over
/// its glass (#212121); where a token must be one solid colour it is that
/// white already laid over the glass, so it reads the same on a panel. The
/// accent stays Twine's blue. The Flip look this replaced is kept on the
/// `archive/flip-look` branch and the `flip-look-v0.2.80` tag.
///
/// Views read these and never write a literal. If a view needs a value that is
/// not here, it belongs here first.
public enum Theme {

    // MARK: Surfaces (surface/*, border/*)

    /// #1E1E1E (dial/canvas). The canvas round the artboard.
    public static let canvas = Color(red: 0x1E / 255, green: 0x1E / 255, blue: 0x1E / 255)
    /// #212121 (dial/glass). Every floating card.
    public static let panel = Color(red: 0x21 / 255, green: 0x21 / 255, blue: 0x21 / 255)
    /// #2C2C2C (dial/surface, white at 5% over the glass). Every row: fields,
    /// sliders, menus, toggles, trays; and hover over `panel`.
    public static let panelRaised = Color(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2C / 255)
    /// #373737 (dial/surface-hover, white at 10%). A row under the pointer.
    public static let panelHover = Color(red: 0x37 / 255, green: 0x37 / 255, blue: 0x37 / 255)
    /// White at 10% (dial/border). The edge of every card.
    public static let border = Color.white.opacity(0.10)
    /// White at 6% (dial/surface-subtle). The rule between a panel's sections.
    public static let rule = Color.white.opacity(0.06)
    /// #2A2A2A (dial/dropdown). An open menu's card.
    public static let dropdown = Color(red: 0x2A / 255, green: 0x2A / 255, blue: 0x2A / 255)
    /// White at 60% (dial/focus-ring). The line round a field being typed in.
    public static let focus = Color.white.opacity(0.6)
    /// A hairline over colour the theme does not control: a swatch, a well, a
    /// thumbnail, the inside of a track. Translucent so it reads on anything.
    public static let edge = Color.white.opacity(0.12)
    /// `edge` under the pointer. On a control whose fill *is* a colour, the
    /// hairline is the only part that can answer a hover without lying.
    public static let edgeHover = Color.white.opacity(0.32)

    // MARK: Accent (accent/*, row/*)

    /// #217FD8. The thing selected itself reads this: the canvas's outlines,
    /// handles and marquee, and a selected bar on the timeline. Rows that
    /// list it (layers panel, timeline labels) use `rowSelected`, and what
    /// is chosen among controls (the tool in hand, the inspector's segments)
    /// uses `chosen`, so the accent is only ever the selection.
    public static let accent = Color(red: 0x21 / 255, green: 0x7F / 255, blue: 0xD8 / 255)
    /// #4D99E0, the accent under the pointer: a fifth of the way to white.
    /// Lighter rather than darker, because a step down would read as disabled.
    public static let accentHover = Color(red: 0x4D / 255, green: 0x99 / 255, blue: 0xE0 / 255)
    /// #33506C. A selected row. Mixed by eye rather than as the accent at some
    /// opacity over `panel`, which comes out greyer than the accent reads.
    public static let rowSelected = Color(red: 0x33 / 255, green: 0x50 / 255, blue: 0x6C / 255)
    /// #434343 (dial/surface-active over a row). What is chosen inside the
    /// inspector: a segment, the tool in hand. Grey rather than the accent,
    /// so settings never compete with the selection on the canvas.
    public static let chosen = Color(red: 0x43 / 255, green: 0x43 / 255, blue: 0x43 / 255)
    /// `chosen` under the pointer, and a switch that is on (dial/border-hover
    /// over a row).
    public static let chosenHover = Color(red: 0x4C / 255, green: 0x4C / 255, blue: 0x4C / 255)
    /// A slider's filled part (dial/surface-active), and while it drags
    /// (dial/border-hover). Laid over the row, so translucent.
    public static let sliderFill = Color.white.opacity(0.11)
    public static let sliderFillActive = Color.white.opacity(0.15)
    /// A slider's handle (3 by 20), shown under the pointer or while dragging.
    public static let sliderHandle = Color.white.opacity(0.95)
    /// The row that is current without being selected.
    public static let rowCurrent = accent.opacity(0.22)
    /// A row under the pointer (dial/surface).
    public static let rowHover = Color.white.opacity(0.05)
    /// A template's tile on Home's New from Template screen, and under the pointer.
    public static let templateTile = Color(red: 0x41 / 255, green: 0x41 / 255, blue: 0x41 / 255)
    public static let templateTileHover = Color(red: 0x4A / 255, green: 0x4A / 255, blue: 0x4A / 255)
    /// The playhead: its line down the timeline and its handle in the
    /// ruler, white as DialKit's slider handle, so it never reads as a
    /// selection. The time it is at sits beside the play controls.
    public static let playhead = Color.white.opacity(0.95)
    /// The ruler's ticks between its numbers (dial/border-hover).
    public static let rulerTick = Color.white.opacity(0.15)
    /// A timeline track: the strip each row's bars run along (dial/surface).
    public static let track = Color.white.opacity(0.05)
    /// The stand-in shape that plays each preset in the preset picker: light,
    /// as a layer on the canvas would be, on the tile's raised grey.
    public static let previewShape = Color(white: 0.86)
    /// Smart guides and equal-spacing marks while something snaps.
    public static let guide = Color(red: 0xF2 / 255, green: 0x4E / 255, blue: 0x6B / 255)
    /// A timeline bar that is not selected (dial/clip, white at 20%).
    public static let clip = Color.white.opacity(0.20)
    /// A timeline scene's own colour: its span bar and the line down its
    /// rows (#2E5575, the user's choice), a deep blue apart from the light
    /// blue of a selection. Scenes have no row colour: the bar is enough.
    public static let timelineScene = Color(red: 0x2E / 255, green: 0x55 / 255, blue: 0x75 / 255)
    /// Where each of a scene's actions runs, shown faintly inside its bar.
    public static let timelineSceneRun = Color.white.opacity(0.18)

    // MARK: Text (text/*)

    /// White at 95% (dial/text-primary): values and names.
    public static let textPrimary = Color.white.opacity(0.95)
    /// White at 70% (dial/text-label): every row's name, and section titles.
    public static let textSecondary = Color.white.opacity(0.70)
    /// White at 40% (dial/text-tertiary). Placeholders, readouts, disabled.
    public static let textTertiary = Color.white.opacity(0.40)
    /// A field's name and unit inside its box (X, W, px, %), as DialKit's
    /// labels inside a row: dial/text-label.
    public static let fieldLabel = Color.white.opacity(0.70)
    /// The panel's own title (dial/text-root).
    public static let textRoot = Color.white
    /// Text drawn on a white fill, such as a slider readout once the fill
    /// reaches it.
    public static let textOnFill = Color(white: 0.32)

    // MARK: Controls (control/*, overlay/*)

    /// The white pill in sliders and toggles.
    public static let thumb = Color.white
    /// The small bar on a pill that says it can be dragged.
    public static let grip = Color(white: 0.72)
    /// Behind numbers laid over artwork.
    public static let badge = Color.black.opacity(0.55)
    /// Words and glyphs on a coloured fill: the tool in hand, a segment
    /// that is on, the Export button, the playhead's time, a guide's gap.
    public static let textOnColor = Color.white
    /// The canvas's handles and points and a timeline bar's trim handles:
    /// white, so they read over artwork of any colour.
    public static let handle = Color.white
    /// The ring round the colour picker's markers, and its soft shadow,
    /// together readable on any colour.
    public static let pickerRing = Color.white
    public static let pickerRingShadow = Color.black.opacity(0.3)
    /// Over the ruler and the tracks after the composition ends.
    public static let pastTheEnd = Color.black.opacity(0.22)
    /// The checkerboard that stands for transparency: its two greys and
    /// the side of a square.
    public static let checkerDark = Color(white: 0.42)
    public static let checkerLight = Color(white: 0.52)
    public static let checkerCell: CGFloat = 8
    /// A dividing line, and the cards' header rows under which one runs:
    /// floating cards (the easing card, popups) and the larger sheets
    /// (Version History, Keyboard Shortcuts).
    public static let hairline: CGFloat = 1
    public static let cardHeader: CGFloat = 40
    public static let sheetHeader: CGFloat = 38
    /// Extra space between the lines of running text in a sheet (Version
    /// History's points): 11 pt text at about 155% of its size, 17 pt lines
    /// where the system font's own are 14 (measured on screen).
    public static let readingLineSpacing: CGFloat = 3
    /// The steps of running text in a sheet, from the smallest: between two
    /// points, and a heading and its first; between sections; a build's
    /// title and what it says; one build and the next.
    public static let readingItemGap: CGFloat = 10
    public static let readingSectionGap: CGFloat = 22
    public static let readingTitleGap: CGFloat = 14
    public static let readingBlockGap: CGFloat = 44
    /// How far a sheet's close button sits in from the right: as far as it
    /// sits down from the top, so the cross reads as tucked into the corner.
    /// The sheet's own side inset left it twice as far in as down.
    public static let sheetCloseInset: CGFloat = (sheetHeader - control) / 2
    /// The bar on a slider's or a switch's pill that says it drags.
    public static let gripWidth: CGFloat = 2
    public static let gripHeight: CGFloat = 10
    public static let radiusGrip: CGFloat = 1
    /// Round a menu's items, and round the anchor picker's dots.
    public static let menuPad: CGFloat = 4
    /// A row's small icon buttons (eye, lock, a field's clear button), and
    /// the layers panel's disclosure chevron.
    public static let rowIconButton: CGFloat = 22
    public static let disclosure: CGFloat = 14
    /// How far above and below an edge it can be grabbed to resize.
    public static let resizeEdge: CGFloat = 6
    /// The shadow under every floating card: DialKit's 0 8 32 at 50%. A CSS
    /// blur is twice SwiftUI's radius.
    public static let shadow = Color.black.opacity(0.5)
    public static let shadowRadius: CGFloat = 16
    public static let shadowY: CGFloat = 8

    /// How strongly surfaces take their grain. DialKit's glass is flat, so none.
    public static let grain: Double = 0

    // MARK: Sizes (size/*)

    /// Every row in a panel is this tall: a field, a slider, a menu, a
    /// toggle, a button with a word (dial/row-height).
    public static let control: CGFloat = 36
    /// A small glyph button in a row or a header (add, remove, the eye), and
    /// the colour well beside a hex.
    public static let glyph: CGFloat = 24
    /// The small curve beside an easing's name.
    public static let easingGlyph = CGSize(width: 10, height: 20)
    /// The swatch at the right of a fill's or a stroke's row.
    public static let swatch: CGFloat = 20
    /// A hex typed into a fill's or a stroke's row, at its right.
    public static let hexField: CGFloat = 64
    /// The round button a folded panel leaves at the window's corner.
    public static let foldedPanel: CGFloat = 44
    /// A DialKit switch: its track and the round thumb inside it.
    public static let toggleWidth: CGFloat = 36
    public static let toggleHeight: CGFloat = 20
    public static let toggleThumb: CGFloat = 16
    /// A slider's handle, shown under the pointer or while dragging.
    public static let sliderHandleWidth: CGFloat = 3
    public static let sliderHandleHeight: CGFloat = 20
    /// The inset of a row's name from its left, and of its value from its
    /// right (DialKit's 10 and 12).
    public static let labelInset: CGFloat = 10
    public static let valueInset: CGFloat = 12
    /// How far typed text is lifted in its box, in screen pixels: AppKit's
    /// text field sets its line about half a point lower than a label, so
    /// a number looked low beside a menu's word (a whole pixel on a 1x
    /// screen).
    public static let fieldTextLift: CGFloat = 1
    /// A button with a word on it, and a section's header row: one row.
    public static let button: CGFloat = control
    /// Tools and other mode switches: the big square button.
    public static let modeButton: CGFloat = 36
    /// The box an icon is drawn in.
    public static let icon: CGFloat = 20
    /// The grid icon artwork is drawn on.
    public static let iconGrid: CGFloat = 24
    /// An icon's line, on its grid: it scales with the icon, so a 20 pt icon
    /// draws a 1.6 pt line and a 15 pt one a 1.2 pt line. The artwork is
    /// drawn at 1.5; the app draws it heavier.
    public static let iconStroke: CGFloat = 1.92
    /// The tick in a checkbox, a little heavier than other icons.
    public static let checkStroke: CGFloat = 2.56
    public static let panelRow: CGFloat = control
    public static let listRow: CGFloat = 32
    public static let barRow: CGFloat = 40
    /// The box of a check mark.
    public static let checkbox: CGFloat = 14
    /// Slider tracks: the whole row.
    public static let trackHeight: CGFloat = control
    /// A picture's thumbnail in the inspector: as tall as two rows of
    /// controls with the gap between them.
    public static let pictureWell: CGFloat = panelRow + rowGap + button

    /// A gradient stop's marker on the inspector's gradient bar, and the
    /// picked one's, taller so it reads as picked without colour.
    public static let gradientMarker: CGFloat = 10
    public static let gradientMarkerPicked: CGFloat = 16
    /// The picked gradient stop's place, beside the gradient bar.
    public static let stopField: CGFloat = 52
    /// The card the anchor button raises, and a dot of the nine on the button.
    public static let anchorCard: CGFloat = 132
    public static let anchorDot: CGFloat = 3
    /// Home's search field and sort menu, beside the New buttons.
    public static let homeSearch: CGFloat = 168
    public static let homeSort: CGFloat = 112
    /// An ellipse's Sweep and Ratio, joined to its Start in one box.
    public static let arcSweepField: CGFloat = 76
    public static let arcRatioField: CGFloat = 64
    /// The opacity joined to a fill's or stroke's hex on its one row.
    public static let paintOpacity: CGFloat = 68

    // MARK: Radii (radius/*)

    /// dial/radius-panel, dial/radius, dial/radius-inner.
    public static let radiusPanel: CGFloat = 14
    public static let radiusControl: CGFloat = 8
    public static let radiusTrack: CGFloat = 8
    public static let radiusRow: CGFloat = 6
    public static let radiusTray: CGFloat = 6
    public static let radiusMenu: CGFloat = 10
    public static let radiusWell: CGFloat = 6
    public static let radiusSwatchMark: CGFloat = 2
    /// A bar in the timeline: an action's, or a scene's span.
    public static let radiusBar: CGFloat = 6

    /// A button's corner, scaled with its box so buttons of different sizes
    /// still look like one family.
    public static func radius(forButton size: CGFloat) -> CGFloat { max(radiusRow, size * 0.22) }

    // MARK: Spacing (space/*)

    /// The spacing scale: gaps and insets that have no role of their own,
    /// named by their size in points. Views take these in place of bare
    /// numbers, so every gap in the app is one of a known few (26 November
    /// 2026, when about two hundred were still written as numbers). A gap
    /// with a role (a panel's inset, a bar's, a tray's) has its own name
    /// below.
    public static let space1: CGFloat = 1
    public static let space2: CGFloat = 2
    public static let space3: CGFloat = 3
    public static let space4: CGFloat = 4
    public static let space5: CGFloat = 5
    public static let space6: CGFloat = 6
    public static let space7: CGFloat = 7
    public static let space8: CGFloat = 8
    public static let space10: CGFloat = 10
    public static let space12: CGFloat = 12
    public static let space14: CGFloat = 14
    public static let space16: CGFloat = 16
    public static let space20: CGFloat = 20
    public static let space44: CGFloat = 44

    /// Line weights: `hairline` (1) for edges and rules, `line` for outlines
    /// that must be seen (a focus ring, a drop target, the canvas's own
    /// handles), `lineHeavy` for marks and rings, `lineShade` for the dark
    /// line under a gradient's.
    public static let line: CGFloat = 1.5
    public static let lineHeavy: CGFloat = 2
    public static let lineShade: CGFloat = 3

    /// Icon boxes smaller than `icon`: in rows and lists, and the smallest,
    /// for ticks and chevrons.
    public static let iconRow: CGFloat = 15
    public static let iconSmall: CGFloat = 13


    /// What every panel insets its contents by.
    public static let panelPad: CGFloat = 12
    /// The inspector's button column, one button wide, and the gap before
    /// it. Every row's controls stop short of it; a button that acts on a
    /// row sits in it, level with the row (the user's grid, 28 September
    /// 2026).
    public static let columnGap: CGFloat = 8
    public static let rowGutter: CGFloat = glyph + columnGap
    /// How far a small button's box sits from the panel's right edge: closer
    /// than `panelPad`, because the box is wider than its glyph. Section
    /// headers' add and remove buttons and the button column share it, so
    /// every button in the inspector lines up.
    public static let buttonInset: CGFloat = panelPad - 4
    /// Card to window edge.
    public static let floatInset: CGFloat = 8
    /// Card to card.
    public static let floatGap: CGFloat = 8
    /// Inside a tray of mode buttons.
    public static let trayPad: CGFloat = 2
    /// Inside the bottom bar.
    public static let barPad: CGFloat = 6
    public static let barGap: CGFloat = 4
    /// Between the timeline's play controls.
    public static let transportGap: CGFloat = 8
    /// The timeline's play controls: smaller than other bar buttons.
    public static let transportButton: CGFloat = 20
    public static let transportIcon: CGFloat = 16
    /// Between rows (dial/row-gap).
    public static let rowGap: CGFloat = 6
    /// The thickness of a progress bar.
    public static let progressBar: CGFloat = 4
    /// The ring a notice shows while work is under way, and its line.
    public static let loader: CGFloat = 14
    public static let loaderLine: CGFloat = 2

    // MARK: Widths (width/*)

    /// dial/panel-width.
    public static let panelWidth: CGFloat = 280
    public static let labelWidth: CGFloat = 72
    /// The Text section's right-hand column (size, and Auto or Fixed), so
    /// the weight menu and the alignment tray get the rest.
    public static let textSideColumn: CGFloat = 76
    public static let cardWidth: CGFloat = 280
    /// How tall the easing card's grid of tiles is before it scrolls.
    public static let easingGridHeight: CGFloat = 468
    public static let menuMinWidth: CGFloat = 168

    /// The ⌘K search card: its width, how far down the window it sits, its
    /// search row, a result's row, the tallest its list grows before it
    /// scrolls, and a project's picture in a row.
    public static let searchWidth: CGFloat = 560
    public static let searchTop: CGFloat = 96
    public static let searchField: CGFloat = 46
    public static let searchRow: CGFloat = 34
    public static let searchList: CGFloat = 392
    public static let searchThumb = CGSize(width: 36, height: 24)

    /// The bottom bar's full height: one bar row inside its padding.
    public static let barHeight: CGFloat = barRow + barPad * 2

    // MARK: Export panel

    /// The settings column down the panel's left: the layers panel's width,
    /// so its edge falls where the layers panel's does.
    public static let exportColumn: CGFloat = panelWidth
    /// The blue button that exports, in the panel and the inspector.
    public static let primaryButton: CGFloat = 36
    /// The preview's play button.
    public static let previewButton: CGFloat = 40
    /// The gap between the preview and its controls.
    public static let previewGap: CGFloat = 24
    /// The project's name at the head of the panel.
    public static let exportTitle: CGFloat = 24
    /// The counter's type size, as a share of the preview area's height.
    public static let exportCounterShare: CGFloat = 0.36
    /// The onboarding card, as Flip's: its size, the panel down its left
    /// (the artwork takes the rest), the panel's inset, the title's size and
    /// the buttons at its foot.
    public static let onboardingCard = CGSize(width: 760, height: 540)
    public static let onboardingPanel: CGFloat = 290
    public static let onboardingPad: CGFloat = 24
    public static let onboardingTitle: CGFloat = 21
    public static let onboardingButton: CGFloat = 28
    public static let onboardingRow: CGFloat = 30
    public static let onboardingFolderRow: CGFloat = 34
    /// The size the onboarding's artwork is drawn at, in its own pixels, and
    /// the folder's name in it: its type size and its baseline from the top,
    /// as the designer set it under the folder.
    public static let onboardingArtwork = CGSize(width: 746, height: 886)
    public static let onboardingFolderName: CGFloat = 38
    public static let onboardingFolderBaseline: CGFloat = 651
    public static let radiusCard: CGFloat = 14
    /// The home screen's Info card on a project: its width, which its
    /// thumbnail spans.
    public static let infoCardWidth: CGFloat = 340
    /// Home's New from Template screen: a panel of the groups beside a
    /// panel of the chosen group's tiles, each a picture of the template
    /// over its name, as many across as fit at this width or wider. The
    /// screen takes these shares of the window (the user's choice, 19
    /// October 2026).
    public static let templateGalleryWidthShare: CGFloat = 0.75
    public static let templateGalleryHeightShare: CGFloat = 0.8
    public static let templateTileWidth: CGFloat = 196
    public static let templateTileHeight: CGFloat = 240
    public static let templateTileGap: CGFloat = 16
    /// The name's inset from a tile's left and bottom.
    public static let templateTileInset: CGFloat = 16
    public static let templateGalleryPad: CGFloat = 20
    public static let templateGalleryHeader: CGFloat = 50
    public static let templateGalleryGap: CGFloat = 24
    /// The groups' panel, as wide as Home's sidebar.
    public static let templateSidebarWidth: CGFloat = panelWidth - floatInset * 2
    /// The Settings page's cards: the narrowest a column of them may be
    /// (three side by side when the window has room, else two), a row's
    /// height, the icon tile at a row's left, the width of a menu or number
    /// at its right, the dashes between rows, and Version History's button.
    public static let settingsCardMin: CGFloat = 320
    /// Between cards, across and down.
    public static let settingsCardGap: CGFloat = 32
    public static let settingsRow: CGFloat = 48
    public static let settingsTile: CGFloat = 32
    public static let settingsTileIcon: CGFloat = 16
    public static let settingsControl: CGFloat = 150
    public static let settingsDash: [CGFloat] = [3, 3]
    public static let settingsButton: CGFloat = 140
    /// Under the onboarding card, darker while a page turns.
    public static let onboardingShadow = Color.black
    /// How the player and the counter trade places: cubic-bezier(0.5, 0, 0, 1).
    public static let exportEase = Animation.timingCurve(0.5, 0, 0, 1, duration: 0.8)
    /// How the counter slides from one number to the next, on the same curve.
    public static let counterEase = Animation.timingCurve(0.5, 0, 0, 1, duration: 0.4)
    /// The panel appearing and going.
    public static let exportFade = Animation.timingCurve(0.5, 0, 0, 1, duration: 0.35)
    /// The tool bar's hover highlight sliding from one tool to the next.
    public static let hoverGlide = Animation.timingCurve(0.5, 0, 0, 1, duration: 0.28)
    /// How long a highlight waits after the pointer leaves one tool before
    /// fading, so passing to the next slides it rather than fading it out and in.
    public static let hoverLinger: Double = 0.06
}

// MARK: - Type

/// The type styles, by their names in Figma ("Dial/..."). SF Pro throughout,
/// except the display face on the home screen.
public enum ThemeFont {
    /// Every label, value, menu row and tool name (Dial/Label, Dial/Value).
    public static let label = Font.system(size: 13, weight: .medium)
    /// Section headings and popup card titles (Dial/Section).
    public static let labelStrong = Font.system(size: 13, weight: .semibold)
    /// Readout values and secondary lines (Dial/Small).
    public static let caption = Font.system(size: 11, weight: .medium)
    /// The unit letter inside a unit field: a row's name, as DialKit's.
    public static let unit = Font.system(size: 13, weight: .medium)
    /// What is typed into the ⌘K search card, and its results.
    public static let search = Font.system(size: 14)
    public static let searchResult = Font.system(size: 12)
    /// The document name and a panel's own title (Dial/Root).
    public static let title = Font.system(size: 15, weight: .semibold)
    /// A template's name on its tile on Home's New from Template screen.
    public static let tileName = Font.system(size: 13)
    /// Tiny numbers on tiles and markers.
    public static let micro = Font.system(size: 8, weight: .medium)

    /// AA Bridge Slab, for the home screen's titles and the export panel's name
    /// (Light) and its counter (Extra Light). The value is the weight on the
    /// font's own axis, which runs from 100 (Thin) to 700 (Bold).
    public enum DisplayWeight: CGFloat, CaseIterable, Sendable {
        case light = 300
        case extraLight = 200
    }

    /// The display face. On the dialkit branch every title is SF Pro, as the
    /// DialKit page sets them (Dial/Page Title, Semibold): `light` titles
    /// are Semibold, the export counter's `extraLight` is Light. On main,
    /// AA Bridge Slab is one variable font, set here to the
    /// weight and to the optical size matching the size it is drawn at, as a
    /// browser does, so large titles get its finer display cut. It ships
    /// inside this package's resource bundle and is registered with the
    /// process at first use rather than through the Info.plist, and is always
    /// made from that file, never looked up by name, as the name of its
    /// default instance is no weight Twine uses. If that fails, the system's
    /// serif shows, which costs a different-looking title rather than a crash.
    public static func display(_ size: CGFloat, _ weight: DisplayWeight = .light) -> Font {
        Font(nsFont(size, weight) as CTFont)
    }

    /// The widest digit of the display face at `size`, so a counter's
    /// digit keeps one width whichever digit shows.
    public static func displayDigitWidth(_ size: CGFloat, _ weight: DisplayWeight = .light) -> CGFloat {
        let font = nsFont(size, weight)
        return (0...9).map { ("\($0)" as NSString).size(withAttributes: [.font: font]).width }.max() ?? size * 0.62
    }

    /// How tall the display face's figures stand at `size`, and how far to
    /// move a line of them down so the figures, not the line, sit centred in
    /// a box of that height.
    public static func displayFigures(_ size: CGFloat, _ weight: DisplayWeight = .light) -> (height: CGFloat, nudge: CGFloat) {
        let font = nsFont(size, weight)
        // Measured down from the top of a line's box, which runs from the
        // ascender to the descender: the box's middle, and the middle of the
        // figures, which stand from the baseline to the cap height.
        let boxMiddle = (font.ascender - font.descender) / 2
        let figureMiddle = font.ascender - font.capHeight / 2
        return (font.capHeight, boxMiddle - figureMiddle)
    }

    /// The gap to add between lines so the display face sits on 130% leading.
    public static func displayLeading(_ size: CGFloat) -> CGFloat {
        let font = nsFont(size, .light)
        let natural = font.ascender - font.descender + font.leading
        return max(0, size * 1.3 - natural)
    }

    /// The title face at `size` and `weight`: SF Pro.
    private static func nsFont(_ size: CGFloat, _ weight: DisplayWeight) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight == .light ? .semibold : .light)
    }

    /// AA Bridge Slab at `size` and `weight`, as main draws its titles, kept
    /// for going back to it; nil when it could not be loaded.
    private static func slabFont(_ size: CGFloat, _ weight: DisplayWeight) -> NSFont? {
        guard let face else { return nil }
        // The axes by their four-letter tags, which Core Text keys by number.
        // The optical size axis runs from 16 to 144.
        let wght = 0x7767_6874, opsz = 0x6F70_737A
        let variation = [wght: weight.rawValue, opsz: min(max(size, 16), 144)] as CFDictionary
        let set = CTFontDescriptorCreateWithAttributes([kCTFontVariationAttribute: variation] as CFDictionary)
        return CTFontCreateCopyWithAttributes(face, size, nil, set) as NSFont
    }

    /// Core Text fonts never change once made, so one is safe to share.
    nonisolated(unsafe) private static let face: CTFont? = {
        guard let url = Bundle.module.url(forResource: "AABridgeSlab", withExtension: "ttf", subdirectory: "Fonts"),
              CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil),
              let found = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = found.first
        else { return nil }
        return CTFontCreateWithFontDescriptor(first, 12, nil)
    }()
}

extension View {
    /// The display face at 130% leading, in one call.
    public func displayTitle(_ size: CGFloat) -> some View {
        font(ThemeFont.display(size)).lineSpacing(ThemeFont.displayLeading(size))
    }
}
