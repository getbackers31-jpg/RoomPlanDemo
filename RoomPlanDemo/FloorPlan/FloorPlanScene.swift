import RoomPlan
import SpriteKit
import RealityKit
import SwiftUI

private struct SurfaceSnapshot {
    let position: CGPoint
    let zRotation: CGFloat
    let halfLength: CGFloat
    let openDirection: OpenDirection
}

private struct ObjectSnapshot {
    let position: CGPoint
    let zRotation: CGFloat
    let xScale: CGFloat
    let yScale: CGFloat
}

private struct SceneSnapshot {
    let surfaces: [ObjectIdentifier: SurfaceSnapshot]
    let objects: [ObjectIdentifier: ObjectSnapshot]
    let cameraRotation: CGFloat
}

final class FloorPlanScene: SKScene {
    let viewModel: FloorPlanViewModel
    private var previousCameraScale = CGFloat()
    private var previousCameraPosition = CGPoint()
    
    private let surfaces: [CapturedRoom.Surface]
    private let objects: [CapturedRoom.Object]
    private let capturedRoom: CapturedRoom
    
    private var gridNode: SKNode?
    private var exteriorDimensionsNode: SKNode?
    
    private var undoStack: [SceneSnapshot] = []
    private var redoStack: [SceneSnapshot] = []
    private var isDraggingObject: Bool = false
    
    init(capturedRoom: CapturedRoom, viewModel: FloorPlanViewModel) {
        self.capturedRoom = capturedRoom
        self.surfaces = capturedRoom.doors + capturedRoom.openings + capturedRoom.walls + capturedRoom.windows
        self.objects = capturedRoom.objects
        self.viewModel = viewModel
        
        super.init(size: DrawParameters.floorPlanSize)
        self.scaleMode = .aspectFill
        self.anchorPoint = DrawParameters.floorPlanAnchorPoint
        self.backgroundColor = DrawParameters.floorPlanBackgroundColor
        
        addCamera()
        drawBlueprintGrid()
        drawSurfaces()
        drawObjects()
        
        if let savedState = viewModel.initialEditState {
            applyEditState(savedState)
        } else if viewModel.autoOrthogonalizeOnLoad {
            orthogonalizeWalls()
            DispatchQueue.main.async { [weak self] in
                self?.viewModel.autoOrthogonalizeOnLoad = false
            }
        }
        
        recalculateAreaAndExteriorDimensions()
        recenterCamera(animated: false)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didMove(to view: SKView) {
        super.didMove(to: view)
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tapGesture)
        
        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(panGestureAction(_:)))
        view.addGestureRecognizer(panGestureRecognizer)
        
        let pinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(pinchGestureAction(_:)))
        view.addGestureRecognizer(pinchGestureRecognizer)
        
        let rotationGestureRecognizer = UIRotationGestureRecognizer(target: self, action: #selector(rotationGestureAction(_:)))
        view.addGestureRecognizer(rotationGestureRecognizer)
    }
}

// MARK: - 第二階段：專案存檔與狀態還原
extension FloorPlanScene {
    func exportEditState() -> FloorPlanEditState {
        var surfaceMap: [String: SavedSurfaceState] = [:]
        for node in children.compactMap({ $0 as? FloorPlanSurface }) {
            let key = node.capturedSurface.identifier.uuidString
            surfaceMap[key] = SavedSurfaceState(
                x: Double(node.position.x),
                y: Double(node.position.y),
                zRotation: Double(node.zRotation),
                halfLength: Double(node.halfLength)
            )
        }
        var objectMap: [String: SavedObjectState] = [:]
        for obj in children.compactMap({ $0 as? FloorPlanObject }) {
            let key = obj.capturedObject.identifier.uuidString
            objectMap[key] = SavedObjectState(
                x: Double(obj.position.x),
                y: Double(obj.position.y),
                zRotation: Double(obj.zRotation),
                xScale: Double(obj.xScale),
                yScale: Double(obj.yScale)
            )
        }
        return FloorPlanEditState(
            surfaces: surfaceMap,
            objects: objectMap,
            cameraRotation: Double(camera?.zRotation ?? 0)
        )
    }
    
