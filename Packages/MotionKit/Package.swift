// swift-tools-version: 6.2
import PackageDescription

// The layers of eMotion that do not need the app to exist. Each is its own
// module so the compiler enforces the direction of every dependency: the model
// knows nothing, editing knows the model, and nothing here knows about views
// except Theme, which is only tokens and drawing primitives.
//
// Later milestones add MotionEvaluation, MotionRendering and MotionExport here.
let package = Package(
    name: "MotionKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MotionModel", targets: ["MotionModel"]),
        .library(name: "MotionEditing", targets: ["MotionEditing"]),
        .library(name: "Theme", targets: ["Theme"]),
    ],
    targets: [
        // Pure value types. Foundation only: no UI, no rendering.
        .target(name: "MotionModel"),
        // Commands and undo. Foundation and the model only.
        .target(name: "MotionEditing", dependencies: ["MotionModel"]),
        // Tokens from the Flip Design System in Figma, the grain, the fonts,
        // and the icon set. Copied rather than processed, because any
        // re-encoding of the grain would undo how it was packed.
        .target(name: "Theme", resources: [.copy("Resources/Textures"), .copy("Resources/Fonts")]),

        .testTarget(name: "MotionModelTests", dependencies: ["MotionModel"]),
        .testTarget(name: "MotionEditingTests", dependencies: ["MotionEditing"]),
    ]
)
