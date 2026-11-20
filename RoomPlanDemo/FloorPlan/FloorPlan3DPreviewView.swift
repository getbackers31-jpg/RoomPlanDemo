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

        for surface in capturedRoom.walls + capturedRoom.doors + capturedRoom.openings + capturedRoom.windows {
            let isWall: Bool
            let isDoor: Bool
            let isOpening: Bool
            let color: UIColor
            let transparency: CGFloat
            switch surface.category {
            case .wall:
                isWall = true
                isDoor = false
                isOpening = false
                color = UIColor(red: 0.76, green: 0.79, blue: 0.84, alpha: 1)
                transparency = 0.52
            case .door:
                isWall = false
                isDoor = true
                isOpening = false
                color = UIColor(red: 0.68, green: 0.39, blue: 0.22, alpha: 1)
                transparency = 1
            case .opening:
                isWall = false
                isDoor = false
                isOpening = true
                color = UIColor(red: 0.38, green: 0.72, blue: 0.69, alpha: 1)
                transparency = 0.24
            case .window:
                isWall = false
                isDoor = false
                isOpening = false
                color = UIColor(red: 0.22, green: 0.57, blue: 0.86, alpha: 1)
                transparency = 0.72
            default:
                continue
            }

            let savedState = editState.surfaces[surface.identifier.uuidString]
            let planX = CGFloat(savedState?.x ?? Double(-CGFloat(surface.transform.position.x) * scale))
            let planY = CGFloat(savedState?.y ?? Double(CGFloat(surface.transform.position.z) * scale))
            let centerX = Float(-planX / scale)
            let centerZ = Float(-planY / scale)
            let planAngle = CGFloat(
                savedState?.zRotation
                    ?? Double(-CGFloat(surface.transform.eulerAngles.z - surface.transform.eulerAngles.y))
            )
            let yaw = Float(-planAngle)
            let savedWidth = savedState.map { $0.halfLength * 2 } ?? Double(surface.dimensions.x)
            let width = max(CGFloat(savedWidth), 0.1)
            let fallbackHeight: CGFloat = isWall ? 2.6 : (isDoor || isOpening) ? 2.05 : 1.2
            let measuredHeight = CGFloat(surface.dimensions.y)
            let height = measuredHeight.isFinite && measuredHeight > 0.1 ? measuredHeight : fallbackHeight
            let depth = max(CGFloat(surface.dimensions.z), 0.08)
            let centerY = max(height / 2, CGFloat(surface.transform.position.y))

            let boxDepth = isWall ? depth : max(depth, 0.06)
            let box = SCNBox(
                width: width,
                height: height,
                length: boxDepth,
                chamferRadius: 0
            )
            box.firstMaterial = makeMaterial(color: color, transparency: transparency)
            let node = SCNNode(geometry: box)
            let frontOffset: Float = isWall ? 0 : Float(boxDepth / 2 + 0.008)
            node.position = SCNVector3(
                centerX + sin(yaw) * frontOffset,
                Float(centerY),
                centerZ + cos(yaw) * frontOffset
            )
            node.eulerAngles = SCNVector3(0, yaw, 0)
            node.name = isWall ? "wall" : isDoor ? "door" : isOpening ? "opening" : "window"
            rootNode.addChildNode(node)

            let horizontalRadius = Float(width / 2 + boxDepth)
            includeBounds(x: centerX, z: centerZ, radius: horizontalRadius)
            maxHeight = max(maxHeight, Float(centerY + height / 2))
        }

        for object in capturedRoom.objects {
            let savedState = editState.objects[object.identifier.uuidString]
            let width = max(CGFloat(object.dimensions.x) * CGFloat(abs(savedState?.xScale ?? 1)), 0.2)
            let height = max(CGFloat(object.dimensions.y), 0.25)
            let depth = max(CGFloat(object.dimensions.z) * CGFloat(abs(savedState?.yScale ?? 1)), 0.2)
            let planX = CGFloat(savedState?.x ?? Double(-CGFloat(object.transform.position.x) * scale))
            let planY = CGFloat(savedState?.y ?? Double(CGFloat(object.transform.position.z) * scale))
            let centerX = Float(-planX / scale)
            let centerZ = Float(-planY / scale)
            let planAngle = CGFloat(
                savedState?.zRotation
                    ?? Double(-CGFloat(object.transform.eulerAngles.z - object.transform.eulerAngles.y))
            )
            let centerY = max(height / 2, CGFloat(object.transform.position.y))

            let box = SCNBox(width: width, height: height, length: depth, chamferRadius: 0.025)
            box.firstMaterial = makeMaterial(color: furnitureColor(for: object.category))
            let node = SCNNode(geometry: box)
            node.position = SCNVector3(centerX, Float(centerY), centerZ)
            node.eulerAngles = SCNVector3(0, Float(-planAngle), 0)
            node.name = "furniture"
            rootNode.addChildNode(node)

            let horizontalRadius = (width * width + depth * depth).squareRoot() / 2
            includeBounds(x: centerX, z: centerZ, radius: Float(horizontalRadius))
            maxHeight = max(maxHeight, Float(centerY + height / 2))
        }

        if let manualObjects = editState.manualObjects {
            for manualObject in manualObjects {
                guard let category = try? JSONDecoder().decode(
                    CapturedRoom.Object.Category.self,
                    from: manualObject.categoryData
                ) else {
                    continue
                }

                let width = max(abs(Float(manualObject.xScale)) * 80 / Float(scale), 0.2)
                let depth = max(abs(Float(manualObject.yScale)) * 60 / Float(scale), 0.2)
                let height: Float = 0.75
                let centerX = Float(-manualObject.x / Double(scale))
                let centerZ = Float(-manualObject.y / Double(scale))
                let centerY = height / 2
                let box = SCNBox(
                    width: CGFloat(width),
                    height: CGFloat(height),
                    length: CGFloat(depth),
                    chamferRadius: 0.025
                )
                box.firstMaterial = makeMaterial(color: furnitureColor(for: category))
                let node = SCNNode(geometry: box)
                node.position = SCNVector3(centerX, centerY, centerZ)
                node.eulerAngles = SCNVector3(0, Float(-manualObject.zRotation), 0)
                node.name = "manualFurniture"
                rootNode.addChildNode(node)

                includeBounds(x: centerX, z: centerZ, radius: (width * width + depth * depth).squareRoot() / 2)
                maxHeight = max(maxHeight, height)
            }
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
