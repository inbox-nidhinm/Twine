import SwiftUI
import AppKit

/// Every colour, size, radius and type style in Twine, in one place.
///
/// Taken from the "Flip Design System" page of the JUI Figma file
/// (2XErpBfGuIGNU0DkL58Ute, node 171:2055), whose values in turn come from
/// Flip's `FlipTheme`. The one deliberate difference is the accent: Twine is
/// blue where Flip is green, and the two tokens derived from the accent
/// (`rowSelected`, `accentHover`) are re-derived to match.
///
/// Views read these and never write a literal. If a view needs a value that is
/// not here, it belongs here first.
public enum Theme {

    // MARK: Surfaces (surface/*, border/*)

    /// #1E1E1E. The canvas, and the track inside sliders and toggles.
    public static let canvas = Color(red: 0x1E / 255, green: 0x1E / 255, blue: 0x1E / 255)
    /// #2C2C2C. Every floating card.
    public static let panel = Color(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2C / 255)
    /// #383838. Fields, trays, and hover over `panel`.
    public static let panelRaised = Color(red: 0x38 / 255, green: 0x38 / 255, blue: 0x38 / 255)
    /// #484848. Hover over something already on `panelRaised`: the next rung of
    /// the same ramp, so a hover on a tray still shows.
    public static let panelHover = Color(red: 0x48 / 255, green: 0x48 / 255, blue: 0x48 / 255)
    /// #424242. Rules, and the edge of every card.
    public static let border = Color(red: 0x42 / 255, green: 0x42 / 255, blue: 0x42 / 255)
    /// A hairline over colour the theme does not control: a swatch, a well, a
    /// thumbnail, the inside of a track. Translucent so it reads on anything.
    public static let edge = Color.white.opacity(0.12)
    /// `edge` under the pointer. On a control whose fill *is* a colour, the
    /// hairline is the only part that can answer a hover without lying.
    public static let edgeHover = Color.white.opacity(0.32)

    // MARK: Accent (accent/*, row/*)

    /// #217FD8. Everything that means *selected* or *in hand* reads this: rows,
    /// the tool in hand, and the canvas's outlines, handles and marquee. One
    /// constant, so they cannot disagree. The inspector's controls stay out of
    /// it (they use `chosen`), so the panel reads as one quiet surface.
    public static let accent = Color(red: 0x21 / 255, green: 0x7F / 255, blue: 0xD8 / 255)
    /// #4D99E0, the accent under the pointer: a fifth of the way to white.
    /// Lighter rather than darker, because a step down would read as disabled.
    public static let accentHover = Color(red: 0x4D / 255, green: 0x99 / 255, blue: 0xE0 / 255)
    /// #33506C. A selected row. Mixed by eye rather than as the accent at some
    /// opacity over `panel`, which comes out greyer than the accent reads.
    public static let rowSelected = Color(red: 0x33 / 255, green: 0x50 / 255, blue: 0x6C / 255)
    /// #5C5C5C. What is chosen inside the inspector: a segment, a switch that
    /// is on. Grey rather than the accent, so settings never compete with the
    /// selection on the canvas for attention.
    public static let chosen = Color(red: 0x5C / 255, green: 0x5C / 255, blue: 0x5C / 255)
    /// `chosen` under the pointer: a step lighter, as `accentHover` is.
    public static let chosenHover = Color(red: 0x68 / 255, green: 0x68 / 255, blue: 0x68 / 255)
    /// The row that is current without being selected.
    public static let rowCurrent = accent.opacity(0.22)
    /// A row under the pointer. Translucent so the grain shows through.
    public static let rowHover = Color.white.opacity(0.057)
    /// A template's tile on Home's New from Template screen, and under the pointer.
    public static let templateTile = Color(red: 0x41 / 255, green: 0x41 / 255, blue: 0x41 / 255)
    public static let templateTileHover = Color(red: 0x4A / 255, green: 0x4A / 255, blue: 0x4A / 255)
    /// The playhead: its line down the timeline and the pill in the ruler
    /// that carries the time. Teal, so it never reads as a selection.
    public static let playhead = Color(red: 0x2B / 255, green: 0x88 / 255, blue: 0x85 / 255)
    /// The stand-in shape that plays each preset in the preset picker: light,
    /// as a layer on the canvas would be, on the tile's raised grey.
    public static let previewShape = Color(white: 0.86)
    /// Smart guides and equal-spacing marks while something snaps.
    public static let guide = Color(red: 0xF2 / 255, green: 0x4E / 255, blue: 0x6B / 255)
    /// A timeline scene's own colour: its span bar and the line down its
    /// rows (#2E5575, the user's choice), a deep blue apart from the light
    /// blue of a selection. Scenes have no row colour: the bar is enough.
    public static let timelineScene = Color(red: 0x2E / 255, green: 0x55 / 255, blue: 0x75 / 255)

