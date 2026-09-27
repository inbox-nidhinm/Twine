import Foundation
import Testing
import MotionModel
import MotionEvaluation
@testable import MotionEditing

@Suite struct PictureEditingTests {
    private let wide = MediaAsset(kind: .image, fileName: "w.png", originalName: "wide.png", contentHash: "w",
                                  pixelWidth: 400, pixelHeight: 200)
    private let tall = MediaAsset(kind: .image, fileName: "t.png", originalName: "tall.png", contentHash: "t",
                                  pixelWidth: 100, pixelHeight: 400)

    private func picture(_ paint: ImagePaint, size: Size2 = Size2(200, 200), name: String = "wide") -> Layer {
        Layer(name: name, content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero), fills: [Fill(paint: .image(paint))])),
              size: size, position: Vec2(100, 100))
    }

    private func close(_ a: ImageCrop, _ b: ImageCrop) -> Bool {
        abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9 && abs(a.width - b.width) < 1e-9 && abs(a.height - b.height) < 1e-9
    }

    // MARK: Placement

    @Test func fillCoversAndFitShowsTheWholePicture() {
        let box = Size2(200, 200), size = Size2(400, 200)
        let fill = ImagePlacement.frame(of: ImagePaint(mediaID: wide.id), box: box, picture: size)
        #expect(fill == Box(minX: -100, minY: 0, maxX: 300, maxY: 200))
        let fit = ImagePlacement.frame(of: ImagePaint(mediaID: wide.id, mode: .fit), box: box, picture: size)
        #expect(fit == Box(minX: 0, minY: 50, maxX: 200, maxY: 150))
    }

    @Test func aTurnedPictureIsPlacedAsTallAsItWasWide() {
        let fit = ImagePlacement.frame(of: ImagePaint(mediaID: wide.id, mode: .fit, quarterTurns: 1),
                                       box: Size2(200, 200), picture: Size2(400, 200))
        #expect(fit == Box(minX: 50, minY: 0, maxX: 150, maxY: 200))
    }

    @Test func tilesAreThePicturesOwnSizeScaled() {
        let tile = ImagePlacement.frame(of: ImagePaint(mediaID: wide.id, mode: .tile, tileScale: 0.25),
                                        box: Size2(200, 200), picture: Size2(400, 200))
        #expect(tile == Box(minX: 0, minY: 0, maxX: 100, maxY: 50))
    }

    @Test func aPictureOfUnknownSizeFillsItsBox() {
        let frame = ImagePlacement.frame(of: ImagePaint(mediaID: wide.id), box: Size2(30, 70), picture: nil)
        #expect(frame == Box(minX: 0, minY: 0, maxX: 30, maxY: 70))
    }

    @Test func evaluationPlacesPicturesFromTheirFiles() throws {
        let layer = picture(ImagePaint(mediaID: wide.id, mode: .fit, opacity: 0.5))
        let scene = evaluateDesign(Project(layers: [layer], media: [wide]))
        guard case .shape(let shape) = scene.layers.first?.content, case .image(let image) = shape.fills.first else {
            Issue.record("no picture")
            return
        }
        #expect(image.frame == Box(minX: 0, minY: 50, maxX: 200, maxY: 150))
        #expect(image.opacity == 0.5 && !image.tiles && image.mediaID == wide.id)
    }

    // MARK: Modes

    @Test func choosingCropKeepsThePictureWhereItWas() {
        let layer = PictureEditing.settingMode(picture(ImagePaint(mediaID: wide.id)), to: .crop, pictures: [wide.id: Size2(400, 200)])
        let paint = layer.picture!.paint
        #expect(paint.mode == .crop)
        #expect(close(paint.crop, ImageCrop(x: -0.5, y: 0, width: 2, height: 1)))
        #expect(ImagePlacement.frame(of: paint, box: layer.size, picture: Size2(400, 200)) == Box(minX: -100, minY: 0, maxX: 300, maxY: 200))
    }

    @Test func turningACropTurnsItAboutItsCentre() {
        let crop = ImageCrop(x: -0.5, y: 0, width: 2, height: 1)
        let layer = PictureEditing.turned(picture(ImagePaint(mediaID: wide.id, mode: .crop, crop: crop)))
        let paint = layer.picture!.paint
        #expect(paint.turns == 1)
        #expect(close(paint.crop, ImageCrop(x: 0, y: -0.5, width: 1, height: 2)))
        // Four turns come back round.
        let round = (0..<3).reduce(layer) { l, _ in PictureEditing.turned(l) }
        #expect(round.picture!.paint.turns == 0)
        #expect(close(round.picture!.paint.crop, crop))
    }

    // MARK: Cropping

    @Test func movingAndScalingACrop() {
        let box = Size2(200, 100)
        let moved = PictureEditing.movedCrop(.whole, by: Vec2(20, -10), box: box)
        #expect(close(moved, ImageCrop(x: 0.1, y: -0.1, width: 1, height: 1)))
        // The bottom-right corner dragged out to (400, 200): twice the size,
        // the top-left staying put.
        let scaled = PictureEditing.scaledCrop(.whole, corner: 2, to: Vec2(400, 200), box: box)
        #expect(close(scaled, ImageCrop(x: 0, y: 0, width: 2, height: 2)))
        // Pulled off the diagonal, the picture still keeps its shape.
        let skewed = PictureEditing.scaledCrop(.whole, corner: 2, to: Vec2(400, 100), box: box)
        #expect(abs(skewed.width / skewed.height - 1) < 1e-9)
        // And it never turns inside out or vanishes.
        let tiny = PictureEditing.scaledCrop(.whole, corner: 2, to: Vec2(-50, -50), box: box)
        #expect(tiny.width * box.width >= PictureEditing.minimumCropSide - 1e-9)
    }

    @Test func resizingWhileCroppingLeavesThePictureInPlace() {
        var layer = picture(ImagePaint(mediaID: wide.id, mode: .crop, crop: .whole), size: Size2(200, 100))
        layer.transform.anchor = .zero
        layer.transform.position = Vec2(50, 50)
        // The left edge dragged in by 40: the box starts 40 further right
        // and is 40 narrower.
        var resized = layer
        resized.size = Size2(160, 100)
        resized.transform.position = Vec2(90, 50)
        let cropped = PictureEditing.croppingResize(layer, to: resized)
        let frame = ImagePlacement.frame(of: cropped.picture!.paint, box: cropped.size, picture: nil)
        // Still from 50 to 250 across in the parent: -40 to 160 in the box.
        #expect(abs(frame.minX + 40) < 1e-9 && abs(frame.maxX - 160) < 1e-9)
        #expect(abs(frame.minY) < 1e-9 && abs(frame.maxY - 100) < 1e-9)
    }

    // MARK: Replace

    @Test func replacingAPictureKeepsTheLayerAndItsActions() {
        let layer = picture(ImagePaint(mediaID: wide.id, mode: .fit, quarterTurns: 1))
        let replaced = PictureEditing.replacingPicture(layer, with: tall, old: wide)
        #expect(replaced.id == layer.id && replaced.size == layer.size && replaced.transform == layer.transform)
        #expect(replaced.picture?.paint == ImagePaint(mediaID: tall.id, mode: .fit, quarterTurns: 1))
        // Named after its old file, it takes the new one's name; a name of
        // its own stays.
        #expect(replaced.name == "tall")
        #expect(PictureEditing.replacingPicture(picture(ImagePaint(mediaID: wide.id), name: "Hero"), with: tall, old: wide).name == "Hero")
    }

    @Test func replacingACroppedPictureCoversWhatShowed() {
        // The wide picture cropped to its middle: 2 by 1 over a square box.
        let layer = picture(ImagePaint(mediaID: wide.id, mode: .crop, crop: ImageCrop(x: -0.5, y: 0, width: 2, height: 1)))
        let replaced = PictureEditing.replacingPicture(layer, with: tall, old: wide)
        let crop = replaced.picture!.paint.crop
        // The tall one covers that 400 by 200 area at its own 1 by 4 shape,
        // centred on it.
        #expect(close(crop, ImageCrop(x: -0.5, y: -3.5, width: 2, height: 8)))
    }

    @Test func replacingAVideoPullsBackPlaysThatWouldRunOff() {
        let old = MediaAsset(kind: .video, fileName: "a.mov", originalName: "a.mov", contentHash: "a", duration: 10)
        let short = MediaAsset(kind: .video, fileName: "b.mov", originalName: "b.mov", contentHash: "b", duration: 4)
        let layer = Layer(name: "a", content: .video(VideoContent(mediaID: old.id, fit: .fit)), size: Size2(10, 10), position: .zero)
        let late = Action(target: layer.id, start: 0, duration: 2, spec: .play(PlayAction(trimStart: 5)))
        let long = Action(target: layer.id, start: 0, duration: 6, spec: .play(PlayAction(trimStart: 1)))
        let fine = Action(target: layer.id, start: 0, duration: 1, spec: .play(PlayAction(trimStart: 1)))
        let result = PictureEditing.replacingVideo(layer, with: short, old: old, actions: [late, long, fine])
        #expect(result.layer.content == .video(VideoContent(mediaID: short.id, fit: .fit)))
        #expect(result.layer.name == "b")
        // 2 s from 5 s in would pass 4 s, so it starts at 2 s; 6 s cannot
        // fit, so it starts at the file's start and holds the last frame.
        #expect(result.actions.map(\.id) == [late.id, long.id])
        #expect(result.actions.map(\.spec) == [.play(PlayAction(trimStart: 2)), .play(PlayAction(trimStart: 0))])
    }

    // MARK: Actions

    @Test func aPictureOffersNoColourAction() {
        let kinds = ActionFactory.kinds(for: picture(ImagePaint(mediaID: wide.id)), hasSound: false)
        #expect(!kinds.contains(.color))
        #expect(kinds.contains(.cornerRadius) && kinds.contains(.move))
    }

    @Test func importedPicturesAreRectanglesFilledWithThem() {
        let layer = LayerFactory.media(wide, center: Vec2(500, 500), fitting: Size2(1920, 1080), name: "wide")
        #expect(layer.picture?.paint == ImagePaint(mediaID: wide.id))
        #expect(layer.size == Size2(400, 200))
        #expect(layer.mediaIDs == [wide.id])
    }
}
