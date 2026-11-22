import Foundation
import SwiftUI
import SceneKit
import RoomPlan
import UIKit

struct FloorPlan3DPreviewView: UIViewRepresentable {
    private let capturedRoom: CapturedRoom
    private let editState: FloorPlanEditState?

    init(capturedRoom: CapturedRoom, editState: FloorPlanEditState?) {
        self.capturedRoom = capturedRoom
        self.editState = editState
    }

    final class Coordinator {
        var lastEditState: FloorPlanEditState?
        var hasRendered = false
        let contentNode = SCNNode()
        let cameraNode = SCNNode()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = SCNScene()
        let coordinator = context.coordinator
        coordinator.contentNode.name = "roomContent"
        scene.rootNode.addChildNode(coordinator.contentNode)

        let camera = SCNCamera()
        camera.zNear = 0.01
        camera.zFar = 10000
        coordinator.cameraNode.camera = camera
        scene.rootNode.addChildNode(coordinator.cameraNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 500
        scene.rootNode.addChildNode(ambient)

        let directional = SCNNode()
        directional.light = SCNLight()
        directional.light?.type = .directional
        directional.light?.intensity = 900
        directional.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
        scene.rootNode.addChildNode(directional)

        view.scene = scene
        view.pointOfView = coordinator.cameraNode
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.backgroundColor = UIColor(red: 0.91, green: 0.93, blue: 0.96, alpha: 1)
        view.antialiasingMode = .multisampling4X
        let bounds = rebuildContent(coordinator.contentNode)
        positionInitialCamera(coordinator.cameraNode, bounds: bounds)
        view.defaultCameraController.target = SCNVector3(
            Float(bounds.midX), Float(bounds.maxHeight * 0.4), Float(bounds.midZ)
        )
        coordinator.lastEditState = editState
        coordinator.hasRendered = true
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        guard !coordinator.hasRendered || editState != coordinator.lastEditState else { return }
        // Only replace room geometry. Scene, lights, pointOfView, controller
        // target and the user's camera transform are deliberately untouched.
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        _ = rebuildContent(coordinator.contentNode)
        SCNTransaction.commit()
        coordinator.lastEditState = editState
        coordinator.hasRendered = true
    }

    private struct RoomBounds {
        var minX: CGFloat = .greatestFiniteMagnitude
        var maxX: CGFloat = -.greatestFiniteMagnitude
        var minZ: CGFloat = .greatestFiniteMagnitude
        var maxZ: CGFloat = -.greatestFiniteMagnitude
        var maxHeight: CGFloat = 2.6
        var midX: CGFloat { (minX + maxX) / 2 }
        var midZ: CGFloat { (minZ + maxZ) / 2 }
        var span: CGFloat { max(max(maxX - minX, maxZ - minZ), 3) }

        mutating func include(center: CGPoint, radius: CGFloat, top: CGFloat) {
            minX = min(minX, center.x - radius)
            maxX = max(maxX, center.x + radius)
            minZ = min(minZ, center.y - radius)
            maxZ = max(maxZ, center.y + radius)
            maxHeight = max(maxHeight, top)
        }

        mutating func finish() {
            if minX == .greatestFiniteMagnitude {
                minX = -2; maxX = 2; minZ = -2; maxZ = 2
            }
        }
    }

