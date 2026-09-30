import Foundation

/// Writes an animated GIF a frame at a time, so a long export never holds
/// more than a frame or two: the system's own GIF writer keeps every frame
/// until the end, 4 GB for eight seconds at 1080p.
///
/// Each frame gets its own palette of up to 255 colours (median cut over a
/// histogram of the pixels it draws), the 256th being see-through. Where a
/// pixel falls between palette colours, as in a gradient, it is dithered in
/// a fixed pattern, which holds still from frame to frame rather than
/// crawling; flat colour is left clean. On an opaque background only what
/// changed since the last frame is drawn, in the box around it, with
/// everything else see-through so the last frame shows through: motion
/// graphics GIFs come out a fraction of the size. On a transparent
/// background every frame is drawn whole, pixels under half opaque being
/// see-through, since a GIF has no partial transparency.
final class GIFWriter {
    let width: Int
    let height: Int
    let transparent: Bool

    private let handle: FileHandle
    /// The last frame's pixels as given, for finding what changed.
    private var previous: [UInt32]?
    private var bytes = Data()

    static let clearIndex: UInt8 = 255

    init(url: URL, width: Int, height: Int, transparent: Bool) throws {
        self.width = width
        self.height = height
        self.transparent = transparent
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw ExportError.failed("The GIF couldn't be created.")
        }
        handle = try FileHandle(forWritingTo: url)
        bytes.append(contentsOf: Array("GIF89a".utf8))
        put16(width); put16(height)
        // No global palette; every frame brings its own.
        bytes.append(contentsOf: [0x70, 0, 0])
        // Loops for ever.
        bytes.append(contentsOf: [0x21, 0xFF, 0x0B])
        bytes.append(contentsOf: Array("NETSCAPE2.0".utf8))
        bytes.append(contentsOf: [0x03, 0x01, 0x00, 0x00, 0x00])
        try flush()
    }

    /// One frame of premultiplied BGRA pixels, top row first, shown for
    /// `delay` hundredths of a second.
    func add(_ base: UnsafeRawPointer, bytesPerRow: Int, delay: Int) throws {
        var pixels = [UInt32](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { out in
            for row in 0..<height {
                out.baseAddress!.advanced(by: row * width * 4).copyMemory(from: base + row * bytesPerRow, byteCount: width * 4)
            }
        }
        if !transparent {
            // Opaque, whatever Core Animation left in the alpha byte.
            for i in pixels.indices { pixels[i] |= 0xFF00_0000 }
        } else {
            unpremultiply(&pixels)
        }

        // What to draw: on an opaque background, the box round what changed.
        var box = (x0: 0, y0: 0, x1: width - 1, y1: height - 1)
        var drawn = [Bool](repeating: true, count: pixels.count)
        if !transparent, let previous {
            var x0 = width, y0 = height, x1 = -1, y1 = -1
            for y in 0..<height {
                let row = y * width
                for x in 0..<width where pixels[row + x] != previous[row + x] {
                    if x < x0 { x0 = x }; if x > x1 { x1 = x }
                    if y < y0 { y0 = y }; if y > y1 { y1 = y }
                }
            }
            if x1 < 0 { (x0, y0, x1, y1) = (0, 0, 0, 0) }
            box = (x0, y0, x1, y1)
            for i in pixels.indices where pixels[i] == previous[i] { drawn[i] = false }
        }
        if transparent {
            for i in pixels.indices where pixels[i] >> 24 < 128 { drawn[i] = false }
        }
        previous = pixels

        let boxWidth = box.x1 - box.x0 + 1, boxHeight = box.y1 - box.y0 + 1
        var inBox: [UInt32] = []
        inBox.reserveCapacity(boxWidth * boxHeight)
        var shows: [Bool] = []
        shows.reserveCapacity(boxWidth * boxHeight)
        for y in box.y0...box.y1 {
            for x in box.x0...box.x1 {
                inBox.append(pixels[y * width + x])
                shows.append(drawn[y * width + x])
            }
        }
        var palette = GIFPalette(inBox, shows: shows)
        let indices = palette.indices(for: inBox, shows: shows, width: boxWidth, originX: box.x0, originY: box.y0)

        // Graphic control: the delay, the see-through index, and what
        // happens to the frame after: kept under the next one when only
        // changes are drawn, cleared when every frame is whole.
        let disposal: UInt8 = transparent ? 2 : 1
        bytes.append(contentsOf: [0x21, 0xF9, 0x04, (disposal << 2) | 1])
        put16(max(delay, 2))
        bytes.append(contentsOf: [Self.clearIndex, 0x00])
        // The frame's box and its own palette of 256.
        bytes.append(0x2C)
        put16(box.x0); put16(box.y0); put16(boxWidth); put16(boxHeight)
        bytes.append(0x80 | 7)
        bytes.append(contentsOf: palette.table)
        bytes.append(8)
        GIFLZW.encode(indices, into: &bytes)
        try flush()
    }

    func finish() throws {
        bytes.append(0x3B)
        try flush()
        try handle.close()
    }

    func abandon() { try? handle.close() }

    private func put16(_ v: Int) {
        bytes.append(UInt8(v & 0xFF))
        bytes.append(UInt8((v >> 8) & 0xFF))
    }

    private func flush() throws {
        try handle.write(contentsOf: bytes)
        bytes.removeAll(keepingCapacity: true)
    }

    /// Straight colour from premultiplied, so a soft edge kept keeps its
    /// colour rather than darkening towards black.
    private func unpremultiply(_ pixels: inout [UInt32]) {
        for i in pixels.indices {
            let p = pixels[i], a = p >> 24
            guard a > 0, a < 255 else { continue }
            func up(_ shift: UInt32) -> UInt32 { min(((p >> shift) & 0xFF) * 255 / a, 255) << shift }
            pixels[i] = (a << 24) | up(16) | up(8) | up(0)
        }
    }
}

