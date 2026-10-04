import Foundation
import Testing
@testable import MotionModel

/// Project files from anyone: names that reach outside the package and
/// numbers past what Twine can draw are brought back as the file is read.
@Suite struct FileSafetyTests {
    /// `project` written out, with each sentinel number in the JSON swapped
    /// for the text given, as a hand-edited or hostile file would have it.
    private func decode(_ project: Project, swapping swaps: [(String, String)]) throws -> Project {
        var json = String(decoding: try ProjectFormat.encode(project), as: UTF8.self)
        for (from, to) in swaps {
            #expect(json.contains(from), "sentinel \(from) missing")
            json = json.replacingOccurrences(of: from, with: to)
        }
        return try ProjectFormat.decode(Data(json.utf8))
    }

    @Test func mediaNamesWithAPathPointNowhere() throws {
        let inside = MediaAsset(kind: .image, fileName: "B1E2.png", originalName: "a.png", contentHash: "a")
        var project = Project(media: [inside])
        for name in ["../../../Pictures/private.jpg", "/etc/hosts", "..", ".hidden.png", "a/b.mov", "", "x:y.png"] {
            project.media.append(MediaAsset(kind: .image, fileName: name, originalName: "x", contentHash: name))
        }
        let read = try ProjectFormat.decode(try ProjectFormat.encode(project))
        #expect(read.media[0].fileName == "B1E2.png")
        for asset in read.media.dropFirst() {
            #expect(FileSafety.isPlainName(asset.fileName))
            #expect(asset.fileName.hasPrefix(asset.id.uuidString))
        }
        #expect(read.media[1].fileName == read.media[1].id.uuidString + ".jpg")
        #expect(read.media[3].fileName == read.media[3].id.uuidString)
    }

    @Test func hugeNumbersAreHeldInRange() throws {
        let sound = MediaAsset(kind: .audio, fileName: "s.wav", originalName: "s.wav", contentHash: "h", duration: 4.125)
        let audio = Layer(name: "S", content: .audio(AudioContent(mediaID: sound.id)), size: Size2(0, 0), position: .zero)
        let text = Layer(name: "T", content: .text(TextContent(text: "1e400 stays words", fontSize: 47.5)),
                         size: Size2(10, 10), position: Vec2(123.25, 0))
        let star = Layer(name: "Star", content: .shape(ShapeContent(geometry: .star(points: 7, innerRadius: 0.4, cornerRadius: 0))),
                         size: Size2(10, 10), position: .zero)
        let poly = Layer(name: "Poly", content: .shape(ShapeContent(geometry: .polygon(sides: 9))),
                         size: Size2(10, 10), position: .zero)
        let fade = Action(target: audio.id, start: 1.375, duration: 2.875, spec: .volume(VolumeAction(end: 0)))
        let project = Project(composition: Composition(width: 1234, height: 567, duration: 6.625),
                              layers: [audio, text, star, poly], actions: [fade], media: [sound])
        let read = try decode(project, swapping: [
            ("\"width\" : 1234", "\"width\" : 1e300"), ("\"height\" : 567", "\"height\" : -99999999999999999999999"),
            ("6.625", "1e400"),
            ("1.375", "-1e300"), ("2.875", "1E+300"), ("4.125", "123456789012345"),
            ("47.5", "1e300"), ("123.25", "-1e300"), ("\"points\" : 7", "\"points\" : 1e15"),
            ("\"sides\" : 9", "\"sides\" : 9000000000000"),
        ])
        #expect(read.composition.width == FileSafety.largestComposition)
        #expect(read.composition.height == 1)
        #expect(read.composition.duration == Composition.longest)
        #expect(read.actions[0].start == 0)
        #expect(read.actions[0].duration == Composition.longest)
        #expect(read.media[0].duration == Composition.longest)
        guard case .text(let t) = read.layers[1].content else { Issue.record("not text"); return }
        #expect(t.fontSize == FileSafety.fontSizes.upperBound)
        #expect(t.text == "1e400 stays words")
        #expect(read.layers[1].transform.position.x == -FileSafety.limit)
        #expect(read.layers[2].look?.geometry == .star(points: FileSafety.maxCorners, innerRadius: 0.4, cornerRadius: 0))
        #expect(read.layers[3].look?.geometry == .polygon(sides: FileSafety.maxCorners))
    }

    @Test func numbersInRangeAreNotCopied() throws {
        let data = try ProjectFormat.encode(kitchenSinkProject())
        #expect(FileSafety.numbersHeld(data) == data)
        // Long fractions, small exponents and numbers in strings are fine.
        let fine = Data(#"{"a": 0.30000000000000004, "b": 1.2246467991473532e-16, "c": "9999999999999", "d": "\"1e400\"", "e": 1e9}"#.utf8)
        #expect(FileSafety.numbersHeld(fine) == fine)
        let wild = Data(#"{"a": 1e10, "b": "1e10", "c": -12345678901.5, "d": 2.5e-1}"#.utf8)
        #expect(String(decoding: FileSafety.numbersHeld(wild), as: UTF8.self)
                == #"{"a": 1000000000, "b": "1e10", "c": -1000000000, "d": 2.5e-1}"#)
    }

    @Test func wholeNumbersFromDoublesNeverStopTheApp() {
        #expect(Int(saturating: .nan) == 0)
        #expect(Int(saturating: .infinity) > 1_000_000_000_000)
        #expect(Int(saturating: -.infinity) < -1_000_000_000_000)
        #expect(Int(saturating: 1e300) > 0)
        #expect(Int(saturating: 41.0) == 41)
    }
}

@Suite struct AngularGradientTests {
    @Test func anAngularGradientRoundTrips() throws {
        let g = Gradient(stops: [GradientStop(position: 0, color: .black), GradientStop(position: 1, color: .white)],
                         start: Vec2(0.5, 0.5), end: Vec2(1, 0.25))
        let layer = Layer(name: "A", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                                 fills: [Fill(paint: .angularGradient(g))])),
                          size: Size2(10, 10), position: .zero)
        let project = Project(layers: [layer])
        #expect(try ProjectFormat.decode(try ProjectFormat.encode(project)) == project)
        #expect(Paint.angularGradient(g).gradientKind == .angular && Paint.angularGradient(g).gradient == g)
        #expect(Paint.solid(.black).withGradient(g) == .linearGradient(g))
        #expect(Paint.angularGradient(g).withGradient(g) == .angularGradient(g))
    }
}