    func applyEditState(_ state: FloorPlanEditState) {
        for node in children.compactMap({ $0 as? FloorPlanSurface }) {
            let key = node.capturedSurface.identifier.uuidString
            if let s = state.surfaces[key] {
                node.position = CGPoint(x: s.x, y: s.y)
                node.zRotation = CGFloat(s.zRotation)
                node.halfLength = CGFloat(s.halfLength)
                node.updateDimensionLabel()
            }
        }
        for obj in children.compactMap({ $0 as? FloorPlanObject }) {
            let key = obj.capturedObject.identifier.uuidString
            if let o = state.objects[key] {
                obj.position = CGPoint(x: o.x, y: o.y)
                obj.zRotation = CGFloat(o.zRotation)
                obj.xScale = CGFloat(o.xScale)
                obj.yScale = CGFloat(o.yScale)
                obj.updateSizeLabel()
            }
        }
        camera?.zRotation = CGFloat(state.cameraRotation)
    }
    
    func saveCurrentProject() {
        let editState = exportEditState()
        let saved = RoomProjectStore.shared.saveProject(
            existingID: viewModel.savedProjectID,
            name: viewModel.roomUsage,
            floorLabel: viewModel.floorLabel,
            areaPing: viewModel.roomAreaPing,
            areaSqm: viewModel.roomAreaSqm,
            capturedRoom: capturedRoom,
            editState: editState
        )
        DispatchQueue.main.async { [weak self] in
            if let project = saved {
                self?.viewModel.savedProjectID = project.id
                self?.viewModel.statusToastMessage = "已儲存「\(project.name)」至空間紀錄庫！"
            } else {
                self?.viewModel.statusToastMessage = "儲存失敗，請稍後再試"
            }
        }
    }
}

// MARK: - 藍圖格線、面積坪數計算與外圍工程尺寸線
extension FloorPlanScene {
    private func drawBlueprintGrid() {
        gridNode?.removeFromParent()
        let container = SKNode()
        container.zPosition = DrawParameters.gridZPosition
        
        let extent: CGFloat = 4000
        let minorStep: CGFloat = 100
        let majorStep: CGFloat = 200
        
        let minorPath = CGMutablePath()
        let majorPath = CGMutablePath()
        
        var coord = -extent
        while coord <= extent {
            let isMajor = Int(abs(coord)) % Int(majorStep) == 0
            let target = isMajor ? majorPath : minorPath
            target.move(to: CGPoint(x: coord, y: -extent))
            target.addLine(to: CGPoint(x: coord, y: extent))
            target.move(to: CGPoint(x: -extent, y: coord))
            target.addLine(to: CGPoint(x: extent, y: coord))
            coord += minorStep
        }
        
        let minorShape = SKShapeNode(path: minorPath)
        minorShape.strokeColor = AppTheme.gridMinor
        minorShape.lineWidth = 1.0
        
        let majorShape = SKShapeNode(path: majorPath)
        majorShape.strokeColor = AppTheme.gridMajor
        majorShape.lineWidth = 1.8
        
        container.addChild(minorShape)
        container.addChild(majorShape)
        addChild(container)
        gridNode = container
    }
    
    func recalculateAreaAndExteriorDimensions() {
        let wallNodes = children.compactMap { $0 as? FloorPlanSurface }.filter { $0.capturedSurface.category == .wall }
        guard !wallNodes.isEmpty else { return }
        
        var rawPoints: [CGPoint] = []
        for wall in wallNodes {
            let cosA = cos(wall.zRotation)
            let sinA = sin(wall.zRotation)
            let p1 = CGPoint(x: wall.position.x - wall.halfLength * cosA, y: wall.position.y - wall.halfLength * sinA)
            let p2 = CGPoint(x: wall.position.x + wall.halfLength * cosA, y: wall.position.y + wall.halfLength * sinA)
            rawPoints.append(p1)
            rawPoints.append(p2)
        }
        
        var vertices: [CGPoint] = []
        for pt in rawPoints {
            if !vertices.contains(where: { hypot($0.x - pt.x, $0.y - pt.y) < 30.0 }) {
                vertices.append(pt)
            }
        }
        
        let cx = vertices.reduce(CGFloat(0)) { $0 + $1.x } / CGFloat(max(vertices.count, 1))
        let cy = vertices.reduce(CGFloat(0)) { $0 + $1.y } / CGFloat(max(vertices.count, 1))
        
        let sortedVertices = vertices.sorted {
            atan2($0.y - cy, $0.x - cx) < atan2($1.y - cy, $1.x - cx)
        }
        
        var areaPt2: Double = 0.0
        if sortedVertices.count >= 3 {
            for i in 0..<sortedVertices.count {
                let j = (i + 1) % sortedVertices.count
                areaPt2 += Double(sortedVertices[i].x * sortedVertices[j].y - sortedVertices[j].x * sortedVertices[i].y)
            }
            areaPt2 = abs(areaPt2) * 0.5
        }
        
        let scaleSq = Double(DrawParameters.scalingFactor * DrawParameters.scalingFactor)
        let sqm = areaPt2 / scaleSq
        let ping = sqm * 0.3025
        
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.roomAreaSqm = sqm
            self?.viewModel.roomAreaPing = ping
        }
        
