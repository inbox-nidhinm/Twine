import Foundation
import Compression

/// A dotLottie: a zip holding a manifest, the animation's JSON and its
/// pictures as files of their own, as LottieFiles and its players read it
/// (the first version of the format, which every dotLottie player opens).
enum DotLottie {
    static func archive(animation: Data, id: String, images: [LottieImage]) -> Data {
        let manifest = LottieJSON.object([
            ("version", .string("1.0")),
            ("generator", .string("Twine")),
            ("author", .string("")),
            ("animations", .array([.object([("id", .string(id)), ("speed", .number(1)), ("loop", .bool(true)),
                                            ("autoplay", .bool(true))])])),
        ]).data
        var zip = ZipWriter()
        zip.add("manifest.json", manifest, compress: true)
        zip.add("animations/\(id).json", animation, compress: true)
        // Pictures are compressed already.
        for image in images { zip.add("images/\(image.id).\(image.fileExtension)", image.data, compress: false) }
        return zip.finish()
    }
}

/// The smallest zip writer that makes files every unzipper reads: each file
/// stored or deflated, a central directory, and its end record.
struct ZipWriter {
    private var body = Data()
    private var directory = Data()
    private var count = 0

    mutating func add(_ name: String, _ data: Data, compress: Bool) {
        let crc = CRC32.checksum(data)
        let deflated = compress ? Self.deflate(data) : nil
        let deflates = deflated.map { $0.count < data.count } ?? false
        let stored = deflates ? deflated! : data
        let method: UInt16 = deflates ? 8 : 0
        let nameBytes = Data(name.utf8)
        let offset = UInt32(body.count)

        var local = Data()
        local.append(le32: 0x0403_4b50)
        local.append(le16: 20)          // version needed
        local.append(le16: 0x0800)      // names are UTF-8
        local.append(le16: method)
        local.append(le16: 0)           // time
        local.append(le16: 0x21)        // date: 1 January 1980
        local.append(le32: crc)
        local.append(le32: UInt32(stored.count))
        local.append(le32: UInt32(data.count))
        local.append(le16: UInt16(nameBytes.count))
        local.append(le16: 0)
        local.append(nameBytes)
        body.append(local)
        body.append(stored)

        var entry = Data()
        entry.append(le32: 0x0201_4b50)
        entry.append(le16: 20)          // made by
        entry.append(le16: 20)
        entry.append(le16: 0x0800)
        entry.append(le16: method)
        entry.append(le16: 0)
        entry.append(le16: 0x21)
        entry.append(le32: crc)
        entry.append(le32: UInt32(stored.count))
        entry.append(le32: UInt32(data.count))
        entry.append(le16: UInt16(nameBytes.count))
        entry.append(le16: 0)           // extra
        entry.append(le16: 0)           // comment
        entry.append(le16: 0)           // disk
        entry.append(le16: 0)           // internal attributes
        entry.append(le32: 0)           // external attributes
        entry.append(le32: offset)
        entry.append(nameBytes)
        directory.append(entry)
        count += 1
    }

    func finish() -> Data {
        var out = body
        let start = UInt32(out.count)
        out.append(directory)
        out.append(le32: 0x0605_4b50)
        out.append(le16: 0)
        out.append(le16: 0)
        out.append(le16: UInt16(count))
        out.append(le16: UInt16(count))
        out.append(le32: UInt32(directory.count))
        out.append(le32: start)
        out.append(le16: 0)
        return out
    }

    /// Raw deflate, as zip stores it: the Compression framework's zlib
    /// leaves out zlib's own header and checksum, which is what zip wants.
    static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let capacity = data.count + data.count / 8 + 1024
        var out = Data(count: capacity)
        let written = out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        out.count = written
        return out
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for b in bytes { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        }
        return c ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func append(le16 v: UInt16) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
    mutating func append(le32 v: UInt32) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
}
