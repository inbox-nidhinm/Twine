import Testing
@testable import MotionEditing

@Suite struct NumberExpressionTests {
    @Test func plainNumbersReadAsThemselves() {
        #expect(NumberExpression.value(of: "120", from: 5) == 120)
        #expect(NumberExpression.value(of: " 12,5 ", from: 5) == 12.5)
        #expect(NumberExpression.value(of: "-10", from: 5) == -10)
        #expect(NumberExpression.value(of: ".5", from: 5) == 0.5)
    }

    @Test func sumsAreWorkedOut() {
        #expect(NumberExpression.value(of: "100+20", from: 0) == 120)
        #expect(NumberExpression.value(of: "1920/2", from: 0) == 960)
        #expect(NumberExpression.value(of: "(10+5)*2", from: 0) == 30)
        #expect(NumberExpression.value(of: "10+5*2", from: 0) == 20)
        #expect(NumberExpression.value(of: "10 - -5", from: 0) == 15)
    }

    @Test func aLeadingSignChangesTheNumberThere() {
        #expect(NumberExpression.value(of: "+10", from: 5) == 15)
        #expect(NumberExpression.value(of: "*2", from: 5) == 10)
        #expect(NumberExpression.value(of: "/2", from: 5) == 2.5)
        #expect(NumberExpression.value(of: "+-10", from: 5) == -5)
        let change = NumberExpression.change(in: "+10")
        #expect(change?(1) == 11)
        #expect(change?(40) == 50)
        #expect(NumberExpression.change(in: "10") == nil)
        #expect(NumberExpression.change(in: "-10") == nil)
    }

    @Test func whatIsNotANumberIsRefused() {
        for typed in ["", "abc", "10+", "(10", "10)", "1/0", "/0", "1e400", "++", "5 5", "１２"] {
            #expect(NumberExpression.value(of: typed, from: 5) == nil, "\(typed)")
        }
        // A long row of brackets stops, it does not run the stack out.
        #expect(NumberExpression.value(of: String(repeating: "(", count: 5000) + "1", from: 0) == nil)
    }
}