    private func rebuildContent(_ root: SCNNode) -> RoomBounds {
        root.childNodes.forEach { $0.removeFromParentNode() }
        let geometry = FloorPlanGeometry(capturedRoom: capturedRoom, editState: editState)
        let ppm = geometry.pointsPerMeter
        let walls = geometry.joinedWallSegments
        var bounds = RoomBounds()

        func addBox(
            center: CGPoint, angle: CGFloat, width: CGFloat, height: CGFloat,
            depth: CGFloat, centerY: CGFloat, color: UIColor,
            opacity: CGFloat = 1, name: String, rounded: Bool = false
        ) {
            let world = FloorPlanCoordinateMapper.worldXZ(fromPlan: center, pointsPerMeter: ppm)
            let yaw = FloorPlanCoordinateMapper.sceneKitYaw(fromPlanAngle: angle)
            let values = [world.x, world.y, yaw, width, height, depth, centerY]
            // Float conversion is checked too: a finite Double can overflow Float.
            guard values.allSatisfy({ $0.isFinite && Float($0).isFinite }),
                  width > 0, height > 0, depth > 0 else { return }
            let radius = hypot(width, depth) / 2
            let extentValues = [world.x - radius, world.x + radius,
                                world.y - radius, world.y + radius,
                                centerY + height / 2]
            guard radius.isFinite,
                  extentValues.allSatisfy({ $0.isFinite && Float($0).isFinite }),
                  extentValues.allSatisfy({ abs($0) < CGFloat(Float.greatestFiniteMagnitude) / 16 }) else {
                return
            }
            let chamfer = rounded ? min(0.025, min(width, min(height, depth)) / 4) : 0
            let box = SCNBox(width: width, height: height, length: depth, chamferRadius: chamfer)
            box.firstMaterial = makeMaterial(color: color, transparency: opacity)
            let node = SCNNode(geometry: box)
            node.name = name
            node.position = SCNVector3(Float(world.x), Float(centerY), Float(world.y))
            node.eulerAngles = SCNVector3(0, Float(yaw), 0)
            root.addChildNode(node)
            bounds.include(center: world, radius: radius, top: centerY + height / 2)
        }

        for wall in walls {
            addBox(
                center: wall.midpoint, angle: wall.angle,
                width: wall.length / ppm, height: wall.heightInMeters,
                depth: wall.depthInMeters, centerY: wall.heightInMeters / 2,
                color: UIColor(red: 0.76, green: 0.79, blue: 0.84, alpha: 1),
                opacity: 0.52, name: "wall"
            )
        }

        for surface in geometry.surfaces where !surface.isWallGeometry {
            let representation = surface.effectiveRepresentation
            if representation == .beam || representation == .column {
                let height = representation == .beam
                    ? max(surface.heightInMeters * 0.12, 0.2) : surface.heightInMeters
                let y = representation == .beam
                    ? max(surface.heightInMeters - height / 2, height / 2) : height / 2
                addBox(
                    center: surface.center, angle: surface.angle,
                    width: surface.widthInMeters, height: height,
                    depth: surface.depthInMeters, centerY: y,
                    color: UIColor(red: 0.47, green: 0.31, blue: 0.72, alpha: 1),
                    name: representation == .beam ? "beamMarker" : "columnMarker"
                )
                continue
            }

            let color: UIColor
            let opacity: CGFloat
            let name: String
            if representation == .wideOpening {
                color = UIColor(red: 0.38, green: 0.72, blue: 0.69, alpha: 1)
                opacity = 0.18
                name = "wideOpening"
            } else {
                switch surface.source.category {
                case .door:
                    color = UIColor(red: 0.68, green: 0.39, blue: 0.22, alpha: 1)
                    opacity = 1
                    name = "door"
                case .opening:
                    color = UIColor(red: 0.38, green: 0.72, blue: 0.69, alpha: 1)
                    opacity = 0.24
                    name = "opening"
                case .window:
                    color = UIColor(red: 0.22, green: 0.57, blue: 0.86, alpha: 1)
                    opacity = surface.isFloorToCeilingGlass ? 0.45 : 0.72
                    name = "window"
                default:
                    continue
                }
            }
            let host = hostWall(for: surface, walls: walls, pointsPerMeter: ppm)
            // Project onto the host centre plane, not to a front-facing side.
            let center = host?.center ?? surface.center
            let hostDepth = host?.depth ?? surface.depthInMeters
            let depth = max(hostDepth, surface.depthInMeters) + 0.02
            addBox(
                center: center, angle: surface.angle,
                width: surface.widthInMeters, height: surface.heightInMeters,
                depth: depth,
                centerY: max(surface.heightInMeters / 2, surface.centerHeightInMeters),
                color: color, opacity: opacity, name: name
            )
        }

        for object in geometry.objects {
            addBox(
                center: object.center, angle: object.angle,
                width: object.widthInMeters, height: object.heightInMeters,
                depth: object.depthInMeters,
                centerY: max(object.heightInMeters / 2, object.centerHeightInMeters),
                color: furnitureColor(for: object.source.category),
                name: "furniture", rounded: true
            )
        }
        for object in geometry.manualObjects {
            addBox(
                center: object.center, angle: object.angle,
                width: object.widthInMeters, height: object.heightInMeters,
                depth: object.depthInMeters, centerY: object.heightInMeters / 2,
                color: furnitureColor(for: object.category),
                name: "manualFurniture", rounded: true
            )
        }
        bounds.finish()
        let floor = SCNFloor()
        floor.reflectivity = 0
        floor.firstMaterial = makeMaterial(
            color: UIColor(red: 0.91, green: 0.92, blue: 0.94, alpha: 1)
        )
        let floorNode = SCNNode(geometry: floor)
        floorNode.name = "floor"
        floorNode.position = SCNVector3(Float(bounds.midX), -0.002, Float(bounds.midZ))
        root.addChildNode(floorNode)
        return bounds
    }