    // MARK: Text (text/*)

    public static let textPrimary = Color.white
    public static let textSecondary = Color(white: 0.70)
    /// Placeholders, units, readouts, disabled.
    public static let textTertiary = Color(white: 0.50)
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
    public static let cardHeader: CGFloat = 34
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
    /// The shadow under every floating card.
    public static let shadow = Color.black.opacity(0.4)
    public static let shadowRadius: CGFloat = 12
    public static let shadowY: CGFloat = 4

    /// How strongly surfaces take their grain. 1 is the artwork as drawn.
    public static let grain: Double = 1

    // MARK: Sizes (size/*)

    /// Every pressable thing in a panel is this tall.
    public static let control: CGFloat = 24
    /// How far typed text is lifted in its box, in screen pixels: AppKit's
    /// text field sets its line about half a point lower than a label, so
    /// a number looked low beside a menu's word (a whole pixel on a 1x
    /// screen).
    public static let fieldTextLift: CGFloat = 1
    /// A button with a glyph and a word. One step up from `control`.
    public static let button: CGFloat = control + 8
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
    public static let panelRow: CGFloat = 24
    public static let listRow: CGFloat = 32
    public static let barRow: CGFloat = 40
    /// The box of a check mark.
    public static let checkbox: CGFloat = 14
    /// Slider and toggle tracks.
    public static let track: CGFloat = 26
    /// A picture's thumbnail in the inspector: as tall as two rows of
    /// controls with the gap between them.
    public static let pictureWell: CGFloat = panelRow + 4 + 6 + button

    /// A gradient stop's marker on the inspector's gradient bar, and the
    /// picked one's, taller so it reads as picked without colour.
    public static let gradientMarker: CGFloat = 10
    public static let gradientMarkerPicked: CGFloat = 16
    /// The picked gradient stop's place, beside the gradient bar.
    public static let stopField: CGFloat = 52

    // MARK: Radii (radius/*)

    public static let radiusPanel: CGFloat = 10
    public static let radiusControl: CGFloat = 5
    public static let radiusTrack: CGFloat = 7
    public static let radiusRow: CGFloat = 4
    public static let radiusTray: CGFloat = 4
    public static let radiusMenu: CGFloat = 8
    public static let radiusWell: CGFloat = 8
    public static let radiusSwatchMark: CGFloat = 2

    /// A button's corner, scaled with its box so buttons of different sizes
    /// still look like one family.
    public static func radius(forButton size: CGFloat) -> CGFloat { max(radiusControl, size * 0.2) }

    // MARK: Spacing (space/*)

