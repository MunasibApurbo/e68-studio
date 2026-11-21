import SceneKit
import AppKit
import simd

extension PlantProps {

    // MARK: - Optical Glass, Water & Caustic Materials

    /// Front-facing crystal-clear soda-lime glass: nearly invisible center so stems/roots/background shine cleanly through,
    /// with sharp HDR IBL specular window highlights, subtle dark refractive edge absorption, and grazing Fresnel glint.
    static let frontGlassMat: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 1)
        m.roughness.contents = 0.008
        m.metalness.contents = 0.0
        m.clearCoat.contents = 1.0
        m.clearCoatRoughness.contents = 0.006
        m.transparency = 0.999
        m.cullMode = .back
        m.writesToDepthBuffer = false
        m.shaderModifiers = [.fragment: """
            vec3 V = normalize(_surface.view);
            vec3 N = normalize(_surface.normal);
            float ndv = clamp(dot(N, V), 0.0, 1.0);
            float fresnel = 0.022 + 0.978 * pow(1.0 - ndv, 5.0);
            float edgeThickness = smoothstep(0.66, 0.94, 1.0 - ndv);
            float outerRim = smoothstep(0.86, 0.985, 1.0 - ndv);
            vec3 pbrSpec = _output.color.rgb;
            float specLuma = dot(pbrSpec, vec3(0.2126, 0.7152, 0.0722));
            float outerEdge = smoothstep(0.74, 0.96, 1.0 - ndv);
            vec3 sodaEdge = vec3(0.015, 0.052, 0.040);
            vec3 outRGB = pbrSpec * (0.45 + 1.40 * fresnel) + sodaEdge * outerEdge * 0.50;
            float outA = clamp(0.005 + fresnel * 0.44 + edgeThickness * 0.28 + outerRim * 0.18 + specLuma * 0.62, 0.005, 0.90);
            _output.color = vec4(outRGB, outA);
        """]
        return m
    }()

    /// Far-wall inner glass pass rendered behind water & submerged stems for crisp double-wall depth.
    static let backGlassMat: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 1)
        m.roughness.contents = 0.012
        m.metalness.contents = 0.0
        m.transparency = 0.999
        m.cullMode = .front
        m.writesToDepthBuffer = false
        m.shaderModifiers = [.fragment: """
            vec3 V = normalize(_surface.view);
            vec3 N = normalize(-_surface.normal);
            float ndv = clamp(dot(N, V), 0.0, 1.0);
            float fresnel = 0.012 + 0.988 * pow(1.0 - ndv, 4.8);
            float edgeBand = smoothstep(0.72, 0.96, 1.0 - ndv);
            vec3 pbrSpec = _output.color.rgb;
            float specLuma = dot(pbrSpec, vec3(0.2126, 0.7152, 0.0722));
            vec3 outRGB = pbrSpec * (0.20 + 0.65 * fresnel) + vec3(0.018, 0.044, 0.036) * edgeBand * 0.36;
            float outA = clamp(0.004 + edgeBand * 0.24 + specLuma * 0.30, 0.004, 0.42);
            _output.color = vec4(outRGB, outA);
        """]
        return m
    }()

    /// Thick refractive glass base puck: transparent center floor, concentrated soda-lime rim thickness & bright glass edge.
    static let glassBaseMat: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 1)
        m.roughness.contents = 0.012
        m.metalness.contents = 0.0
        m.transparency = 0.999
        m.cullMode = .back
        m.writesToDepthBuffer = false
        m.shaderModifiers = [.fragment: """
            vec3 V = normalize(_surface.view);
            vec3 N = normalize(_surface.normal);
            float ndv = clamp(dot(N, V), 0.0, 1.0);
            vec3 worldN = normalize((u_inverseViewTransform * vec4(N, 0.0)).xyz);
            float rimMask = smoothstep(0.28, 0.84, 1.0 - abs(worldN.y));
            float fresnel = 0.02 + 0.98 * pow(1.0 - ndv, 4.2);
            vec3 pbrSpec = _output.color.rgb;
            float specLuma = dot(pbrSpec, vec3(0.2126, 0.7152, 0.0722));
            vec3 thickGlass = vec3(0.035, 0.085, 0.068) * rimMask;
            vec3 outRGB = thickGlass * 0.55 + pbrSpec * (0.28 + 0.95 * fresnel);
            float outA = clamp(0.008 + rimMask * 0.44 + fresnel * rimMask * 0.24 + specLuma * 0.40, 0.008, 0.76);
            _output.color = vec4(outRGB, outA);
        """]
        return m
    }()

    /// Subtle optical glass highlights for molded neck screw-threads.
    static let glassThreadMat: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 1)
        m.roughness.contents = 0.014
        m.metalness.contents = 0.0
        m.transparency = 0.999
        m.cullMode = .back
        m.writesToDepthBuffer = false
        m.shaderModifiers = [.fragment: """
            vec3 V = normalize(_surface.view);
            vec3 N = normalize(_surface.normal);
            float ndv = clamp(dot(N, V), 0.0, 1.0);
            float fresnel = 0.025 + 0.975 * pow(1.0 - ndv, 3.6);
            vec3 pbrSpec = _output.color.rgb;
            float specLuma = dot(pbrSpec, vec3(0.2126, 0.7152, 0.0722));
            vec3 outRGB = pbrSpec * (0.35 + 0.85 * fresnel) + vec3(0.08, 0.11, 0.10) * fresnel * 0.28;
            float outA = clamp(0.012 + fresnel * 0.24 + specLuma * 0.45, 0.012, 0.46);
            _output.color = vec4(outRGB, outA);
        """]
        return m
    }()

    /// Pale greenish-aqua molded jar glass for thick-walled ribbed pickle/mason jars.
    static let greenFrontGlassMat: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 1)
        m.roughness.contents = 0.016
        m.metalness.contents = 0.0
        m.clearCoat.contents = 1.0
        m.clearCoatRoughness.contents = 0.012
        m.transparency = 0.999
        m.cullMode = .back
        m.writesToDepthBuffer = false
        m.shaderModifiers = [.fragment: """
            vec3 V = normalize(_surface.view);
            vec3 N = normalize(_surface.normal);
            float ndv = clamp(dot(N, V), 0.0, 1.0);
            float fresnel = 0.028 + 0.972 * pow(1.0 - ndv, 4.4);
            float edgeThickness = smoothstep(0.55, 0.94, 1.0 - ndv);
            vec3 pbrSpec = _output.color.rgb;
            float specLuma = dot(pbrSpec, vec3(0.2126, 0.7152, 0.0722));
            vec3 aquaTint = vec3(0.022, 0.068, 0.044);
            vec3 outRGB = pbrSpec * (0.48 + 1.25 * fresnel) + aquaTint * (0.14 + edgeThickness * 0.72);
            float outA = clamp(0.040 + fresnel * 0.42 + edgeThickness * 0.36 + specLuma * 0.58, 0.04, 0.88);
            _output.color = vec4(outRGB, outA);
        """]
        return m
    }()

    static let greenBackGlassMat: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 1)
        m.roughness.contents = 0.018
        m.metalness.contents = 0.0
        m.transparency = 0.999
        m.cullMode = .front
        m.writesToDepthBuffer = false
        m.shaderModifiers = [.fragment: """
            vec3 V = normalize(_surface.view);
            vec3 N = normalize(-_surface.normal);
            float ndv = clamp(dot(N, V), 0.0, 1.0);
            float edgeBand = smoothstep(0.62, 0.95, 1.0 - ndv);
            vec3 pbrSpec = _output.color.rgb;
            float specLuma = dot(pbrSpec, vec3(0.2126, 0.7152, 0.0722));
            vec3 outRGB = pbrSpec * 0.35 + vec3(0.048, 0.125, 0.082) * (0.14 + edgeBand * 0.65);
            float outA = clamp(0.025 + edgeBand * 0.28 + specLuma * 0.26, 0.025, 0.48);
            _output.color = vec4(outRGB, outA);
        """]
        return m
    }()

    static let greenGlassBaseMat: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 1)
        m.roughness.contents = 0.018
        m.metalness.contents = 0.0
        m.transparency = 0.999
        m.cullMode = .back
        m.writesToDepthBuffer = false
        m.shaderModifiers = [.fragment: """
            vec3 V = normalize(_surface.view);
            vec3 N = normalize(_surface.normal);
            float ndv = clamp(dot(N, V), 0.0, 1.0);
            vec3 worldN = normalize((u_inverseViewTransform * vec4(N, 0.0)).xyz);
            float rimMask = smoothstep(0.24, 0.84, 1.0 - abs(worldN.y));
            float fresnel = 0.03 + 0.97 * pow(1.0 - ndv, 4.0);
            vec3 pbrSpec = _output.color.rgb;
            float specLuma = dot(pbrSpec, vec3(0.2126, 0.7152, 0.0722));
            vec3 thickGlass = vec3(0.065, 0.165, 0.105) * (0.28 + 0.95 * rimMask);
            vec3 outRGB = thickGlass + pbrSpec * (0.28 + 0.90 * fresnel);
            float outA = clamp(0.04 + rimMask * 0.48 + fresnel * rimMask * 0.22 + specLuma * 0.38, 0.04, 0.80);
            _output.color = vec4(outRGB, outA);
        """]
        return m
    }()

    /// Physically-clear liquid water volume: invisible haze-free center showing submerged stems/roots clearly,
    /// with subtle refractive edge thickness and crisp total-internal-reflection sliver at grazing vessel walls.
    static let waterBodyMat: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 1)
        m.roughness.contents = 0.008
        m.metalness.contents = 0.0
        m.transparency = 0.999
        m.cullMode = .back
        m.writesToDepthBuffer = false
        m.shaderModifiers = [.fragment: """
            vec3 V = normalize(_surface.view);
            vec3 N = normalize(_surface.normal);
            float ndv = clamp(dot(N, V), 0.0, 1.0);
            float fresnel = pow(1.0 - ndv, 4.6);
            float flank = smoothstep(0.72, 0.96, 1.0 - ndv);
            float tirRim = smoothstep(0.84, 0.975, 1.0 - ndv);
            vec3 pbrSpec = _output.color.rgb;
            float specLuma = dot(pbrSpec, vec3(0.2126, 0.7152, 0.0722));
            vec3 aquaTint = vec3(0.003, 0.006, 0.006);
            vec3 outRGB = aquaTint * (0.12 + 0.45 * flank) + pbrSpec * (0.20 + 0.88 * flank) + vec3(0.90, 0.92, 0.94) * tirRim * 0.24;
            float outA = clamp(0.010 + 0.14 * flank + 0.24 * tirRim + fresnel * 0.14 + specLuma * 0.35, 0.010, 0.56);
            _output.color = vec4(outRGB, outA);
        """]
        return m
    }()

    /// Concave top water surface: transparent center with real HDR Fresnel glint and a razor-thin meniscus rim at the wall.
    static let waterSurfaceMat: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 1)
        m.roughness.contents = 0.008
        m.metalness.contents = 0.0
        m.transparency = 0.999
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.shaderModifiers = [.fragment: """
            vec3 V = normalize(_surface.view);
            vec3 N = normalize(_surface.normal);
            if (dot(N, V) < 0.0) { N = -N; }
            float ndv = clamp(dot(N, V), 0.0, 1.0);
            float fresnel = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
            vec3 worldN = normalize((u_inverseViewTransform * vec4(N, 0.0)).xyz);
            float meniscusTilt = clamp(1.0 - abs(worldN.y), 0.0, 1.0);
            float meniscusRim = smoothstep(0.32, 0.72, meniscusTilt);
            float meniscusCrease = smoothstep(0.10, 0.28, meniscusTilt) * (1.0 - smoothstep(0.28, 0.52, meniscusTilt));
            vec3 pbrSpec = _output.color.rgb;
            float specLuma = dot(pbrSpec, vec3(0.2126, 0.7152, 0.0722));
            vec3 outRGB = pbrSpec * (0.32 + 1.05 * fresnel) + vec3(0.92, 0.96, 0.98) * meniscusRim * 0.46 + vec3(0.015, 0.032, 0.028) * meniscusCrease * 0.25;
            float outA = clamp(0.008 + 0.30 * fresnel + 0.42 * meniscusRim + 0.20 * meniscusCrease + specLuma * 0.48, 0.008, 0.74);
            _output.color = vec4(outRGB, outA);
        """]
        return m
    }()

    static let causticMat: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = DeskTextures.waterCausticTexture()
        m.transparency = 0.14
        m.blendMode = .add
        m.writesToDepthBuffer = false
        return m
    }()

    // MARK: - Vessel Builders

    /// Revolved mesh supporting continuous per-ring superellipse blending (`squareness` 0 = circle, 1 = rounded square).
    static func roundedVesselGeometry(
        profile: [(r: Float, y: Float, squareness: Float)],
        exponent: Float = 3.15,
        segments: Int = 56
    ) -> SCNGeometry {
        let rings: [[SIMD3<Float>]] = profile.map { pt in
            let p = 2.0 + (exponent - 2.0) * max(0, min(1, pt.squareness))
            return (0..<segments).map { i in
                let a = Float(i) / Float(segments) * 2 * .pi
                let ca = cos(a)
                let sa = sin(a)
                let scale: Float = p > 2.001
                    ? pow(pow(abs(ca), p) + pow(abs(sa), p), -1.0 / p)
                    : 1.0
                let rr = pt.r * scale
                return SIMD3(rr * ca, pt.y, rr * sa)
            }
        }
        return MeshBuilder.loft(rings: rings)
    }

    /// Adds circular or superellipsoid back/front optical glass shells, thick bottom puck, water volume, concave meniscus, and caustic.
    /// All glass, water, and caustic nodes explicitly disable shadow casting so roots and stems inside vessels stay cleanly lit.
    static func addGlassVesselAndWater(
        outerGeometry outerGeo: SCNGeometry,
        baseGeometry baseGeo: SCNGeometry,
        waterGeometry waterGeo: SCNGeometry,
        waterTopProfileRadius: Float,
        waterTopSquareness: Float = 0,
        squareExponent: Float = 3.15,
        waterTopY: Float,
        segments: Int = 48,
        greenTinted: Bool = false,
        causticPos: SIMD3<Float>,
        causticRadius: Float,
        into group: SCNNode,
        causticRoot: SCNNode
    ) {
        // Back glass wall behind water & stems
        outerGeo.materials = [greenTinted ? greenBackGlassMat : backGlassMat]
        let backNode = SCNNode(geometry: outerGeo)
        backNode.renderingOrder = 1
        backNode.castsShadow = false
        group.addChildNode(backNode)

        // Thick refractive glass base puck
        baseGeo.materials = [greenTinted ? greenGlassBaseMat : glassBaseMat]
        let baseNode = SCNNode(geometry: baseGeo)
        baseNode.renderingOrder = 3
        baseNode.castsShadow = false
        group.addChildNode(baseNode)

        // Optical water volume
        waterGeo.materials = [waterBodyMat]
        let waterNode = SCNNode(geometry: waterGeo)
        waterNode.renderingOrder = 3
        waterNode.castsShadow = false
        group.addChildNode(waterNode)

        // Concave capillary meniscus surface (iterate rim -> center so winding produces upward +Y normals)
        let surfSteps = 10
        var surfProfile = [(r: Float, y: Float, squareness: Float)]()
        for i in stride(from: surfSteps, through: 0, by: -1) {
            let u = Float(i) / Float(surfSteps)
            let rr = max(0.01, u * waterTopProfileRadius)
            let meniscusLift: Float = 0.055 * pow(u, 4.0) - 0.015 * (1.0 - u * u)
            surfProfile.append((rr, waterTopY + meniscusLift, waterTopSquareness * u))
        }
        let surfGeo = waterTopSquareness > 0.001
            ? roundedVesselGeometry(profile: surfProfile, exponent: squareExponent, segments: segments)
            : MeshBuilder.lathe(profile: surfProfile.map { ($0.r, $0.y) }, segments: max(36, segments - 8))
        surfGeo.materials = [waterSurfaceMat]
        let surfNode = SCNNode(geometry: surfGeo)
        surfNode.renderingOrder = 3
        surfNode.castsShadow = false
        group.addChildNode(surfNode)

        // Front crystal-clear glass shell
        let frontGeo = outerGeo.copy() as! SCNGeometry
        frontGeo.materials = [greenTinted ? greenFrontGlassMat : frontGlassMat]
        let frontNode = SCNNode(geometry: frontGeo)
        frontNode.renderingOrder = 4
        frontNode.castsShadow = false
        group.addChildNode(frontNode)

        // Soft focused caustic light pool on desk near vessel base
        let cPlane = SCNPlane(width: CGFloat(causticRadius * 2), height: CGFloat(causticRadius * 2))
        cPlane.materials = [causticMat]
        let cNode = SCNNode(geometry: cPlane)
        cNode.position = SCNVector3(causticPos.x + 0.18, 0.008, causticPos.z + 0.35)
        cNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        cNode.castsShadow = false
        cNode.renderingOrder = 1
        causticRoot.addChildNode(cNode)
    }

    /// Convenience circular-vessel overload matching symmetric glass fishbowls and bottles.
    static func addGlassVesselAndWater(
        outerProfile: [(r: Float, y: Float)],
        basePuckProfile: [(r: Float, y: Float)],
        waterProfile: [(r: Float, y: Float)],
        waterTopRadius: Float,
        waterTopY: Float,
        segments: Int = 48,
        causticPos: SIMD3<Float>,
        causticRadius: Float,
        into group: SCNNode,
        causticRoot: SCNNode
    ) {
        addGlassVesselAndWater(
            outerGeometry: MeshBuilder.lathe(profile: outerProfile, segments: segments),
            baseGeometry: MeshBuilder.lathe(profile: basePuckProfile, segments: segments),
            waterGeometry: MeshBuilder.lathe(profile: waterProfile, segments: max(36, segments - 8)),
            waterTopProfileRadius: waterTopRadius,
            waterTopY: waterTopY,
            segments: segments,
            causticPos: causticPos,
            causticRadius: causticRadius,
            into: group,
            causticRoot: causticRoot
        )
    }
}