/// Up to 255 colours for one frame. The colours that cover much of it (a
/// flat background, a solid card) are kept exactly, each its own entry, so
/// they come out the same in every frame: made by median cut alone, a
/// background uncovered by a moving shadow came back a shade off the rest,
/// leaving a trail. The rest are a histogram of the other pixels in 32
/// levels a channel, split by median cut, each the average of the pixels it
/// stands for.
struct GIFPalette {
    /// 256 colours as red, green, blue bytes; the last is the see-through one.
    private(set) var table: [UInt8]
    private var colors: [(r: Int, g: Int, b: Int)]
    /// The nearest colour for each histogram cell, worked out as needed.
    private var nearest: [Int16]
    /// The colours kept exactly, by their pixel value, and their entries.
    private var exact: [UInt32: Int] = [:]

    /// A colour covering at least this share of what a frame draws is kept exactly.
    static let exactShare = 0.002
    static let maxExact = 64

    /// The pixel value without its alpha, which a colour match ignores.
    private static func rgb(_ p: UInt32) -> UInt32 { p & 0x00FF_FFFF }

    private static func cell(_ r: Int, _ g: Int, _ b: Int) -> Int { (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3) }

    init(_ pixels: [UInt32], shows: [Bool]) {
        // Exact colours, counted a run at a time, since flat artwork repeats.
        var runs: [UInt32: Int] = [:]
        var drawnCount = 0
        var last: UInt32 = 0, run = 0
        for (i, p) in pixels.enumerated() where shows[i] {
            drawnCount += 1
            let c = Self.rgb(p)
            if run > 0, c == last { run += 1; continue }
            if run > 0 { runs[last, default: 0] += run }
            last = c
            run = 1
        }
        if run > 0 { runs[last, default: 0] += run }
        let keep = runs.filter { Double($0.value) >= Double(max(drawnCount, 1)) * Self.exactShare }
            .sorted { $0.value > $1.value }.prefix(Self.maxExact).map(\.key)
        var exact: [UInt32: Int] = [:]
        for (i, c) in keep.enumerated() { exact[c] = i }

        var count = [Int](repeating: 0, count: 32768)
        var sums = [(r: Int, g: Int, b: Int)](repeating: (0, 0, 0), count: 32768)
        var lastKept: (color: UInt32, kept: Bool) = (0xFFFF_FFFF, false)
        for (i, p) in pixels.enumerated() where shows[i] {
            let value = Self.rgb(p)
            if value != lastKept.color { lastKept = (value, exact[value] != nil) }
            if lastKept.kept { continue }
            let r = Int((p >> 16) & 0xFF), g = Int((p >> 8) & 0xFF), b = Int(p & 0xFF)
            let c = Self.cell(r, g, b)
            count[c] += 1
            sums[c].r += r; sums[c].g += g; sums[c].b += b
        }
        let used = (0..<32768).filter { count[$0] > 0 }
        func channel(_ c: Int, _ axis: Int) -> Int { axis == 0 ? c >> 10 : axis == 1 ? (c >> 5) & 31 : c & 31 }
        struct Box { var cells: [Int]; var axis: Int; var score: Int }
        // A box's longest side, and how much it is worth splitting: how far
        // it spans, weighted by how many pixels it holds.
        func box(_ cells: [Int]) -> Box {
            var low = [31, 31, 31], high = [0, 0, 0], total = 0
            for c in cells {
                total += count[c]
                for axis in 0..<3 { let v = channel(c, axis); low[axis] = min(low[axis], v); high[axis] = max(high[axis], v) }
            }
            let sides = (0..<3).map { high[$0] - low[$0] }
            let axis = sides.firstIndex(of: sides.max() ?? 0) ?? 0
            return Box(cells: cells, axis: axis, score: sides[axis] == 0 ? -1 : sides[axis] * total)
        }
        var boxes: [Box] = used.isEmpty ? [] : [box(used)]
        // Split the box worth most at the median of its pixels along its
        // longest side.
        while boxes.count < 255 - keep.count, let pick = boxes.indices.max(by: { boxes[$0].score < boxes[$1].score }), boxes[pick].score > 0 {
            let axis = boxes[pick].axis
            let sorted = boxes[pick].cells.sorted { channel($0, axis) < channel($1, axis) }
            let total = sorted.reduce(0) { $0 + count[$1] }
            var running = 0, split = 1
            for (i, c) in sorted.enumerated() {
                running += count[c]
                if running * 2 >= total { split = min(max(i + 1, 1), sorted.count - 1); break }
            }
            boxes[pick] = box(Array(sorted[..<split]))
            boxes.append(box(Array(sorted[split...])))
        }
        colors = boxes.map { b in
            let box = b.cells
            let n = max(box.reduce(0) { $0 + count[$1] }, 1)
            let r = box.reduce(0) { $0 + sums[$1].r }, g = box.reduce(0) { $0 + sums[$1].g }, b = box.reduce(0) { $0 + sums[$1].b }
            return ((r + n / 2) / n, (g + n / 2) / n, (b + n / 2) / n)
        }
        colors = keep.map { c in (Int((c >> 16) & 0xFF), Int((c >> 8) & 0xFF), Int(c & 0xFF)) } + colors
        if colors.isEmpty { colors = [(0, 0, 0)] }
        self.exact = exact
        table = [UInt8](repeating: 0, count: 768)
        for (i, c) in colors.enumerated() {
            table[i * 3] = UInt8(c.r); table[i * 3 + 1] = UInt8(c.g); table[i * 3 + 2] = UInt8(c.b)
        }
        nearest = [Int16](repeating: -1, count: 32768)
    }