        drawExteriorDimensionLines(points: rawPoints)
    }
    
    private func drawExteriorDimensionLines(points: [CGPoint]) {
        exteriorDimensionsNode?.removeFromParent()
        guard !points.isEmpty else { return }
        
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        
        let widthPt = maxX - minX
        let heightPt = maxY - minY
        guard widthPt > 20 && heightPt > 20 else { return }
        
        let container = SKNode()
        container.zPosition = DrawParameters.dimensionZPosition
        container.isHidden = !viewModel.showDimensions
        
        let ptToCm = 100.0 / Double(DrawParameters.scalingFactor)
        let offsetOuter: CGFloat = 95.0
        
        addEngineeringDimLine(
            to: container,
            start: CGPoint(x: minX, y: maxY + offsetOuter),
            end: CGPoint(x: maxX, y: maxY + offsetOuter),
            extStartA: CGPoint(x: minX, y: maxY + 18),
            extStartB: CGPoint(x: maxX, y: maxY + 18),
            labelText: String(format: "%.0f", Double(widthPt) * ptToCm),
            isVertical: false
        )
        
        addEngineeringDimLine(
            to: container,
            start: CGPoint(x: minX, y: minY - offsetOuter),
            end: CGPoint(x: maxX, y: minY - offsetOuter),
            extStartA: CGPoint(x: minX, y: minY - 18),
            extStartB: CGPoint(x: maxX, y: minY - 18),
            labelText: String(format: "%.0f", Double(widthPt) * ptToCm),
            isVertical: false
        )
        
        addEngineeringDimLine(
            to: container,
            start: CGPoint(x: minX - offsetOuter, y: minY),
            end: CGPoint(x: minX - offsetOuter, y: maxY),
            extStartA: CGPoint(x: minX - 18, y: minY),
            extStartB: CGPoint(x: minX - 18, y: maxY),
            labelText: String(format: "%.0f", Double(heightPt) * ptToCm),
            isVertical: true
        )
        
        addEngineeringDimLine(
            to: container,
            start: CGPoint(x: maxX + offsetOuter, y: minY),
            end: CGPoint(x: maxX + offsetOuter, y: maxY),
            extStartA: CGPoint(x: maxX + 18, y: minY),
            extStartB: CGPoint(x: maxX + 18, y: maxY),
            labelText: String(format: "%.0f", Double(heightPt) * ptToCm),
            isVertical: true
        )
        
        addChild(container)
        exteriorDimensionsNode = container
    }
    
    private func addEngineeringDimLine(
        to container: SKNode,
        start: CGPoint,
        end: CGPoint,
        extStartA: CGPoint,
        extStartB: CGPoint,
        labelText: String,
        isVertical: Bool
    ) {
        let extPath = CGMutablePath()
        extPath.move(to: extStartA)
        extPath.addLine(to: start)
        extPath.move(to: extStartB)
        extPath.addLine(to: end)
        
        let extNode = SKShapeNode(path: extPath)
        extNode.strokeColor = AppTheme.dimensionLine.withAlphaComponent(0.45)
        extNode.lineWidth = 1.5
        container.addChild(extNode)
        
        let mainPath = CGMutablePath()
        mainPath.move(to: start)
        mainPath.addLine(to: end)
        
        let tick: CGFloat = 11.0
        for pt in [start, end] {
            mainPath.move(to: CGPoint(x: pt.x - tick, y: pt.y - tick))
            mainPath.addLine(to: CGPoint(x: pt.x + tick, y: pt.y + tick))
        }
        
        let mainNode = SKShapeNode(path: mainPath)
        mainNode.strokeColor = AppTheme.dimensionLine
        mainNode.lineWidth = 2.2
        container.addChild(mainNode)
        
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let labelNode = SKNode()
        labelNode.position = mid
        if isVertical { labelNode.zRotation = .pi / 2 }
        
        let label = SKLabelNode(fontNamed: "Helvetica-Bold")
        label.text = labelText
        label.fontSize = 24
        label.fontColor = AppTheme.dimensionText
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        
        let bgRect = CGRect(
            x: -label.frame.width / 2 - 10,
            y: -label.frame.height / 2 - 4,
            width: label.frame.width + 20,
            height: label.frame.height + 8
        )
        let bg = SKShapeNode(rect: bgRect, cornerRadius: 4)
        bg.fillColor = AppTheme.canvasBg
        bg.strokeColor = .clear
        bg.zPosition = -1
        
        labelNode.addChild(bg)
        labelNode.addChild(label)
        container.addChild(labelNode)
    }
}

