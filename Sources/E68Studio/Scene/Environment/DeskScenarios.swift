import SceneKit
import AppKit
import simd

/// The surroundings of the desk. Every outdoor scenario is a real 360-degree photograph (`DeskPhotoSky`);
/// the only geometry a scenario adds is the ground the desk stands on, which shows the photograph's own
/// ground with the desk's shadows on it. The Studio Room is built separately in `DeskRoomAndMat`.
///
/// Desk legs and the under-desk basket sit flush at `floorY`.
enum DeskScenarios {

    static let floorY: Float = -26.0
    static let centerX: Float = DeskRoomAndMat.matCenter.x // 2.4

    /// Node name the ray tracer recognises as "draw the photograph's ground here".
    static let photoGroundName = "env.ground.photo"
    /// Where the panorama was taken from, relative to the ground: a tripod at about 1.6 m, above the desk.
    static let photoCaptureOrigin = SIMD3<Float>(centerX, floorY + 80, -8)

    static func build(_ scenario: DeskScenario) -> SCNNode {
        let root = SCNNode()
        root.name = "env.scenario.\(scenario.rawValue)"
        guard scenario != .room else { return root }
        root.addChildNode(photoGround(albedo: SIMD3<Float>(0.22, 0.22, 0.22)))
        return root
    }

    static func updatePhotoGroundAlbedo(in root: SCNNode, albedo: SIMD3<Float>) {
        func encoded(_ v: Float) -> CGFloat { CGFloat(v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055) }
        root.childNode(withName: photoGroundName, recursively: true)?
            .geometry?.firstMaterial?.diffuse.contents = NSColor(srgbRed: encoded(albedo.x), green: encoded(albedo.y), blue: encoded(albedo.z), alpha: 1)
    }

    /// A wide disc at floor level. The renderer paints it with the panorama as seen from the capture point,
    /// so grass, sand or snow continue from the horizon right up to the desk legs, and multiplies in the
    /// stored light so the desk's contact shadows fall on it. Its own colour is the ground's average
    /// colour, used for the light it bounces back up onto the underside of the desk.
    ///
    /// Rings grow with distance so stored light is dense under the desk and sparse far away.
    private static func photoGround(albedo: SIMD3<Float>) -> SCNNode {
        let radii: [Float] = [10, 22, 38, 60, 95, 150, 240, 380, 600, 950, 1500]
        let segments = 64
        var positions = [SCNVector3(0, 0, 0)]
        var normals = [SCNVector3(0, 1, 0)]
        var uvs = [CGPoint(x: 0.5, y: 0.5)]
        for r in radii {
            for s in 0..<segments {
                let a = Float(s) / Float(segments) * 2 * .pi
                positions.append(SCNVector3(CGFloat(cos(a) * r), 0, CGFloat(sin(a) * r)))
                normals.append(SCNVector3(0, 1, 0))
                uvs.append(CGPoint(x: CGFloat(0.5 + cos(a) * r / 3000), y: CGFloat(0.5 + sin(a) * r / 3000)))
            }
        }
        var indices = [UInt32]()
        func ring(_ k: Int, _ s: Int) -> UInt32 { UInt32(1 + k * segments + (s % segments)) }
        for s in 0..<segments {
            indices += [0, ring(0, s + 1), ring(0, s)]
            for k in 0..<(radii.count - 1) {
                indices += [ring(k, s), ring(k, s + 1), ring(k + 1, s + 1)]
                indices += [ring(k, s), ring(k + 1, s + 1), ring(k + 1, s)]
            }
        }
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals), SCNGeometrySource(textureCoordinates: uvs)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        func encoded(_ v: Float) -> CGFloat { CGFloat(v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055) }
        material.diffuse.contents = NSColor(srgbRed: encoded(albedo.x), green: encoded(albedo.y), blue: encoded(albedo.z), alpha: 1)
        material.roughness.contents = 0.95
        material.metalness.contents = 0.0
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.name = photoGroundName
        node.simdPosition = SIMD3(centerX, floorY, -8)
        return node
    }
}