    /// What every panel insets its contents by.
    public static let panelPad: CGFloat = 12
    /// The inspector's button column, one button wide, and the gap before
    /// it. Every row's controls stop short of it; a button that acts on a
    /// row sits in it, level with the row (the user's grid, 28 September
    /// 2026).
    public static let columnGap: CGFloat = 8
    public static let rowGutter: CGFloat = control + columnGap
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
    public static let rowGap: CGFloat = 4
    /// The thickness of a progress bar.
    public static let progressBar: CGFloat = 4
    /// The ring a notice shows while work is under way, and its line.
    public static let loader: CGFloat = 14
    public static let loaderLine: CGFloat = 2

    // MARK: Widths (width/*)

    public static let panelWidth: CGFloat = 232
    public static let labelWidth: CGFloat = 58
    /// The Text section's right-hand column (size, and Auto or Fixed), so
    /// the weight menu and the alignment tray get the rest.
    public static let textSideColumn: CGFloat = 76
    public static let cardWidth: CGFloat = 240
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
    public static let radiusCard: CGFloat = 12
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

/// The type styles, by their names in Figma. SF Pro throughout, except the
/// display face on the home screen.
public enum ThemeFont {
    /// Every label, value, menu row and tool name.
    public static let label = Font.system(size: 11)
    /// Section headings and popup card titles.
    public static let labelStrong = Font.system(size: 11, weight: .semibold)
    /// Readout values and secondary lines.
    public static let caption = Font.system(size: 10)
    /// The unit letter inside a unit field.
    public static let unit = Font.system(size: 10, weight: .medium)
    /// What is typed into the ⌘K search card, and its results.
    public static let search = Font.system(size: 14)
    public static let searchResult = Font.system(size: 12)
    /// The document name.
    public static let title = Font.system(size: 13, weight: .semibold)
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

    /// The display face. AA Bridge Slab is one variable font, set here to the
    /// weight and to the optical size matching the size it is drawn at, as a
    /// browser does, so large titles get its finer display cut. It ships
    /// inside this package's resource bundle and is registered with the
    /// process at first use rather than through the Info.plist, and is always
    /// made from that file, never looked up by name, as the name of its
    /// default instance is no weight Twine uses. If that fails, the system's
    /// serif shows, which costs a different-looking title rather than a crash.
    public static func display(_ size: CGFloat, _ weight: DisplayWeight = .light) -> Font {
        guard let font = nsFont(size, weight) else { return .system(size: size, weight: .light, design: .serif) }
        return Font(font as CTFont)
    }

    /// The widest digit of the display face at `size`, so a counter's
    /// digit keeps one width whichever digit shows.
    public static func displayDigitWidth(_ size: CGFloat, _ weight: DisplayWeight = .light) -> CGFloat {
        guard let font = nsFont(size, weight) else { return size * 0.62 }
        return (0...9).map { ("\($0)" as NSString).size(withAttributes: [.font: font]).width }.max() ?? size * 0.62
    }

    /// How tall the display face's figures stand at `size`, and how far to
    /// move a line of them down so the figures, not the line, sit centred in
    /// a box of that height.
    public static func displayFigures(_ size: CGFloat, _ weight: DisplayWeight = .light) -> (height: CGFloat, nudge: CGFloat) {
        guard let font = nsFont(size, weight) else { return (size * 0.72, 0) }
        // Measured down from the top of a line's box, which runs from the
        // ascender to the descender: the box's middle, and the middle of the
        // figures, which stand from the baseline to the cap height.
        let boxMiddle = (font.ascender - font.descender) / 2
        let figureMiddle = font.ascender - font.capHeight / 2
        return (font.capHeight, boxMiddle - figureMiddle)
    }

    /// The gap to add between lines so the display face sits on 130% leading.
    public static func displayLeading(_ size: CGFloat) -> CGFloat {
        guard let font = nsFont(size, .light) else { return size * 0.3 }
        let natural = font.ascender - font.descender + font.leading
        return max(0, size * 1.3 - natural)
    }

    /// The display face at `size` and `weight`, or nil when it could not be
    /// loaded.
    private static func nsFont(_ size: CGFloat, _ weight: DisplayWeight) -> NSFont? {
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