// MARK: - 圖層開關、畫面置中、旋轉 90° 與 Undo / Redo
extension FloorPlanScene {
    func applyDisplaySettings(showFurniture: Bool, showDimensions: Bool, showFurnitureLabels: Bool) {
        let objectNodes = children.compactMap { $0 as? FloorPlanObject }
        for obj in objectNodes {
            obj.isHidden = !showFurniture
            obj.setLabelVisible(showFurnitureLabels)
        }
        
        let surfaceNodes = children.compactMap { $0 as? FloorPlanSurface }
        for surface in surfaceNodes {
            surface.setDimensionVisible(showDimensions)
        }
        
        exteriorDimensionsNode?.isHidden = !showDimensions
    }
    
    func rotateView90() {
        guard let camera = self.camera else { return }
        let target = camera.zRotation - (.pi / 2)
        let action = SKAction.rotate(toAngle: target, duration: 0.22, shortestUnitArc: true)
        camera.run(action)
    }
    
    func recenterCamera(animated: Bool = true) {
        guard let camera = self.camera else { return }
        let surfaceNodes = children.compactMap { $0 as? FloorPlanSurface }
        guard !surfaceNodes.isEmpty else { return }
        
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        
        for node in surfaceNodes {
            let cosA = cos(node.zRotation)
            let sinA = sin(node.zRotation)
            let pts = [
                CGPoint(x: node.position.x - node.halfLength * cosA, y: node.position.y - node.halfLength * sinA),
                CGPoint(x: node.position.x + node.halfLength * cosA, y: node.position.y + node.halfLength * sinA)
            ]
            for pt in pts {
                minX = min(minX, pt.x); maxX = max(maxX, pt.x)
                minY = min(minY, pt.y); maxY = max(maxY, pt.y)
            }
        }
        
        let center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let span = max(maxX - minX, maxY - minY) + 460
        let targetScale = max(0.35, min(2.6, span / 1100.0))
        
        if animated {
            let move = SKAction.move(to: center, duration: 0.25)
            let zoom = SKAction.scale(to: targetScale, duration: 0.25)
            camera.run(SKAction.group([move, zoom]))
        } else {
            camera.position = center
            camera.setScale(targetScale)
        }
    }
    
    private func captureSnapshot() -> SceneSnapshot {
        var surfaceMap: [ObjectIdentifier: SurfaceSnapshot] = [:]
        for node in children.compactMap({ $0 as? FloorPlanSurface }) {
            surfaceMap[ObjectIdentifier(node)] = SurfaceSnapshot(
                position: node.position,
                zRotation: node.zRotation,
                halfLength: node.halfLength,
                openDirection: node.openDirection
            )
        }
        var objectMap: [ObjectIdentifier: ObjectSnapshot] = [:]
        for obj in children.compactMap({ $0 as? FloorPlanObject }) {
            objectMap[ObjectIdentifier(obj)] = ObjectSnapshot(
                position: obj.position,
                zRotation: obj.zRotation,
                xScale: obj.xScale,
                yScale: obj.yScale
            )
        }
        return SceneSnapshot(surfaces: surfaceMap, objects: objectMap, cameraRotation: camera?.zRotation ?? 0)
    }
    