    private mutating func closest(_ r: Int, _ g: Int, _ b: Int) -> Int {
        let c = Self.cell(r, g, b)
        if nearest[c] >= 0 { return Int(nearest[c]) }
        let cr = (r & ~7) + 4, cg = (g & ~7) + 4, cb = (b & ~7) + 4
        var best = 0, bestDistance = Int.max
        for (i, p) in colors.enumerated() {
            let dr = p.r - cr, dg = p.g - cg, db = p.b - cb
            // Weighted as the eye weighs them, green most.
            let d = 3 * dr * dr + 4 * dg * dg + 2 * db * db
            if d < bestDistance { bestDistance = d; best = i }
        }
        nearest[c] = Int16(best)
        return best
    }

    /// A 4 × 4 ordered pattern, from -0.5 to 0.5.
    private static let bayer: [Double] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { ($0 + 0.5) / 16 - 0.5 }
    /// How far the pattern nudges a colour, in levels of 255.
    private static let ditherSpread = 20.0
    /// Colours this close to their palette colour are left undithered, so
    /// flat colour stays flat.
    private static let cleanDistance = 36

    mutating func indices(for pixels: [UInt32], shows: [Bool], width: Int, originX: Int, originY: Int) -> [UInt8] {
        var out = [UInt8](repeating: GIFWriter.clearIndex, count: pixels.count)
        var lastExact: (color: UInt32, index: Int?) = (0xFFFF_FFFF, nil)
        for (i, p) in pixels.enumerated() where shows[i] {
            let rgb = Self.rgb(p)
            if rgb != lastExact.color { lastExact = (rgb, exact[rgb]) }
            if let kept = lastExact.index {
                out[i] = UInt8(kept)
                continue
            }
            let r = Int((p >> 16) & 0xFF), g = Int((p >> 8) & 0xFF), b = Int(p & 0xFF)
            var index = closest(r, g, b)
            let c = colors[index]
            let dr = c.r - r, dg = c.g - g, db = c.b - b
            if dr * dr + dg * dg + db * db > Self.cleanDistance {
                let x = originX + i % width, y = originY + i / width
                let nudge = Int(Self.bayer[(y & 3) * 4 + (x & 3)] * Self.ditherSpread)
                func held(_ v: Int) -> Int { min(max(v + nudge, 0), 255) }
                index = closest(held(r), held(g), held(b))
            }
            out[i] = UInt8(index)
        }
        return out
    }
}

