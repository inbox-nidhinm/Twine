import Foundation

/// A project file is held to what Twine can draw and keep before anything
/// uses it, since a file can come from anyone (4 October 2026). JSON allows
/// numbers far past what a whole number can hold, and turning one of those
/// into a count of pixels, points or steps stops the app; a media file's
/// name is joined onto the package's `media` folder, so a name with a path
/// in it reached files outside the package, read them as pictures and
/// copied them into the next save.
public enum FileSafety {
    /// The largest number a file may use, as for imports
    /// (`SVGNumber.limit`): far past any real design, and small enough that
    /// sums and products of such numbers stay countable.
    public static let limit = 1e9
    /// The widest and tallest composition, as the inspector allows.
    public static let largestComposition = 16_384
    /// Type sizes a file may set: the inspector allows 1 to 2,000, and
    /// imports may go further.
    public static let fontSizes: ClosedRange<Double> = 1...10_000
    /// The most sides a polygon or points a star may have, as the inspector
    /// and Figma imports allow.
    public static let maxCorners = 60

    /// Whether `name` is a plain file name, which can only name a file
    /// directly inside the folder it is joined onto: not empty, no folders,
    /// not hidden, and no longer than a file name may be.
    public static func isPlainName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 255 && !name.hasPrefix(".")
            && !name.contains("/") && !name.contains(":") && !name.contains("\0")
    }

    /// The widest or tallest picture taken in from inside another file (an
    /// SVG's or a Figma paste's), and the most pixels: a picture of a few
    /// kilobytes can claim a size that takes gigabytes to show, every time
    /// the project opens. Figma itself keeps pictures to 4,096 a side.
    public static let largestPictureSide = 16_384
    public static let mostPicturePixels = 100_000_000

    /// Whether a picture `width` by `height` pixels may come in.
    public static func pictureFits(width: Double, height: Double) -> Bool {
        width.isFinite && height.isFinite && width >= 1 && height >= 1
            && max(width, height) <= Double(largestPictureSide) && width * height <= Double(mostPicturePixels)
    }

    /// The largest picture file Twine takes in at all (4 October 2026).
    /// Larger than `pictureFits` allows, it is drawn shrunk to fit
    /// (`pictureDrawingScale`), which keeps a big photo usable; past these
    /// even shrinking it takes seconds and gigabytes as it is read, every
    /// time the project opens, so it is refused.
    public static let largestPictureFileSide = 65_535
    public static let mostPictureFilePixels = 400_000_000

    /// Whether a picture file `width` by `height` pixels may come in.
    public static func pictureFileFits(width: Double, height: Double) -> Bool {
        width.isFinite && height.isFinite && width >= 1 && height >= 1
            && max(width, height) <= Double(largestPictureFileSide) && width * height <= Double(mostPictureFilePixels)
    }

    /// How much a picture `width` by `height` pixels is shrunk when drawn,
    /// so it is within `pictureFits`: 1 for every picture already within.
    public static func pictureDrawingScale(width: Double, height: Double) -> Double {
        guard width >= 1, height >= 1, width.isFinite, height.isFinite else { return 1 }
        return min(1, Double(largestPictureSide) / max(width, height), (Double(mostPicturePixels) / (width * height)).squareRoot())
    }

    /// A polygon's sides or a star's points as Twine draws them.
    public static func corners(_ count: Int) -> Int { min(max(count, 3), maxCorners) }

    /// The JSON with every number past `limit` (or past what a double holds)
    /// written as `limit`, keeping its sign. Only numbers that could be that
    /// large are read: those with ten or more whole digits or a positive
    /// exponent. Text in strings is left alone. Nothing is copied when every
    /// number is in range, which is every file Twine wrote. Project files,
    /// Figma pastes and Twine's own clipboard all come through it.
    public static func numbersHeld(_ data: Data) -> Data {
        var edits: [(range: Range<Int>, negative: Bool)] = []
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let n = raw.count
            var i = 0
            var inString = false
            while i < n {
                let c = raw[i]
                if inString {
                    if c == 0x5C { i += 2; continue }       // a backslash escapes what follows
                    if c == 0x22 { inString = false }
                    i += 1
                    continue
                }
                if c == 0x22 { inString = true; i += 1; continue }
                guard c == 0x2D || (0x30...0x39).contains(c) else { i += 1; continue }
                let start = i
                var whole = 0, inWhole = true, exponent = false, positiveExponent = false
                while i < n {
                    let d = raw[i]
                    if (0x30...0x39).contains(d) {
                        if inWhole { whole += 1 }
                    } else if d == 0x2E {
                        inWhole = false
                    } else if d == 0x65 || d == 0x45 {
                        inWhole = false
                        exponent = true
                        positiveExponent = i + 1 >= n || raw[i + 1] != 0x2D
                    } else if d != 0x2B && d != 0x2D {
                        break
                    }
                    i += 1
                }
                guard whole > 9 || (exponent && positiveExponent) else { continue }
                let text = String(decoding: UnsafeRawBufferPointer(rebasing: raw[start..<i]), as: UTF8.self)
                // Malformed numbers are left for the decoder to refuse.
                guard let value = Double(text), !(value.isFinite && abs(value) <= limit) else { continue }
                edits.append((start..<i, value < 0))
            }
        }
        guard !edits.isEmpty else { return data }
        var out = Data(capacity: data.count)
        var from = data.startIndex
        for edit in edits {
            let range = (data.startIndex + edit.range.lowerBound)..<(data.startIndex + edit.range.upperBound)
            out.append(data[from..<range.lowerBound])
            out.append(contentsOf: (edit.negative ? "-1000000000" : "1000000000").utf8)
            from = range.upperBound
        }
        out.append(data[from...])
        return out
    }
}