    private func pushUndoState() {
        undoStack.append(captureSnapshot())
        if undoStack.count > 25 { undoStack.removeFirst() }
        redoStack.removeAll()
        syncUndoRedoFlags()
    }
    
    private func restoreSnapshot(_ snapshot: SceneSnapshot) {
        for node in children.compactMap({ $0 as? FloorPlanSurface }) {
            if let state = snapshot.surfaces[ObjectIdentifier(node)] {
                node.position = state.position
                node.zRotation = state.zRotation
                node.openDirection = state.openDirection
                node.halfLength = state.halfLength
                node.updateDimensionLabel()
            }
        }
        for obj in children.compactMap({ $0 as? FloorPlanObject }) {
            if let state = snapshot.objects[ObjectIdentifier(obj)] {
                obj.position = state.position
                obj.zRotation = state.zRotation
                obj.xScale = state.xScale
                obj.yScale = state.yScale
                obj.updateSizeLabel()
            }
        }
        camera?.zRotation = snapshot.cameraRotation
        recalculateAreaAndExteriorDimensions()
    }
    
    private func syncUndoRedoFlags() {
        let canU = !undoStack.isEmpty
        let canR = !redoStack.isEmpty
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.canUndo = canU
            self?.viewModel.canRedo = canR
        }
    }
    
    func performUndo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(captureSnapshot())
        restoreSnapshot(previous)
        syncUndoRedoFlags()
        viewModel.statusToastMessage = "已復原上一步"
    }
    
    func performRedo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(captureSnapshot())
        restoreSnapshot(next)
        syncUndoRedoFlags()
        viewModel.statusToastMessage = "已重做操作"
    }
}

// MARK: - 核心工程演算法：正交直角對齊 & 單邊基準尺全域縮放
extension FloorPlanScene {
    func orthogonalizeWalls() {
        let surfaceNodes = children.compactMap { $0 as? FloorPlanSurface }
        let wallNodes = surfaceNodes.filter { $0.capturedSurface.category == .wall }
        guard let primaryWall = wallNodes.max(by: { $0.halfLength < $1.halfLength }) else { return }
        
        pushUndoState()
        
        let baseAngle = primaryWall.zRotation
        let snapStep: CGFloat = .pi / 2
        let maxDeviation: CGFloat = 20.0 * (.pi / 180.0)
        var alignedCount = 0
        
        for node in surfaceNodes {
            let diff = node.zRotation - baseAngle
            let nearestQuarter = round(diff / snapStep) * snapStep
            let residual = atan2(sin(diff - nearestQuarter), cos(diff - nearestQuarter))
            
            if abs(residual) <= maxDeviation {
                node.zRotation = baseAngle + nearestQuarter
                node.updateDimensionLabel()
                alignedCount += 1
            }
        }
        
        if let camera = self.camera {
            camera.zRotation = baseAngle
        }
        
        recalculateAreaAndExteriorDimensions()
        viewModel.statusToastMessage = "已完成 \(alignedCount) 面牆體與門窗正交直角對齊"
    }
    
    func calibrateWholeRoom(by ratio: CGFloat) {
        guard ratio > 0.1 && ratio < 10.0 else { return }
        let surfaceNodes = children.compactMap { $0 as? FloorPlanSurface }
        let objectNodes = children.compactMap { $0 as? FloorPlanObject }
        guard !surfaceNodes.isEmpty else { return }
        
        pushUndoState()
        
        let sumX = surfaceNodes.reduce(CGFloat(0)) { $0 + $1.position.x }
        let sumY = surfaceNodes.reduce(CGFloat(0)) { $0 + $1.position.y }
        let center = CGPoint(x: sumX / CGFloat(surfaceNodes.count), y: sumY / CGFloat(surfaceNodes.count))
        
        for surface in surfaceNodes {
            surface.applyGlobalScale(ratio: ratio, around: center)
        }
        
        for obj in objectNodes {
            obj.applyGlobalScale(ratio: ratio, around: center)
        }
        
        recalculateAreaAndExteriorDimensions()
        viewModel.statusToastMessage = String(format: "已依基準尺全域縮放校準 (比例 %.3fx)", Double(ratio))
    }
}

private extension FloorPlanScene {
    func drawSurfaces() {
        for surface in surfaces {
            addChild(FloorPlanSurface(capturedSurface: surface))
        }
    }
    
