import Foundation
import Testing
import MotionModel
@testable import MotionEvaluation

private func label(_ text: String, sizing: TextSizing = .autoWidth, width: Double = 100,
                   alignment: TextAlignment = .left) -> Layer {
    let content = TextContent(text: text, fontFamily: "SF Pro", fontSize: 40, color: .black, alignment: alignment,
                              sizing: sizing)
    let size = TextLayout.size(of: text, style: TextStyle(content), width: sizing == .fixedWidth ? width : nil)
    return Layer(name: "Label", content: .text(content), size: size, position: Vec2(500, 500))
}

private func action(_ layer: Layer, _ spec: ActionSpec, at start: Double = 1, for duration: Double = 1) -> Action {
    Action(target: layer.id, start: start, duration: duration, easing: .linear, spec: spec)
}

private func shown(_ layer: Layer, _ actions: [Action], at time: Double) -> ShownText? {
    ActionTracks(actions).state(of: layer, at: time).text
}

private func resolvedText(_ layer: Layer, _ actions: [Action], at time: Double) -> (ResolvedLayer, ResolvedText)? {
    let resolved = evaluate(Project(layers: [layer], actions: actions), at: time).layers[0]
    guard case .text(let t) = resolved.content else { return nil }
    return (resolved, t)
}

@Suite struct NumberFormatTests {
    @Test func readsCurrencyWithSeparators() throws {
        let (format, value) = try #require(NumberFormat.read("$1,200.50"))
        #expect(value == 1200.5)
        #expect(format.prefix == "$" && format.suffix == "" && format.decimals == 2)
        #expect(format.groupingSeparator == "," && format.decimalSeparator == ".")
        #expect(format.text(for: 98765.4) == "$98,765.40")
    }

    @Test func readsEuropeanNumbers() throws {
        let (format, value) = try #require(NumberFormat.read("1.200,50 €"))
        #expect(value == 1200.5 && format.suffix == " €")
        #expect(format.text(for: 3000) == "3.000,00 €")
    }

    @Test func keepsZeroPadding() throws {
        let (format, value) = try #require(NumberFormat.read("Agent 007"))
        #expect(value == 7 && format.prefix == "Agent ")
        #expect(format.text(for: 42) == "Agent 042")
    }

    @Test func tellsDecimalsFromThousands() throws {
        #expect(try #require(NumberFormat.read("3.5")).format.decimals == 1)
        #expect(try #require(NumberFormat.read("1,000")).format.groupingSeparator == ",")
        #expect(try #require(NumberFormat.read("50%")).format.suffix == "%")
        #expect(try #require(NumberFormat.read("-12 degrees")).value == -12)
        #expect(NumberFormat.read("no numbers here") == nil)
    }
}

@Suite struct CounterTests {
    @Test func countsThroughTheTextsOwnFormat() {
        let layer = label("Users: 0")
        let a = action(layer, .counter(CounterAction(to: 100)))
        #expect(shown(layer, [a], at: 0)?.text == "Users: 0")
        #expect(shown(layer, [a], at: 1.5)?.text == "Users: 50")
        #expect(shown(layer, [a], at: 2)?.text == "Users: 100")
        #expect(shown(layer, [a], at: 1.5)?.isCounting == true)
    }

    @Test func anExplicitFromShowsBeforeItStarts() {
        let layer = label("$0.00")
        let a = action(layer, .counter(CounterAction(from: 10, to: 20)))
        #expect(shown(layer, [a], at: 0)?.text == "$10.00")
    }

    @Test func stepsAreWholeAndTheEndIsExact() {
        let layer = label("0")
        let a = action(layer, .counter(CounterAction(to: 25, step: 10)))
        #expect(shown(layer, [a], at: 1.5)?.text == "10")
        #expect(shown(layer, [a], at: 1.99)?.text == "20")
        #expect(shown(layer, [a], at: 2)?.text == "25")
        let down = action(layer, .counter(CounterAction(from: 10, to: 0)))
        #expect(shown(layer, [down], at: 1.5)?.text == "5")
    }

    @Test func slidingCountsRollBetweenNumbers() throws {
        let layer = label("0")
        let a = action(layer, .counter(CounterAction(to: 10, transition: .slide)))
        let mid = try #require(shown(layer, [a], at: 1.55))
        let swap = try #require(mid.swap)
        #expect(swap.previous == "5" && mid.text == "6")
        #expect(abs(swap.inProgress - 0.5) < 1e-6 && swap.transitionIn == .slide)
    }
}

@Suite struct ChangeTextTests {
    @Test func outThenIn() throws {
        let layer = label("Hello")
        let a = action(layer, .changeText(ChangeTextAction(text: "World")))
        #expect(shown(layer, [a], at: 0.5)?.text == "Hello")
        let early = try #require(shown(layer, [a], at: 1.25))
        #expect(early.visible == "Hello" && early.swap?.outProgress == 0.5 && early.swap?.inProgress == 0)
        let late = try #require(shown(layer, [a], at: 1.75))
        #expect(late.visible == "World" && late.swap?.outProgress == 1 && late.swap?.inProgress == 0.5)
        #expect(shown(layer, [a], at: 2)?.swap == nil)
    }

    @Test func overlappingRunsBothAtOnce() throws {
        let layer = label("Hello")
        let a = action(layer, .changeText(ChangeTextAction(text: "World", overlaps: true)))
        let mid = try #require(shown(layer, [a], at: 1.5)?.swap)
        #expect(mid.outProgress == 0.5 && mid.inProgress == 0.5)
    }