/// GIF's variable-length LZW, in sub-blocks of 255 bytes, with 8-bit
/// codes to start: a clear code first, and again whenever the table fills.
enum GIFLZW {
    static func encode(_ indices: [UInt8], into data: inout Data) {
        let minimum = 8
        let clear = 1 << minimum, end = clear + 1
        var size = minimum + 1
        var next = end
        // The table as a flat trie: for a code and the next index, the code
        // they make, stamped with the generation it was made in so clearing
        // is a counter rather than a sweep.
        var table = [UInt32](repeating: 0, count: 4096 * 256)
        var generation: UInt32 = 1

        var block = [UInt8](); block.reserveCapacity(255)
        var bits: UInt32 = 0, count = 0
        func emit(_ code: Int) {
            bits |= UInt32(code) << UInt32(count)
            count += size
            while count >= 8 {
                block.append(UInt8(bits & 0xFF))
                bits >>= 8
                count -= 8
                if block.count == 255 { data.append(255); data.append(contentsOf: block); block.removeAll(keepingCapacity: true) }
            }
        }

        emit(clear)
        var current = -1
        for value in indices {
            let v = Int(value)
            if current < 0 { current = v; continue }
            let slot = current * 256 + v
            let found = table[slot]
            if found >> 12 == generation {
                current = Int(found & 0xFFF)
                continue
            }
            emit(current)
            next += 1
            table[slot] = generation << 12 | UInt32(next)
            if next >= 1 << size { size += 1 }
            if next == 4095 {
                emit(clear)
                generation += 1
                size = minimum + 1
                next = end
            }
            current = v
        }
        if current >= 0 { emit(current) }
        emit(clear)
        emit(end)
        if count > 0 { block.append(UInt8(bits & 0xFF)) }
        if !block.isEmpty { data.append(UInt8(block.count)); data.append(contentsOf: block) }
        data.append(0)
    }
}
