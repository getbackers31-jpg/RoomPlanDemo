import RoomPlan
import SceneKit
import SwiftUI
import UIKit

struct FloorPlan3DPreviewView: UIViewRepresentable {
    let capturedRoom: CapturedRoom
    let editState: FloorPlanEditState

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = makeScene()
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.backgroundColor = UIColor(red: 0.91, green: 0.93, blue: 0.96, alpha: 1)
        scnView.antialiasingMode = .multisampling4X
        return scnView
    }

    func updateUIView(_ scnView: SCNView, context: Context) {}

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        let rootNode = scene.rootNode
        let scale = CGFloat(DrawParameters.scalingFactor)
        let geometry = FloorPlanGeometry(
            capturedRoom: capturedRoom,
            editState: editState
        )

        var minX = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude
        var maxZ = -Float.greatestFiniteMagnitude
        var maxHeight: Float = 2.6

        func includeBounds(x: Float, z: Float, radius: Float) {
            minX = min(minX, x - radius)
            maxX = max(maxX, x + radius)
            minZ = min(minZ, z - radius)
            maxZ = max(maxZ, z + radius)
        }

        for wall in geometry.joinedWallSegments {
            let width = max(wall.length / scale, 0.12)
            let height = max(wall.heightInMeters, 0.1)
            let depth = max(wall.depthInMeters, 0.08)
            let center = CGPoint(
                x: -wall.midpoint.x / scale,
                y: -wall.midpoint.y / scale
            )
            let yaw = -wall.angle
            let box = SCNBox(width: width, height: height, length: depth, chamferRadius: 0)
            box.firstMaterial = makeMaterial(
                color: UIColor(red: 0.76, green: 0.79, blue: 0.84, alpha: 1),
                transparency: 0.52
            )
            let node = SCNNode(geometry: box)
            node.position = SCNVector3(Float(center.x), Float(height / 2), Float(center.y))
            node.eulerAngles = SCNVector3(0, Float(yaw), 0)
            node.name = "wall"
            rootNode.addChildNode(node)

            includeBounds(
                x: Float(center.x),
                z: Float(center.y),
                radius: Float(width / 2 + depth)
            )
            maxHeight = max(maxHeight, Float(height))
        }

        for surface in geometry.surfaces where !surface.isWallGeometry {
            let representation = surface.effectiveRepresentation
            if representation == .wideOpening {
                continue
            }
            if representation == .beam || representation == .column {
                let width = max(surface.widthInMeters, 0.12)
                let depth = max(surface.depthInMeters, 0.08)
                let height = representation == .beam
                    ? max(surface.heightInMeters * 0.12, 0.2)
                    : surface.heightInMeters
                let worldCenter = surface.worldCenter
                let centerY = representation == .beam
                    ? max(surface.heightInMeters - height / 2, height / 2)
                    : height / 2
                let box = SCNBox(width: width, height: height, length: depth, chamferRadius: 0)
                box.firstMaterial = makeMaterial(color: UIColor(red: 0.47, green: 0.31, blue: 0.72, alpha: 1))
                let node = SCNNode(geometry: box)
                node.position = SCNVector3(Float(worldCenter.x), Float(centerY), Float(worldCenter.y))
                node.eulerAngles = SCNVector3(0, Float(-surface.angle), 0)
                node.name = representation == .beam ? "beamMarker" : "columnMarker"
                rootNode.addChildNode(node)
                includeBounds(
                    x: Float(worldCenter.x),
                    z: Float(worldCenter.y),
                    radius: Float(width / 2 + depth)
                )
                maxHeight = max(maxHeight, Float(centerY + height / 2))
                continue
            }

            let isDoor: Bool
            let isOpening: Bool
            let color: UIColor
            let transparency: CGFloat
            switch surface.source.category {
            case .wall:
                continue
            case .door:
                isDoor = true
                isOpening = false
                color = UIColor(red: 0.68, green: 0.39, blue: 0.22, alpha: 1)
                transparency = 1
            case .opening:
                isDoor = false
                isOpening = true
                color = UIColor(red: 0.38, green: 0.72, blue: 0.69, alpha: 1)
                transparency = 0.24
            case .window:
                isDoor = false
                isOpening = false
                color = UIColor(red: 0.22, green: 0.57, blue: 0.86, alpha: 1)
                transparency = surface.isFloorToCeilingGlass ? 0.45 : 0.72
            default:
                continue
            }

            let centerX = Float(surface.worldCenter.x)
            let centerZ = Float(surface.worldCenter.y)
            let yaw = Float(-surface.angle)
            let width = max(surface.widthInMeters, 0.1)
            let height = surface.heightInMeters
            let depth = max(surface.depthInMeters, 0.08)
            let centerY = max(height / 2, surface.centerHeightInMeters)

            let boxDepth = max(depth, 0.06)
            let box = SCNBox(
                width: width,
                height: height,
                length: boxDepth,
                chamferRadius: 0
            )
            box.firstMaterial = makeMaterial(color: color, transparency: transparency)
            let node = SCNNode(geometry: box)
            let frontOffset = Float(boxDepth / 2 + 0.008)
            node.position = SCNVector3(
                centerX + sin(yaw) * frontOffset,
                Float(centerY),
                centerZ + cos(yaw) * frontOffset
            )
            node.eulerAngles = SCNVector3(0, yaw, 0)
            node.name = isDoor ? "door" : isOpening ? "opening" : "window"
            rootNode.addChildNode(node)

            let horizontalRadius = Float(width / 2 + boxDepth)
            includeBounds(x: centerX, z: centerZ, radius: horizontalRadius)
            maxHeight = max(maxHeight, Float(centerY + height / 2))
        }

        for object in geometry.objects {
            let width = max(object.widthInMeters, 0.2)
            let height = object.heightInMeters
            let depth = max(object.depthInMeters, 0.2)
            let centerX = Float(object.worldCenter.x)
            let centerZ = Float(object.worldCenter.y)
            let centerY = max(height / 2, object.centerHeightInMeters)

            let box = SCNBox(width: width, height: height, length: depth, chamferRadius: 0.025)
            box.firstMaterial = makeMaterial(color: furnitureColor(for: object.source.category))
            let node = SCNNode(geometry: box)
            node.position = SCNVector3(centerX, Float(centerY), centerZ)
            node.eulerAngles = SCNVector3(0, Float(-object.angle), 0)
            node.name = "furniture"
            rootNode.addChildNode(node)

            let horizontalRadius = (width * width + depth * depth).squareRoot() / 2
            includeBounds(x: centerX, z: centerZ, radius: Float(horizontalRadius))
            maxHeight = max(maxHeight, Float(centerY + height / 2))
        }

        for manualObject in geometry.manualObjects {
            let width = max(manualObject.widthInMeters, 0.2)
            let depth = max(manualObject.depthInMeters, 0.2)
            let height = manualObject.heightInMeters
            let centerX = Float(manualObject.worldCenter.x)
            let centerZ = Float(manualObject.worldCenter.y)
            let box = SCNBox(width: width, height: height, length: depth, chamferRadius: 0.025)
            box.firstMaterial = makeMaterial(color: furnitureColor(for: manualObject.category))
            let node = SCNNode(geometry: box)
            node.position = SCNVector3(centerX, Float(height / 2), centerZ)
            node.eulerAngles = SCNVector3(0, Float(-manualObject.angle), 0)
            node.name = "manualFurniture"
            rootNode.addChildNode(node)

            includeBounds(
                x: centerX,
                z: centerZ,
                radius: Float((width * width + depth * depth).squareRoot() / 2)
            )
            maxHeight = max(maxHeight, Float(height))
        }

        if minX == Float.greatestFiniteMagnitude {
            minX = -2
            maxX = 2
            minZ = -2
            maxZ = 2
        }

        let centerX = (minX + maxX) / 2
        let centerZ = (minZ + maxZ) / 2
        let roomSpan = max(max(maxX - minX, maxZ - minZ), 3)

        let floor = SCNFloor()
        floor.firstMaterial = makeMaterial(color: UIColor(red: 0.91, green: 0.92, blue: 0.94, alpha: 1))
        floor.reflectivity = 0
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(centerX, 0, centerZ)
        rootNode.addChildNode(floorNode)

        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = UIColor(white: 1, alpha: 1)
        ambientLight.intensity = 500
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        rootNode.addChildNode(ambientNode)

        let directionalLight = SCNLight()
        directionalLight.type = .directional
        directionalLight.intensity = 900
        let directionalNode = SCNNode()
        directionalNode.light = directionalLight
        directionalNode.position = SCNVector3(centerX + roomSpan, maxHeight * 2, centerZ + roomSpan)
        directionalNode.look(at: SCNVector3(centerX, 0, centerZ))
        rootNode.addChildNode(directionalNode)

        let camera = SCNCamera()
        camera.zFar = 1000
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(
            centerX + roomSpan * 0.9,
            max(maxHeight * 1.35, 3),
            centerZ + roomSpan * 0.9
        )
        cameraNode.look(at: SCNVector3(centerX, maxHeight * 0.4, centerZ))
        rootNode.addChildNode(cameraNode)

        return scene
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