    @Test func changesChainAndCountersPickUpTheNewText() {
        let layer = label("Hello")
        let change = action(layer, .changeText(ChangeTextAction(text: "Score 5")), at: 0, for: 0)
        let count = action(layer, .counter(CounterAction(to: 15)), at: 1, for: 1)
        #expect(shown(layer, [change, count], at: 0.5)?.text == "Score 5")
        #expect(shown(layer, [change, count], at: 1.5)?.text == "Score 10")
    }
}

@Suite struct TextSizeTests {
    @Test func aTextBoxFitsItsWords() throws {
        let short = TextLayout.size(of: "Hi", style: TextStyle(fontFamily: "SF Pro", fontWeight: 400, fontSize: 40,
                                                               alignment: .left, letterSpacing: 0, lineHeight: nil), width: nil)
        let long = TextLayout.size(of: "Hi there", style: TextStyle(fontFamily: "SF Pro", fontWeight: 400, fontSize: 40,
                                                                    alignment: .left, letterSpacing: 0, lineHeight: nil), width: nil)
        #expect(long.width > short.width && long.height == short.height)
        let two = TextLayout.size(of: "Hi\nthere", style: TextStyle(fontFamily: "SF Pro", fontWeight: 400, fontSize: 40,
                                                                     alignment: .left, letterSpacing: 0, lineHeight: 50), width: nil)
        #expect(two.height == 100)
    }

    @Test func fixedWidthWrapsDownwards() {
        let layer = label("one two three four five six", sizing: .fixedWidth, width: 120)
        #expect(layer.size.width == 120 && layer.size.height > 100)
    }

    @Test func letterSpacingWidensTheBoxFromItsLeftEdge() throws {
        let layer = label("Wide")
        let a = action(layer, .letterSpacing(LetterSpacingAction(end: 20)))
        let (before, _) = try #require(resolvedText(layer, [a], at: 0))
        let (after, t) = try #require(resolvedText(layer, [a], at: 2))
        #expect(t.letterSpacing == 20)
        #expect(after.size.width > before.size.width + 50)
        // Left-aligned text keeps its left edge where it was.
        let scene = { (time: Double) in evaluate(Project(layers: [layer], actions: [a]), at: time) }
        let leftBefore = try #require(scene(0).worldCorners(of: layer.id))[0].x
        let leftAfter = try #require(scene(2).worldCorners(of: layer.id))[0].x
        #expect(abs(leftBefore - leftAfter) < 1e-6)
    }

    @Test func centredTextGrowsBothWays() throws {
        let layer = label("Mid", alignment: .center)
        let a = action(layer, .changeText(ChangeTextAction(text: "Much longer", transitionOut: .none, transitionIn: .none)),
                       at: 1, for: 0)
        let scene = { (time: Double) in evaluate(Project(layers: [layer], actions: [a]), at: time) }
        let before = try #require(scene(0).worldCorners(of: layer.id)), after = try #require(scene(2).worldCorners(of: layer.id))
        #expect(abs((before[0].x + before[1].x) / 2 - (after[0].x + after[1].x) / 2) < 1e-6)
    }

    @Test func lineHeightStartsFromTheFontsOwn() throws {
        let layer = label("Line")
        let natural = try #require(LayerState(design: layer).lineHeight)
        #expect(natural > 40 && natural < 60)
        let a = action(layer, .lineHeight(LineHeightAction(end: 100)))
        let (after, _) = try #require(resolvedText(layer, [a], at: 2))
        #expect(after.size.height == 100)
    }

    @Test func aMissingFontFallsBack() {
        let style = TextStyle(fontFamily: "No Such Family 123", fontWeight: 400, fontSize: 40, alignment: .left,
                              letterSpacing: 0, lineHeight: nil)
        #expect(!TextLayout.isInstalled(style.fontFamily))
        #expect(TextLayout.size(of: "Text", style: style, width: nil).width > 0)
    }
}

@Suite struct ShapeActionTests {
    @Test func aSliceIsAWedgeAndARingHasAHole() {
        let wedge = ShapePaths.ellipse(Size2(100, 100), arc: EllipseArc(start: 0, end: 90))
        // The wedge ends at the centre before closing.
        #expect(wedge.subpaths[0].points.last?.position == Vec2(50, 50))
        let ring = ShapePaths.ellipse(Size2(100, 100), arc: EllipseArc(innerRadius: 0.5))
        #expect(ring.subpaths.count == 2)
        let full = ShapePaths.ellipse(Size2(100, 100), arc: .full)
        #expect(full == ShapePaths.ellipse(Size2(100, 100)))
    }

    @Test func arcsAnimate() {
        let layer = Layer(name: "E", content: .shape(ShapeContent(geometry: .ellipse(arc: .full))), size: Size2(100, 100),
                          position: .zero)
        let a = action(layer, .arc(ArcAction(end: EllipseArc(start: 0, end: 180))))
        #expect(ActionTracks([a]).state(of: layer, at: 1.5).arc == EllipseArc(start: 0, end: 270))
    }

    @Test func starsRoundAndChangeAWholePointAtATime() {
        let sharp = ShapePaths.star(Size2(100, 100), points: 5, innerRadius: 0.4)
        let round = ShapePaths.star(Size2(100, 100), points: 5, innerRadius: 0.4, cornerRadius: 6)
        #expect(round.subpaths[0].points.count == sharp.subpaths[0].points.count * 2)
        let layer = Layer(name: "S", content: .shape(ShapeContent(geometry: .star(points: 5, innerRadius: 0.4, cornerRadius: 0))),
                          size: Size2(100, 100), position: .zero)
        let a = action(layer, .star(StarAction(end: StarShape(points: 8, innerRadius: 0.4))))
        #expect(ActionTracks([a]).state(of: layer, at: 1.4).star?.points == 6)
    }
}
