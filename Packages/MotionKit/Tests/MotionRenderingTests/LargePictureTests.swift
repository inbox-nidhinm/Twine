import Foundation
import Testing
import CoreGraphics
import ImageIO
import MotionModel
@testable import MotionRendering

/// Pictures past what Twine draws are read shrunk, and ones past what it
/// takes in at all are not read (4 October 2026).
@Suite struct LargePictureTests {
    /// A PNG `width` by `height`, written to a temporary file.
    private func png(_ width: Int, _ height: Int) throws -> URL {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("twine-large-\(UUID().uuidString).png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    @Test func aPictureWithinTheLimitsIsReadWhole() throws {
        let url = try png(300, 200)
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try #require(MediaLibrary.loadImage(url))
        #expect(image.width == 300 && image.height == 200)
    }

    @Test func aPictureTooWideIsReadShrunkToFit() throws {
        let url = try png(FileSafety.largestPictureSide * 2, 10)
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try #require(MediaLibrary.loadImage(url))
        #expect(image.width == FileSafety.largestPictureSide)
        #expect(image.height == 5)
    }

    @Test func aPicturePastWhatComesInIsNotRead() throws {
        let url = try png(FileSafety.largestPictureFileSide + 1, 1)
        defer { try? FileManager.default.removeItem(at: url) }
        // The file itself is fine: it is Twine that leaves it unread.
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        #expect(properties?[kCGImagePropertyPixelWidth] as? Int == FileSafety.largestPictureFileSide + 1)
        #expect(MediaLibrary.loadImage(url) == nil)
    }

    @Test func theLimitsShrinkOnlyWhatIsPastThem() {
        #expect(FileSafety.pictureDrawingScale(width: 4000, height: 3000) == 1)
        // A 120 megapixel photo comes in, drawn at 100 megapixels.
        #expect(FileSafety.pictureFileFits(width: 12_000, height: 10_000))
        let s = FileSafety.pictureDrawingScale(width: 12_000, height: 10_000)
        #expect(abs(12_000 * s * 10_000 * s - Double(FileSafety.mostPicturePixels)) < 1)
        #expect(!FileSafety.pictureFileFits(width: 30_000, height: 30_000))
        #expect(!FileSafety.pictureFileFits(width: 70_000, height: 1))
    }
}