    func drawObjects() {
        for object in objects {
            addChild(FloorPlanObject(capturedObject: object))
        }
    }
    
    func selectSurface(_ surfaceNode: FloorPlanSurface) {
        deselectSurface()
        surfaceNode.select()
        viewModel.selectedSurface = surfaceNode
    }
    
    func deselectSurface() {
        viewModel.selectedSurface?.deselect()
        viewModel.selectedSurface = nil
    }
    
    func selectObject(_ objectNode: FloorPlanObject) {
        deselectObject()
        objectNode.select()
        viewModel.selectedObject = objectNode
    }
    
    func deselectObject() {
        viewModel.selectedObject?.deselect()
        viewModel.selectedObject = nil
    }
    
    func selectAnnotation(_ annotationNode: FloorPlanAnnotation) {
        deselectAnnotation()
        annotationNode.highlight()
        viewModel.selectedAnnotation = annotationNode
    }
    
    func deselectAnnotation() {
        viewModel.selectedAnnotation?.removeHighlight()
        viewModel.selectedAnnotation = nil
    }
}

private extension FloorPlanScene {
    @objc func panGestureAction(_ sender: UIPanGestureRecognizer) {
        let locationInView = sender.location(in: view)
        let locationInScene = convertPoint(fromView: locationInView)
        
        if let selectedObject = viewModel.selectedObject, selectedObject.contains(locationInScene) || isDraggingObject {
            switch sender.state {
            case .began:
                isDraggingObject = true
                pushUndoState()
            case .changed:
                selectedObject.position = locationInScene
            case .ended, .cancelled:
                isDraggingObject = false
            default:
                break
            }
            return
        }
        
        if let annotationNode = viewModel.selectedAnnotation, annotationNode.contains(locationInScene) {
            if sender.state == .changed { annotationNode.position = locationInScene }
            return
        }
        
        guard let camera = self.camera else { return }
        switch sender.state {
        case .began:
            previousCameraPosition = camera.position
        case .changed:
            let translation = sender.translation(in: self.view)
            let rotationAngle = -camera.zRotation
            let rotatedTranslation = CGPoint(
                x: translation.x * cos(rotationAngle) - translation.y * sin(rotationAngle),
                y: translation.x * sin(rotationAngle) + translation.y * cos(rotationAngle)
            )
            let translationScale = camera.xScale
            camera.position = CGPoint(
                x: previousCameraPosition.x - rotatedTranslation.x * translationScale,
                y: previousCameraPosition.y - -rotatedTranslation.y * translationScale
            )
        default: break
        }
    }
    
    @objc func pinchGestureAction(_ sender: UIPinchGestureRecognizer) {
        guard let camera = self.camera else { return }
        if sender.state == .began { previousCameraScale = camera.xScale }
        camera.setScale(previousCameraScale * 1 / sender.scale)
    }
    
    @objc func rotationGestureAction(_ sender: UIRotationGestureRecognizer) {
        guard let camera = self.camera else { return }
        if sender.state == .began || sender.state == .changed {
            camera.zRotation += sender.rotation
            sender.rotation = 0
        }
    }
    
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let view = self.view else { return }
        let locationInScene = convertPoint(fromView: gesture.location(in: view))
        
        if let surfaceNode = nodes(at: locationInScene).compactMap({ $0 as? FloorPlanSurface }).first {
            deselectObject(); deselectAnnotation(); selectSurface(surfaceNode)
        } else { deselectSurface() }
        
        if let objectNode = nodes(at: locationInScene).compactMap({ $0 as? FloorPlanObject }).first {
            deselectSurface(); deselectAnnotation(); selectObject(objectNode)
        } else { deselectObject() }
        
        if let annotationNode = nodes(at: locationInScene).compactMap({ $0 as? FloorPlanAnnotation }).first {
            deselectSurface(); deselectObject(); selectAnnotation(annotationNode)
        } else { deselectAnnotation() }
    }
}

private extension FloorPlanScene {
    func addCamera() {
        let cameraNode = SKCameraNode()
        addChild(cameraNode)
        self.camera = cameraNode
    }
}

