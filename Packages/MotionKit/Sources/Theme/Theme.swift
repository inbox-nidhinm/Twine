import SwiftUI
import AppKit

/// Every colour, size, radius and type style in Twine, in one place.
///
/// Taken from the "Flip Design System" page of the JUI Figma file
/// (2XErpBfGuIGNU0DkL58Ute, node 171:2055), whose values in turn come from
/// Flip's `FlipTheme`. The one deliberate difference is the accent: Twine is
/// light blue where Flip is green, and the two tokens derived from the accent
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

    /// #4C9FEF. Everything that means *selected* or *in hand* reads this: rows,
    /// the tool in hand, and the canvas's outlines, handles and marquee. One
    /// constant, so they cannot disagree. The inspector's controls stay out of
    /// it (they use `chosen`), so the panel reads as one quiet surface.
    public static let accent = Color(red: 0x4C / 255, green: 0x9F / 255, blue: 0xEF / 255)
    /// The accent under the pointer. Lighter rather than darker, because a
    /// step down would read as disabled.
    public static let accentHover = Color(red: 0x6E / 255, green: 0xB3 / 255, blue: 0xF3 / 255)
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
    /// The playhead: its line down the timeline and the pill in the ruler
    /// that carries the time. Teal, so it never reads as a selection.
    public static let playhead = Color(red: 0x2B / 255, green: 0x88 / 255, blue: 0x85 / 255)
    /// A layer under the pointer on the canvas: a white line on a dark edge
    /// over a faint white wash. Black and white together show on artwork of
    /// any colour, grey included, and never read as a selection.
    public static let canvasHover = Color.white
    public static let canvasHoverEdge = Color.black
    /// The stand-in shape that plays each preset in the preset picker: light,
    /// as a layer on the canvas would be, on the tile's raised grey.
    public static let previewShape = Color(white: 0.86)
    /// Smart guides and equal-spacing marks while something snaps.
    public static let guide = Color(red: 0xF2 / 255, green: 0x4E / 255, blue: 0x6B / 255)

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
    /// The shadow under every floating card.
    public static let shadow = Color.black.opacity(0.4)
    public static let shadowRadius: CGFloat = 12
    public static let shadowY: CGFloat = 4

    /// How strongly surfaces take their grain. 1 is the artwork as drawn.
    public static let grain: Double = 1

    // MARK: Sizes (size/*)

    /// Every pressable thing in a panel is this tall.
    public static let control: CGFloat = 24
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

    // MARK: Widths (width/*)

    public static let panelWidth: CGFloat = 232
    public static let labelWidth: CGFloat = 58
    public static let cardWidth: CGFloat = 240
    public static let menuMinWidth: CGFloat = 168

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
    public static let exportTitle: CGFloat = 32
    /// The counter's type size, as a share of the preview area's height.
    public static let exportCounterShare: CGFloat = 0.36
    /// How the player and the counter trade places: cubic-bezier(0.5, 0, 0, 1).
    public static let exportEase = Animation.timingCurve(0.5, 0, 0, 1, duration: 0.8)
    /// How the counter slides from one number to the next, on the same curve.
    public static let counterEase = Animation.timingCurve(0.5, 0, 0, 1, duration: 0.4)
    /// The panel appearing and going.
    public static let exportFade = Animation.timingCurve(0.5, 0, 0, 1, duration: 0.35)
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
    /// The document name.
    public static let title = Font.system(size: 13, weight: .semibold)
    /// Tiny numbers on tiles and markers.
    public static let micro = Font.system(size: 8, weight: .medium)

    /// PP Kyoto, for the home screen's titles and the export panel's name
    /// (Light) and its counter (Thin).
    public enum DisplayWeight: String, CaseIterable, Sendable {
        case light = "PPKyoto-Light"
        case thin = "PPKyoto-Thin"
    }

    /// The display face. Registered with the process at first use rather
    /// than through the Info.plist, because the fonts ship inside this
    /// package's resource bundle. If registration fails, `Font.custom` falls
    /// back to the system face, which costs a different-looking title rather
    /// than a crash.
    public static func display(_ size: CGFloat, _ weight: DisplayWeight = .light) -> Font {
        _ = registered
        return .custom(weight.rawValue, size: size)
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

    private static func nsFont(_ size: CGFloat, _ weight: DisplayWeight) -> NSFont? {
        _ = registered
        return NSFont(name: weight.rawValue, size: size)
    }

    private static let registered: Bool = {
        DisplayWeight.allCases.map { weight in
            guard let url = Bundle.module.url(forResource: weight.rawValue, withExtension: "otf", subdirectory: "Fonts")
            else { return false }
            return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }.allSatisfy { $0 }
    }()
}

extension View {
    /// The display face at 130% leading, in one call.
    public func displayTitle(_ size: CGFloat) -> some View {
        font(ThemeFont.display(size)).lineSpacing(ThemeFont.displayLeading(size))
    }
}