extension Project {
    /// The project with what a file could carry out of range brought back:
    /// the composition's size and length, actions' times and motion blur,
    /// media files' names and lengths, type sizes, and polygon and star
    /// corners. Everything Twine itself writes comes through unchanged.
    public func heldInRange() -> Project {
        var p = self
        let biggest = FileSafety.largestComposition
        p.composition.width = min(max(p.composition.width, 1), biggest)
        p.composition.height = min(max(p.composition.height, 1), biggest)
        p.composition.duration = FileSafety.time(p.composition.duration)
        p.actions = FileSafety.held(p.actions)
        p.media = p.media.map { asset in
            var m = asset
            if !FileSafety.isPlainName(m.fileName) {
                // A name pointing anywhere else becomes the asset's own,
                // which the package does not have: the layer shows grey.
                let ext = (m.fileName as NSString).pathExtension
                let plain = !ext.isEmpty && ext.count <= 8 && ext.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
                m.fileName = m.id.uuidString + (plain ? "." + ext : "")
            }
            m.duration = m.duration.map(FileSafety.time)
            return m
        }
        p.layers = FileSafety.held(p.layers)
        return p
    }
}

extension FileSafety {
    static func time(_ t: Double) -> Double { min(max(t, 0), Composition.longest) }

    /// Actions with their times within a day and motion blur within a frame.
    public static func held(_ actions: [Action]) -> [Action] {
        actions.map { action in
            var a = action
            a.start = time(a.start)
            a.duration = time(a.duration)
            a.motionBlur = a.motionBlur.map { min(max($0, 0), 1) }
            return a
        }
    }

    /// Layers, and everything inside them, with type sizes in `fontSizes`
    /// and polygon and star corners within `maxCorners`.
    public static func held(_ layers: [Layer]) -> [Layer] {
        layers.map { layer in
            var l = layer
            switch l.content {
            case .text(var text):
                guard !fontSizes.contains(text.fontSize) else { break }
                text.fontSize = min(max(text.fontSize, fontSizes.lowerBound), fontSizes.upperBound)
                l.content = .text(text)
            case .shape(var shape):
                switch shape.geometry {
                case .polygon(let sides, let corner) where corners(sides) != sides:
                    shape.geometry = .polygon(sides: corners(sides), cornerRadius: corner)
                case .star(let points, let inner, let corner) where corners(points) != points:
                    shape.geometry = .star(points: corners(points), innerRadius: inner, cornerRadius: corner)
                default:
                    break
                }
                l.content = .shape(shape)
            case .group:
                l.children = held(l.children)
            case .video, .audio:
                break
            }
            return l
        }
    }
}

extension Int {
    /// The whole number nearest `value`, held to what an `Int` can hold
    /// (zero for not-a-number), where `Int(value)` would stop the app.
    public init(saturating value: Double) {
        guard !value.isNaN else { self = 0; return }
        let edge = 9.0e18
        self = Int(Swift.min(Swift.max(value, -edge), edge))
    }
}