// MARK: - 匯出圖檔 & AutoCAD DXF 產生器
extension FloorPlanScene {
    func addNewObject(with category: CapturedRoom.Object.Category) {
        guard let camera = self.camera, let firstObject = objects.first else { return }
        let newFloorPlanObject = FloorPlanObject(capturedObject: firstObject, withCategory: category, objectPosition: camera.position)
        newFloorPlanObject.isHidden = !viewModel.showFurniture
        newFloorPlanObject.setLabelVisible(viewModel.showFurnitureLabels)
        addChild(newFloorPlanObject)
    }
    
    func addExampleAnnotations() {
        guard let camera = self.camera else { return }
        let annotation = FloorPlanAnnotation(title: "區域標註", subtitle: "點擊編輯文字", fontSize: 36, fontColor: AppTheme.windowStroke)
        annotation.position = camera.position
        addChild(annotation)
    }
    
    func exportImage(with format: ImageFormat) {
        if format == .dxf {
            let dxfString = generateDXF()
            guard let data = dxfString.data(using: .utf8) else { return }
            let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("floorPlan.dxf")
            do {
                try data.write(to: fileURL)
                presentShareSheet(with: fileURL)
            } catch {
                print("Error saving DXF: \(error.localizedDescription)")
            }
            return
        }
        
        guard let snapshot = snapshot() else { return }
        var imageData: Data?
        switch format {
        case .png: imageData = snapshot.pngData()
        case .jpeg: imageData = snapshot.jpegData(compressionQuality: 1.0)
        case .pdf:
            let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: snapshot.size))
            imageData = pdfRenderer.pdfData { context in
                context.beginPage()
                snapshot.draw(in: CGRect(origin: .zero, size: snapshot.size))
            }
        case .dxf:
            return
        }
        guard let data = imageData else { return }
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("floorPlan.\(format.rawValue)")
        do {
            try data.write(to: fileURL)
            presentShareSheet(with: fileURL)
        } catch {
            print("Error saving image: \(error.localizedDescription)")
        }
    }
    
    func generateDXF() -> String {
        let ptToCm = 100.0 / Double(DrawParameters.scalingFactor)
        
        func fmt(_ v: Double) -> String { String(format: "%.2f", v) }
        func normalizeDeg(_ deg: Double) -> Double {
            var d = deg.truncatingRemainder(dividingBy: 360.0)
            if d < 0 { d += 360.0 }
            return d
        }
        
        var lines: [String] = []
        func addLine(layer: String, x1: Double, y1: Double, x2: Double, y2: Double) {
            lines.append(contentsOf: [
                "0", "LINE",
                "8", layer,
                "10", fmt(x1), "20", fmt(y1), "30", "0.0",
                "11", fmt(x2), "21", fmt(y2), "31", "0.0"
            ])
        }
        
        func addArc(layer: String, cx: Double, cy: Double, radius: Double, startDeg: Double, endDeg: Double) {
            lines.append(contentsOf: [
                "0", "ARC",
                "8", layer,
                "10", fmt(cx), "20", fmt(cy), "30", "0.0",
                "40", fmt(radius),
                "50", fmt(startDeg),
                "51", fmt(endDeg)
            ])
        }
        
        func addText(layer: String, x: Double, y: Double, height: Double, angleDeg: Double, text: String) {
            lines.append(contentsOf: [
                "0", "TEXT",
                "8", layer,
                "10", fmt(x), "20", fmt(y), "30", "0.0",
                "40", fmt(height),
                "50", fmt(angleDeg),
                "1", text
            ])
        }
        
        lines.append(contentsOf: [
            "0", "SECTION",
            "2", "HEADER",
            "9", "$INSUNITS",
            "70", "5",
            "0", "ENDSEC"
        ])
        
        let layerDefs: [(String, String)] = [
            ("WALLS", "7"),
            ("DOORS", "1"),
            ("WINDOWS", "5"),
            ("DIMENSIONS", "3"),
            ("FURNITURE", "8")
        ]
        lines.append(contentsOf: ["0", "SECTION", "2", "TABLES", "0", "TABLE", "2", "LAYER", "70", "\(layerDefs.count)"])
        for (name, color) in layerDefs {
            lines.append(contentsOf: ["0", "LAYER", "2", name, "70", "0", "62", color, "6", "CONTINUOUS"])
        }
        lines.append(contentsOf: ["0", "ENDTAB", "0", "ENDSEC"])
        
        lines.append(contentsOf: ["0", "SECTION", "2", "ENTITIES"])
        
        let surfaceNodes = children.compactMap { $0 as? FloorPlanSurface }
        for surface in surfaceNodes {
            let cx = Double(surface.position.x) * ptToCm
            let cy = Double(surface.position.y) * ptToCm
            let halfLen = Double(surface.halfLength) * ptToCm
            let angle = Double(surface.zRotation)
            let cosA = cos(angle)
            let sinA = sin(angle)
            
            let ax = cx - halfLen * cosA
            let ay = cy - halfLen * sinA
            let bx = cx + halfLen * cosA
            let by = cy + halfLen * sinA
            
            switch surface.capturedSurface.category {
            case .wall:
                addLine(layer: "WALLS", x1: ax, y1: ay, x2: bx, y2: by)
                
                var angleDeg = angle * 180.0 / .pi
                angleDeg = angleDeg.truncatingRemainder(dividingBy: 360.0)
                if angleDeg > 180 { angleDeg -= 360 }
                if angleDeg < -180 { angleDeg += 360 }
                var textAngle = angleDeg
                var offsetDist = 18.0
                if textAngle > 90 { textAngle -= 180; offsetDist = -18.0 }
                if textAngle < -90 { textAngle += 180; offsetDist = -18.0 }
                
                let tx = cx - sinA * offsetDist
                let ty = cy + cosA * offsetDist
                let lengthText = String(format: "%.1f cm", halfLen * 2.0)
                addText(layer: "DIMENSIONS", x: tx, y: ty, height: 12.0, angleDeg: normalizeDeg(textAngle), text: lengthText)
                
            case .door:
                let lengthCm = halfLen * 2.0
                let openAngle = Double(surface.openDirection.angle)
                let doorEndX = ax + lengthCm * cos(angle + openAngle)
                let doorEndY = ay + lengthCm * sin(angle + openAngle)
                addLine(layer: "DOORS", x1: ax, y1: ay, x2: doorEndX, y2: doorEndY)
                
                let zRotDeg = angle * 180.0 / .pi
                let startDeg = surface.openDirection == .clockwise ? normalizeDeg(zRotDeg - 45.0) : normalizeDeg(zRotDeg)
                let endDeg = surface.openDirection == .clockwise ? normalizeDeg(zRotDeg) : normalizeDeg(zRotDeg + 45.0)
                addArc(layer: "DOORS", cx: ax, cy: ay, radius: lengthCm, startDeg: startDeg, endDeg: endDeg)
                
            case .window:
                addLine(layer: "WINDOWS", x1: ax, y1: ay, x2: bx, y2: by)
                
            default:
                break
            }
        }
        
        let objectNodes = children.compactMap { $0 as? FloorPlanObject }
        for obj in objectNodes where !obj.isHidden {
            let cx = Double(obj.position.x) * ptToCm
            let cy = Double(obj.position.y) * ptToCm
            let hw = Double(obj.capturedObject.dimensions.x) * 100.0 * Double(abs(obj.xScale)) / 2.0
            let hh = Double(obj.capturedObject.dimensions.z) * 100.0 * Double(abs(obj.yScale)) / 2.0
            let angle = Double(obj.zRotation)
            let cosA = cos(angle)
            let sinA = sin(angle)
            
            let localCorners = [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)]
            let worldCorners = localCorners.map { (lx, ly) in
                (cx + lx * cosA - ly * sinA, cy + lx * sinA + ly * cosA)
            }
            for i in 0..<4 {
                let p1 = worldCorners[i]
                let p2 = worldCorners[(i + 1) % 4]
                addLine(layer: "FURNITURE", x1: p1.0, y1: p1.1, x2: p2.0, y2: p2.1)
            }
        }
        
        lines.append(contentsOf: ["0", "ENDSEC", "0", "EOF"])
        return lines.joined(separator: "\r\n")
    }
    
    func presentShareSheet(with fileURL: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else { return }
        let activityViewController = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        rootViewController.present(activityViewController, animated: true, completion: nil)
    }
    
    func snapshot() -> UIImage? {
        guard let view = self.view,
              let texture = view.texture(from: self, crop: CGRect(origin: .zero, size: self.size)) else { return nil }
        return UIImage(cgImage: texture.cgImage())
    }
}