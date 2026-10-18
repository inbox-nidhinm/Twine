import Foundation
import QuartzCore
import ObjectiveC
import MotionModel
import MotionEvaluation

/// Core Animation's private mesh warp (`CAMeshTransform`, set as a layer's
/// `meshTransform`): a grid laid over the layer, each point of it moved
/// somewhere else, and the layer, everything inside it included, stretched
/// along. How bent layers are drawn, the same on the canvas and in exports
/// (the templates spike, `Space3DRenderingTests`). Looked up by name, as the
/// private filters are; without it a bent layer is drawn flat through its
/// corners. A layer's own clip comes after its mesh, in its flat box, so
/// nothing that bends may clip itself: frames clip in their children's
/// holder, one layer in.
enum MeshWarp {
    private struct Vertex {
        var from: CGPoint
        var to: (CGFloat, CGFloat, CGFloat)
    }

    private struct Face {
        var indices: (UInt32, UInt32, UInt32, UInt32)
        var w: (Float, Float, Float, Float)
    }

    private typealias Make = @convention(c) (AnyObject, Selector, UInt, UnsafeRawPointer, UInt, UnsafeRawPointer,
                                             NSString) -> AnyObject?

    private static let selector = NSSelectorFromString("meshTransformWithVertexCount:vertices:faceCount:faces:depthNormalization:")
    private static let kind: AnyClass? = NSClassFromString("CAMeshTransform")
    private static let make: Make? = {
        guard let kind, let method = class_getClassMethod(kind, selector) else { return nil }
        return unsafeBitCast(method_getImplementation(method), to: Make.self)
    }()

    static var isAvailable: Bool { make != nil }

    /// The warp that puts a layer of `size`, sitting square at its parent's
    /// origin, onto `mesh`'s points in the parent.
    static func transform(_ mesh: BentMesh, size: Size2) -> AnyObject? {
        guard let make, let kind, size.width > 0, size.height > 0,
              mesh.points.count == (mesh.rows + 1) * (mesh.columns + 1) else { return nil }
        var vertices: [Vertex] = []
        vertices.reserveCapacity(mesh.points.count)
        for j in 0...mesh.rows {
            for i in 0...mesh.columns {
                let k = j * (mesh.columns + 1) + i
                let p = mesh.points[k]
                // Depth in the layer's widths, as `width` normalisation reads it.
                let z = k < mesh.depths.count ? mesh.depths[k] / size.width : 0
                vertices.append(Vertex(from: CGPoint(x: Double(i) / Double(mesh.columns), y: Double(j) / Double(mesh.rows)),
                                       to: (CGFloat(p.x / size.width), CGFloat(p.y / size.height), CGFloat(z))))
            }
        }
        var faces: [Face] = []
        faces.reserveCapacity(mesh.rows * mesh.columns)
        for j in 0..<mesh.rows {
            for i in 0..<mesh.columns {
                // Only its own side, for a layer split into front and back.
                if mesh.side != .both, mesh.facesFront(i, j) != (mesh.side == .front) { continue }
                let a = UInt32(j * (mesh.columns + 1) + i), b = a + 1
                let c = UInt32((j + 1) * (mesh.columns + 1) + i + 1), d = c - 1
                faces.append(Face(indices: (a, b, c, d), w: (0, 0, 0, 0)))
            }
        }
        guard !faces.isEmpty else { return nil }
        return vertices.withUnsafeBytes { v in
            faces.withUnsafeBytes { f in
                make(kind, selector, UInt(vertices.count), v.baseAddress!, UInt(faces.count), f.baseAddress!, "width")
            }
        }
    }
}
