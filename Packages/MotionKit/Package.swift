// swift-tools-version: 6.2
import PackageDescription

// The layers of Twine that do not need the app to exist. Each is its own
// module so the compiler enforces the direction of every dependency: the model
// knows nothing, editing knows the model, and nothing here knows about views
// except Theme, which is only tokens and drawing primitives.
let package = Package(
    name: "MotionKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MotionModel", targets: ["MotionModel"]),
        .library(name: "MotionEditing", targets: ["MotionEditing"]),
        .library(name: "MotionEvaluation", targets: ["MotionEvaluation"]),
        .library(name: "MotionRendering", targets: ["MotionRendering"]),
        .library(name: "MotionExport", targets: ["MotionExport"]),
        .library(name: "MotionImport", targets: ["MotionImport"]),
        .library(name: "MotionAgent", targets: ["MotionAgent"]),
        .library(name: "Theme", targets: ["Theme"]),
    ],
    targets: [
        // Pure value types. Foundation only: no UI, no rendering.
        .target(name: "MotionModel"),
        // Commands and undo, and the edits built from them. Reads evaluated
        // values so an edit can land relative to what is on screen.
        .target(name: "MotionEditing", dependencies: ["MotionModel", "MotionEvaluation"]),
        // `evaluate(project, at:)`: interpolation, easing, springs, and the
        // flat ResolvedScene every renderer draws from. Foundation only.
        .target(name: "MotionEvaluation", dependencies: ["MotionModel"]),
        // The SceneRenderer protocol and its Core Animation implementation,
        // shared by the canvas and offscreen rendering.
        .target(name: "MotionRendering", dependencies: ["MotionModel", "MotionEvaluation"]),
        // Steps through a composition frame by frame, drawing each through
        // the offscreen renderer, and writes a movie or a still. Never tied to
        // a clock, so an export is the same every time.
        .target(name: "MotionExport", dependencies: ["MotionModel", "MotionEvaluation", "MotionRendering"]),
        // Reads SVG files into editable layers, and draws the parts it cannot
        // make editable (text, mostly) as pictures, with the system's own SVG
        // drawing, which is why it alone may use AppKit.
        .target(name: "MotionImport", dependencies: ["MotionModel", "MotionEvaluation", "MotionEditing"]),
        // Twine's tools for AI apps, through the Model Context Protocol:
        // reading the project, changing it by commands, and the protocol's
        // messages. The app hosts it on a private socket.
        .target(name: "MotionAgent", dependencies: ["MotionModel", "MotionEvaluation", "MotionEditing", "MotionExport"]),
        // Tokens from the Flip Design System in Figma, the grain, the fonts,
        // and the icon set. Copied rather than processed, because any
        // re-encoding of the grain would undo how it was packed.
        .target(name: "Theme", resources: [.copy("Resources/Textures"), .copy("Resources/Fonts")]),

        .testTarget(name: "MotionModelTests", dependencies: ["MotionModel"]),
        .testTarget(name: "MotionEditingTests", dependencies: ["MotionEditing"]),
        .testTarget(name: "MotionEvaluationTests", dependencies: ["MotionEvaluation"]),
        .testTarget(name: "MotionRenderingTests", dependencies: ["MotionRendering"]),
        .testTarget(name: "MotionExportTests", dependencies: ["MotionExport", "MotionRendering"]),
        .testTarget(name: "MotionAgentTests", dependencies: ["MotionAgent", "MotionEditing", "MotionEvaluation"]),
        .testTarget(name: "MotionImportTests", dependencies: ["MotionImport", "MotionEditing", "MotionRendering"]),
    ]
)