    // Match parallel wall pieces by projected interval, not midpoint distance.
    // A window can be wider than an individual T-split wall piece.
    private func hostWall(
        for surface: FloorPlanSurfaceGeometry,
        walls: [FloorPlanWallSegment], pointsPerMeter: CGFloat
    ) -> (center: CGPoint, depth: CGFloat)? {
        guard surface.center.x.isFinite, surface.center.y.isFinite,
              surface.angle.isFinite, surface.halfLength.isFinite else { return nil }
        let sx = cos(surface.angle)
        let sy = sin(surface.angle)
        var bestDistance = CGFloat.greatestFiniteMagnitude
        var bestCenter: CGPoint?
        var hostDepth: CGFloat = 0
        for wall in walls {
            let length = wall.length
            guard length.isFinite, length > 1e-6,
                  wall.depthInMeters.isFinite, wall.depthInMeters > 0 else { continue }
            let ux = (wall.end.x - wall.start.x) / length
            let uy = (wall.end.y - wall.start.y) / length
            guard abs(sx * ux + sy * uy) >= cos(1.5 * .pi / 180) else { continue }
            let dx = surface.center.x - wall.start.x
            let dy = surface.center.y - wall.start.y
            let along = dx * ux + dy * uy
            let lateral = dx * (-uy) + dy * ux
            let reach = max(wall.depthInMeters / 2 + 0.08, 0.15) * pointsPerMeter
            guard lateral.isFinite, along.isFinite, abs(lateral) <= reach,
                  along + surface.halfLength >= 0,
                  along - surface.halfLength <= length else { continue }
            hostDepth = max(hostDepth, wall.depthInMeters)
            if abs(lateral) < bestDistance {
                bestDistance = abs(lateral)
                bestCenter = CGPoint(
                    x: wall.start.x + along * ux,
                    y: wall.start.y + along * uy
                )
            }
        }
        guard let center = bestCenter else { return nil }
        return (center, hostDepth)
    }

    private func positionInitialCamera(_ node: SCNNode, bounds: RoomBounds) {
        node.position = SCNVector3(
            Float(bounds.midX + bounds.span * 0.9),
            Float(max(bounds.maxHeight * 1.35, 3)),
            Float(bounds.midZ + bounds.span * 0.9)
        )
        node.look(at: SCNVector3(
            Float(bounds.midX), Float(bounds.maxHeight * 0.4), Float(bounds.midZ)
        ))
    }

    private func makeMaterial(color: UIColor, transparency: CGFloat = 1) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.8
        material.transparency = transparency
        material.isDoubleSided = true
        return material
    }

    private func furnitureColor(for category: CapturedRoom.Object.Category) -> UIColor {
        switch category {
        case .bed, .sofa, .chair:
            return UIColor(red: 0.78, green: 0.60, blue: 0.43, alpha: 1)
        case .storage, .refrigerator, .washerDryer, .dishwasher, .oven:
            return UIColor(red: 0.55, green: 0.62, blue: 0.69, alpha: 1)
        case .table, .stove, .sink, .toilet, .bathtub, .fireplace, .television, .stairs:
            return UIColor(red: 0.44, green: 0.58, blue: 0.50, alpha: 1)
        @unknown default:
            return UIColor(red: 0.62, green: 0.65, blue: 0.70, alpha: 1)
        }
    }
}
