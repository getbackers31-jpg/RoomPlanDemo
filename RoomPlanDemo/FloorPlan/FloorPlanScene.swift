import UIKit
import RoomPlan
import SpriteKit
import RealityKit
import SwiftUI

final class FloorPlanScene: SKScene {
    let viewModel: FloorPlanViewModel
    let capturedRoom: CapturedRoom

    private var previousCameraScale = CGFloat()
    private var previousCameraPosition = CGPoint()
    private var gridNode: SKNode?
    private var wallJointNode: SKShapeNode?
    private var exteriorDimensionsNode: SKNode?
    private var undoStack: [FloorPlanEditState] = []
    private var redoStack: [FloorPlanEditState] = []
    private var continuousEditStart: FloorPlanEditState?
    private var isRestoringState = false
    private var isDraggingObject = false
    private var isDraggingAnnotation = false
    private var handledCalibrationRequestIDs = Set<UUID>()

    init(capturedRoom: CapturedRoom, viewModel: FloorPlanViewModel) {
        self.capturedRoom = capturedRoom
        self.viewModel = viewModel
        super.init(size: DrawParameters.floorPlanSize)
        scaleMode = .aspectFill
        anchorPoint = DrawParameters.floorPlanAnchorPoint
        backgroundColor = DrawParameters.floorPlanBackgroundColor

        addCamera()
        drawBlueprintGrid()
        drawSurfaces()
        drawObjects()
        if let state = viewModel.initialEditState {
            applyEditState(state, recalculateArea: false)
        }
        recenterCamera(animated: false)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.recalculateAreaAndExteriorDimensions()
            self.syncUndoRedoFlags()
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        view.gestureRecognizers?.forEach { recognizer in
            if recognizer.view === view,
               recognizer.delegate === nil,
               recognizer.name?.hasPrefix("FloorPlanScene.") == true {
                view.removeGestureRecognizer(recognizer)
            }
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.name = "FloorPlanScene.tap"
        view.addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panGestureAction(_:)))
        pan.name = "FloorPlanScene.pan"
        view.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinchGestureAction(_:)))
        pinch.name = "FloorPlanScene.pinch"
        view.addGestureRecognizer(pinch)
        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(rotationGestureAction(_:)))
        rotation.name = "FloorPlanScene.rotation"
        view.addGestureRecognizer(rotation)
    }
}

// MARK: - Stable identities and node lookup

private extension FloorPlanScene {
    static let manualObjectIDKey = "manualObjectID"
    static let manualCategoryDataKey = "manualCategoryData"
    static let annotationIDKey = "annotationID"

    var surfaceNodes: [FloorPlanSurface] {
        children.compactMap { $0 as? FloorPlanSurface }
    }

    var objectNodes: [FloorPlanObject] {
        children.compactMap { $0 as? FloorPlanObject }
    }

    var annotationNodes: [FloorPlanAnnotation] {
        children.compactMap { $0 as? FloorPlanAnnotation }
    }

    func uuidString(in data: NSMutableDictionary?, key: String) -> String? {
        data?[key] as? String
    }

    func setUUID(_ id: UUID, on node: SKNode, key: String) {
        if node.userData == nil { node.userData = NSMutableDictionary() }
        node.userData?[key] = id.uuidString
    }

    func manualObjectID(for node: FloorPlanObject, createIfNeeded: Bool) -> UUID? {
        if let raw = uuidString(in: node.userData, key: Self.manualObjectIDKey),
           let id = UUID(uuidString: raw) {
            return id
        }
        guard createIfNeeded else { return nil }
        let id = UUID()
        setUUID(id, on: node, key: Self.manualObjectIDKey)
        return id
    }

    func annotationID(for node: FloorPlanAnnotation, createIfNeeded: Bool) -> UUID? {
        if let raw = uuidString(in: node.userData, key: Self.annotationIDKey),
           let id = UUID(uuidString: raw) {
            return id
        }
        guard createIfNeeded else { return nil }
        let id = UUID()
        setUUID(id, on: node, key: Self.annotationIDKey)
        return id
    }

    func surfaceNode(id: UUID) -> FloorPlanSurface? {
        surfaceNodes.first { $0.capturedSurface.identifier == id }
    }

    func scannedObjectNode(id: UUID) -> FloorPlanObject? {
        objectNodes.first { $0.capturedObject?.identifier == id }
    }
}

// MARK: - Complete editable state export and idempotent restore

extension FloorPlanScene {
    func exportEditState() -> FloorPlanEditState {
        var surfaces: [String: SavedSurfaceState] = [:]
        for node in surfaceNodes {
            let defaultWidth = defaultStrokeWidth(for: node)
            let actualWidth = node.selectedShape?.lineWidth ?? defaultWidth
            let customWidth: Double? = abs(actualWidth - defaultWidth) > 0.0001
                ? Double(actualWidth) : nil
            surfaces[node.capturedSurface.identifier.uuidString] = SavedSurfaceState(
                x: Double(node.position.x),
                y: Double(node.position.y),
                zRotation: Double(node.zRotation),
                halfLength: Double(node.halfLength),
                representation: node.representation == .source ? nil : node.representation,
                isFloorToCeilingGlass: node.isFloorToCeilingGlass ? true : nil,
                openDirection: node.openDirection,
                strokeWidth: customWidth,
                thicknessMeters: Double(node.thicknessMeters)
            )
        }

        var scannedObjects: [String: SavedObjectState] = [:]
        var manualObjects: [SavedManualObjectState] = []
        for node in objectNodes {
            if node.capturedObject == nil || node.name == "manual_object" {
                guard let categoryData = node.userData?[Self.manualCategoryDataKey] as? Data,
                      let id = manualObjectID(for: node, createIfNeeded: true) else { continue }
                manualObjects.append(SavedManualObjectState(
                    categoryData: categoryData,
                    x: Double(node.position.x),
                    y: Double(node.position.y),
                    zRotation: Double(node.zRotation),
                    xScale: Double(node.xScale),
                    yScale: Double(node.yScale),
                    id: id
                ))
            } else if let id = node.capturedObject?.identifier {
                scannedObjects[id.uuidString] = SavedObjectState(
                    x: Double(node.position.x),
                    y: Double(node.position.y),
                    zRotation: Double(node.zRotation),
                    xScale: Double(node.xScale),
                    yScale: Double(node.yScale)
                )
            }
        }

        var annotations: [SavedAnnotationState] = []
        for node in annotationNodes {
            var r: CGFloat = 0
            var g: CGFloat = 0.45
            var b: CGFloat = 0.85
            var a: CGFloat = 1
            if node.titleLabel.fontColor?.getRed(&r, green: &g, blue: &b, alpha: &a) != true,
               let converted = node.titleLabel.fontColor?.cgColor.converted(
                    to: CGColorSpace(name: CGColorSpace.sRGB)!,
                    intent: .defaultIntent,
                    options: nil
               ), converted.numberOfComponents >= 4,
               let values = converted.components {
                r = values[0]
                g = values[1]
                b = values[2]
                a = values[3]
            }
            func clamp(_ value: CGFloat) -> Double {
                Double(min(max(value.isFinite ? value : 0, 0), 1))
            }
            annotations.append(SavedAnnotationState(
                title: node.titleLabel.text ?? "",
                subtitle: node.subtitleLabel.text ?? "",
                x: Double(node.position.x),
                y: Double(node.position.y),
                zRotation: Double(node.zRotation),
                fontSize: Double(node.titleLabel.fontSize),
                red: clamp(r),
                green: clamp(g),
                blue: clamp(b),
                alpha: clamp(a),
                id: annotationID(for: node, createIfNeeded: true)
            ))
        }

        return FloorPlanEditState(
            createdAt: viewModel.editStateCreatedAt,
            displayUnit: viewModel.displayUnit,
            calibration: viewModel.calibrationState,
            surfaces: surfaces,
            objects: scannedObjects,
            cameraRotation: Double(camera?.zRotation ?? 0),
            manualObjects: manualObjects,
            annotations: annotations,
            coordinateConvention: viewModel.coordinateConvention,
            deletedSurfaceIDs: viewModel.deletedSurfaceIDs,
            deletedObjectIDs: viewModel.deletedObjectIDs,
            boundaryStatus: viewModel.boundaryStatus
        )
    }

    func applyEditState(_ input: FloorPlanEditState, recalculateArea: Bool = true) {
        var state = FloorPlanEditState.migrateIfNeeded(
            input,
            projectID: viewModel.savedProjectID
        )
        state.ensureStableIDs(projectID: viewModel.savedProjectID)
        isRestoringState = true
        defer { isRestoringState = false }

        deselectSurface()
        deselectObject()
        deselectAnnotation()
        objectNodes.filter { $0.capturedObject == nil || $0.name == "manual_object" }
            .forEach { $0.removeFromParent() }
        annotationNodes.forEach { $0.removeFromParent() }

        viewModel.deletedSurfaceIDs = state.deletedSurfaceIDs
        viewModel.deletedObjectIDs = state.deletedObjectIDs
        viewModel.coordinateConvention = state.coordinateConvention
        viewModel.editStateCreatedAt = state.createdAt
        viewModel.displayUnit = state.displayUnit
        viewModel.calibrationState = state.calibration

        let geometry = FloorPlanGeometry(capturedRoom: capturedRoom, editState: state)
        let surfaceGeometry = Dictionary(uniqueKeysWithValues:
            geometry.surfaces.map { ($0.source.identifier, $0) }
        )
        let objectGeometry = Dictionary(uniqueKeysWithValues:
            geometry.objects.map { ($0.source.identifier, $0) }
        )

        for source in allCapturedSurfaces() {
            let id = source.identifier
            if state.deletedSurfaceIDs.contains(id.uuidString) {
                surfaceNode(id: id)?.removeFromParent()
                continue
            }
            guard let resolved = surfaceGeometry[id] else { continue }
            let node: FloorPlanSurface
            if let existing = surfaceNode(id: id) {
                node = existing
            } else {
                node = FloorPlanSurface(capturedSurface: source, geometry: resolved)
                addChild(node)
            }
            node.position = resolved.center
            node.zRotation = resolved.angle
            node.halfLength = resolved.halfLength
            node.representation = resolved.representation
            node.isFloorToCeilingGlass = resolved.isFloorToCeilingGlass
            node.restoreOpenDirection(to: resolved.openDirection)
            node.restoreCalibrationScaleFactor(to: geometry.scaleFactor)
            node.restoreThicknessMeters(to: resolved.depthInMeters)
            node.restoreStrokeWidth(to: resolved.strokeWidth)
            node.updateDimensionLabel()
        }

        for source in capturedRoom.objects {
            let id = source.identifier
            if state.deletedObjectIDs.contains(id.uuidString) {
                scannedObjectNode(id: id)?.removeFromParent()
                continue
            }
            guard let resolved = objectGeometry[id] else { continue }
            let node: FloorPlanObject
            if let existing = scannedObjectNode(id: id) {
                node = existing
            } else {
                node = FloorPlanObject(geometry: resolved)
                addChild(node)
            }
            node.position = resolved.center
            node.zRotation = resolved.angle
            node.xScale = resolved.xScale
            node.yScale = resolved.yScale
            node.updateSizeLabel()
        }

        for saved in state.manualObjects ?? [] {
            guard let category = try? JSONDecoder().decode(
                CapturedRoom.Object.Category.self,
                from: saved.categoryData
            ) else { continue }
            let node = FloorPlanObject(
                withCategory: category,
                objectPosition: CGPoint(x: saved.x, y: saved.y)
            )
            node.name = "manual_object"
            node.userData = NSMutableDictionary(dictionary: [
                Self.manualCategoryDataKey: saved.categoryData,
                Self.manualObjectIDKey: (saved.id ?? UUID()).uuidString
            ])
            node.zRotation = CGFloat(saved.zRotation)
            node.xScale = CGFloat(saved.xScale)
            node.yScale = CGFloat(saved.yScale)
            node.isHidden = !viewModel.showFurniture
            node.setLabelVisible(viewModel.showFurnitureLabels)
            node.updateSizeLabel()
            addChild(node)
        }

        for saved in state.annotations ?? [] {
            let color = UIColor(
                red: CGFloat(min(max(saved.red, 0), 1)),
                green: CGFloat(min(max(saved.green, 0), 1)),
                blue: CGFloat(min(max(saved.blue, 0), 1)),
                alpha: CGFloat(min(max(saved.alpha, 0), 1))
            )
            let node = FloorPlanAnnotation(
                title: saved.title,
                subtitle: saved.subtitle,
                fontSize: CGFloat(saved.fontSize),
                fontColor: color
            )
            node.position = CGPoint(x: saved.x, y: saved.y)
            node.zRotation = CGFloat(saved.zRotation)
            setUUID(saved.id ?? UUID(), on: node, key: Self.annotationIDKey)
            addChild(node)
        }

        camera?.zRotation = CGFloat(state.cameraRotation)
        applyDisplaySettings(
            showFurniture: viewModel.showFurniture,
            showDimensions: viewModel.showDimensions,
            showFurnitureLabels: viewModel.showFurnitureLabels,
            showStructuralMarkers: viewModel.showStructuralMarkers
        )
        if recalculateArea {
            recalculateAreaAndExteriorDimensions()
        }
    }

    func saveCurrentProject() {
        let revision = viewModel.modelRevision
        let state = exportEditState()
        guard let project = RoomProjectStore.shared.saveProject(
            existingID: viewModel.savedProjectID,
            name: viewModel.roomUsage,
            floorLabel: viewModel.floorLabel,
            areaPing: viewModel.roomAreaPing,
            areaSqm: viewModel.roomAreaSqm,
            capturedRoom: capturedRoom,
            editState: state
        ) else {
            viewModel.shouldDismissAfterSave = false
            viewModel.statusToastMessage = RoomProjectStore.shared.lastErrorMessage
                ?? "儲存失敗，請稍後再試"
            return
        }
        viewModel.adoptSavedProject(project)
        if viewModel.editStateCreatedAt == nil {
            viewModel.editStateCreatedAt = state.createdAt
        }
        viewModel.clearDirty(ifRevisionMatches: revision)
        viewModel.statusToastMessage = "已儲存「\(project.name)」至空間紀錄庫！"
        if viewModel.shouldDismissAfterSave {
            viewModel.shouldDismissAfterSave = false
            viewModel.didCompleteSaveForDismiss = true
        }
    }
}

// MARK: - Surface style, derived walls, openings and boundary helpers

private extension FloorPlanScene {
    func defaultStrokeWidth(for surface: FloorPlanSurface) -> CGFloat {
        switch surface.effectiveRepresentation {
        case .solidWall:
            return DrawParameters.wallWidth
        case .wideOpening:
            return 7
        case .beam, .column:
            return 2
        case .source:
            switch surface.capturedSurface.category {
            case .wall: return DrawParameters.wallWidth
            case .door: return 8
            case .window: return DrawParameters.windowWidth
            case .opening: return DrawParameters.surfaceWidth
            default: return DrawParameters.surfaceWidth
            }
        }
    }

    func allCapturedSurfaces() -> [CapturedRoom.Surface] {
        capturedRoom.doors + capturedRoom.openings + capturedRoom.walls + capturedRoom.windows
    }

    func segment(for surface: FloorPlanSurface) -> FloorPlanWallSegment {
        let direction = CGPoint(x: cos(surface.zRotation), y: sin(surface.zRotation))
        let rawHeight = CGFloat(surface.capturedSurface.dimensions.y)
        let calibration = CGFloat(viewModel.calibrationState?.scaleFactor ?? 1)
        let height = rawHeight.isFinite && rawHeight > 0.1
            ? rawHeight * calibration : 2.6 * calibration
        return FloorPlanWallSegment(
            start: CGPoint(
                x: surface.position.x - surface.halfLength * direction.x,
                y: surface.position.y - surface.halfLength * direction.y
            ),
            end: CGPoint(
                x: surface.position.x + surface.halfLength * direction.x,
                y: surface.position.y + surface.halfLength * direction.y
            ),
            heightInMeters: max(height, 0.1),
            depthInMeters: surface.thicknessMeters,
            sourceSurfaceIDs: [surface.capturedSurface.identifier.uuidString]
        )
    }

    func openingSpan(for surface: FloorPlanSurface) -> FloorPlanOpeningSpan? {
        guard !surface.isWallGeometry else { return nil }
        switch surface.effectiveRepresentation {
        case .solidWall, .beam, .column:
            return nil
        case .wideOpening:
            break
        case .source:
            switch surface.capturedSurface.category {
            case .door, .window, .opening:
                break
            default:
                return nil
            }
        }
        let wall = segment(for: surface)
        return FloorPlanOpeningSpan(
            start: wall.start,
            end: wall.end,
            blocksCornerExtension: surface.capturedSurface.category != .window ||
                surface.effectiveRepresentation == .wideOpening
        )
    }

    func currentDerivedWalls() -> [FloorPlanWallSegment] {
        let visible = surfaceNodes.filter { node in
            !viewModel.deletedSurfaceIDs.contains(node.capturedSurface.identifier.uuidString)
        }
        return FloorPlanGeometry.joinedWallSegments(
            from: visible.filter(\.isWallGeometry).map(segment(for:)),
            pointsPerMeter: DrawParameters.scalingFactor,
            openings: visible.compactMap(openingSpan(for:))
        )
    }

    func segment(_ candidate: FloorPlanWallSegment, isCoveredBy walls: [FloorPlanWallSegment]) -> Bool {
        let vector = CGPoint(
            x: candidate.end.x - candidate.start.x,
            y: candidate.end.y - candidate.start.y
        )
        let length = hypot(vector.x, vector.y)
        guard length > 0.0001 else { return true }
        let direction = CGPoint(x: vector.x / length, y: vector.y / length)
        return walls.contains { wall in
            let lateralToleranceMeters = max(
                wall.depthInMeters * 0.5 + 0.08,
                0.15
            )
            let tolerance = DrawParameters.scalingFactor * lateralToleranceMeters
            let wallVector = CGPoint(x: wall.end.x - wall.start.x, y: wall.end.y - wall.start.y)
            let wallLength = hypot(wallVector.x, wallVector.y)
            guard wallLength > 0.0001 else { return false }
            let wallDirection = CGPoint(x: wallVector.x / wallLength, y: wallVector.y / wallLength)
            guard abs(direction.x * wallDirection.y - direction.y * wallDirection.x) <= sin(1.5 * .pi / 180) else {
                return false
            }
            func projection(_ point: CGPoint) -> CGFloat {
                (point.x - wall.start.x) * wallDirection.x +
                (point.y - wall.start.y) * wallDirection.y
            }
            func offset(_ point: CGPoint) -> CGFloat {
                abs((point.x - wall.start.x) * wallDirection.y -
                    (point.y - wall.start.y) * wallDirection.x)
            }
            guard offset(candidate.start) <= tolerance,
                  offset(candidate.end) <= tolerance else { return false }
            let a = projection(candidate.start)
            let b = projection(candidate.end)
            return min(a, b) >= -tolerance && max(a, b) <= wallLength + tolerance
        }
    }

    func boundarySegments(using walls: [FloorPlanWallSegment]) -> [FloorPlanWallSegment] {
        var result = walls
        for surface in surfaceNodes where !surface.isWallGeometry && surface.isRoomBoundaryGeometry {
            let virtual = segment(for: surface)
            if !segment(virtual, isCoveredBy: walls) {
                result.append(virtual)
            }
        }
        return result
    }
}

// MARK: - Blueprint grid, area and exterior dimensions

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
        var coordinate = -extent
        while coordinate <= extent {
            let major = Int(abs(coordinate)) % Int(majorStep) == 0
            let path = major ? majorPath : minorPath
            path.move(to: CGPoint(x: coordinate, y: -extent))
            path.addLine(to: CGPoint(x: coordinate, y: extent))
            path.move(to: CGPoint(x: -extent, y: coordinate))
            path.addLine(to: CGPoint(x: extent, y: coordinate))
            coordinate += minorStep
        }
        let minor = SKShapeNode(path: minorPath)
        minor.strokeColor = AppTheme.gridMinor
        minor.lineWidth = 1
        let major = SKShapeNode(path: majorPath)
        major.strokeColor = AppTheme.gridMajor
        major.lineWidth = 1.8
        container.addChild(minor)
        container.addChild(major)
        addChild(container)
        gridNode = container
    }

    func recalculateAreaAndExteriorDimensions() {
        let revision = viewModel.modelRevision
        let walls = currentDerivedWalls()
        updateWallJoinOverlay(with: walls)

        let wallOnlyResult = FloorPlanGeometry.evaluateBoundary(
            segments: walls,
            pointsPerMeter: DrawParameters.scalingFactor
        )

        let evaluatedSegments: [FloorPlanWallSegment]
        let result: FloorPlanBoundaryResult
        if wallOnlyResult.status == .closed {
            evaluatedSegments = walls
            result = wallOnlyResult
        } else {
            let combined = boundarySegments(using: walls)
            evaluatedSegments = FloorPlanGeometry.joinedWallSegments(
                from: combined,
                pointsPerMeter: DrawParameters.scalingFactor,
                openings: []
            )
            result = FloorPlanGeometry.evaluateBoundary(
                segments: evaluatedSegments,
                pointsPerMeter: DrawParameters.scalingFactor
            )
        }

        viewModel.updateBoundaryResult(result, revision: revision)
        if result.status == .closed {
            drawExteriorDimensionLines(
                points: evaluatedSegments.flatMap { [$0.start, $0.end] }
            )
        } else {
            exteriorDimensionsNode?.removeFromParent()
            exteriorDimensionsNode = nil
        }
    }

    private func updateWallJoinOverlay(with segments: [FloorPlanWallSegment]) {
        wallJointNode?.removeFromParent()
        guard !segments.isEmpty else {
            wallJointNode = nil
            return
        }
        let path = CGMutablePath()
        for segment in segments {
            path.move(to: segment.start)
            path.addLine(to: segment.end)
        }
        let node = SKShapeNode(path: path)
        node.strokeColor = AppTheme.wallStroke
        node.lineWidth = DrawParameters.wallWidth
        node.lineCap = .square
        node.zPosition = -0.5
        addChild(node)
        wallJointNode = node
    }

    private func drawExteriorDimensionLines(points: [CGPoint]) {
        exteriorDimensionsNode?.removeFromParent()
        guard !points.isEmpty else { return }
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        let width = maxX - minX
        let height = maxY - minY
        guard width > 20, height > 20 else { return }
        let container = SKNode()
        container.zPosition = DrawParameters.dimensionZPosition
        container.isHidden = !viewModel.showDimensions
        let factor = 100.0 / Double(DrawParameters.scalingFactor)
        let offset: CGFloat = 95
        addEngineeringDimLine(
            to: container,
            start: CGPoint(x: minX, y: maxY + offset),
            end: CGPoint(x: maxX, y: maxY + offset),
            extStartA: CGPoint(x: minX, y: maxY + 18),
            extStartB: CGPoint(x: maxX, y: maxY + 18),
            labelText: String(format: "%.0f cm", Double(width) * factor),
            isVertical: false
        )
        addEngineeringDimLine(
            to: container,
            start: CGPoint(x: minX, y: minY - offset),
            end: CGPoint(x: maxX, y: minY - offset),
            extStartA: CGPoint(x: minX, y: minY - 18),
            extStartB: CGPoint(x: maxX, y: minY - 18),
            labelText: String(format: "%.0f cm", Double(width) * factor),
            isVertical: false
        )
        addEngineeringDimLine(
            to: container,
            start: CGPoint(x: minX - offset, y: minY),
            end: CGPoint(x: minX - offset, y: maxY),
            extStartA: CGPoint(x: minX - 18, y: minY),
            extStartB: CGPoint(x: minX - 18, y: maxY),
            labelText: String(format: "%.0f cm", Double(height) * factor),
            isVertical: true
        )
        addEngineeringDimLine(
            to: container,
            start: CGPoint(x: maxX + offset, y: minY),
            end: CGPoint(x: maxX + offset, y: maxY),
            extStartA: CGPoint(x: maxX + 18, y: minY),
            extStartB: CGPoint(x: maxX + 18, y: maxY),
            labelText: String(format: "%.0f cm", Double(height) * factor),
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
        let extensionPath = CGMutablePath()
        extensionPath.move(to: extStartA)
        extensionPath.addLine(to: start)
        extensionPath.move(to: extStartB)
        extensionPath.addLine(to: end)
        let extensionNode = SKShapeNode(path: extensionPath)
        extensionNode.strokeColor = AppTheme.dimensionLine.withAlphaComponent(0.45)
        extensionNode.lineWidth = 1.5
        container.addChild(extensionNode)

        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)
        let tick: CGFloat = 11
        for point in [start, end] {
            path.move(to: CGPoint(x: point.x - tick, y: point.y - tick))
            path.addLine(to: CGPoint(x: point.x + tick, y: point.y + tick))
        }
        let main = SKShapeNode(path: path)
        main.strokeColor = AppTheme.dimensionLine
        main.lineWidth = 2.2
        container.addChild(main)

        let labelNode = SKNode()
        labelNode.position = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        if isVertical { labelNode.zRotation = .pi / 2 }
        let label = SKLabelNode(fontNamed: "Helvetica-Bold")
        label.text = labelText
        label.fontSize = 24
        label.fontColor = AppTheme.dimensionText
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        let background = SKShapeNode(
            rect: CGRect(
                x: -label.frame.width / 2 - 10,
                y: -label.frame.height / 2 - 4,
                width: label.frame.width + 20,
                height: label.frame.height + 8
            ),
            cornerRadius: 4
        )
        background.fillColor = AppTheme.canvasBg
        background.strokeColor = .clear
        background.zPosition = -1
        labelNode.addChild(background)
        labelNode.addChild(label)
        container.addChild(labelNode)
    }
}

// MARK: - Display, camera, rotation and complete Undo / Redo

extension FloorPlanScene {
    func applyDisplaySettings(
        showFurniture: Bool,
        showDimensions: Bool,
        showFurnitureLabels: Bool,
        showStructuralMarkers: Bool
    ) {
        for object in objectNodes {
            object.isHidden = !showFurniture
            object.setLabelVisible(showFurnitureLabels)
        }
        for surface in surfaceNodes {
            surface.setDimensionVisible(showDimensions)
            if surface.effectiveRepresentation == .beam || surface.effectiveRepresentation == .column {
                surface.isHidden = !showStructuralMarkers
            } else {
                surface.isHidden = false
            }
        }
        exteriorDimensionsNode?.isHidden = !showDimensions
    }

    func rotateView90() {
        recordUndoState()
        rotateAllNodes(by: -.pi / 2)
        camera?.zRotation = 0
        viewModel.markDirty(reason: "rotate_90")
        recalculateAreaAndExteriorDimensions()
        recenterCamera(animated: true)
    }

    private func rotateAllNodes(by angle: CGFloat) {
        let surfaces = surfaceNodes
        guard !surfaces.isEmpty else { return }
        let center = CGPoint(
            x: surfaces.reduce(0) { $0 + $1.position.x } / CGFloat(surfaces.count),
            y: surfaces.reduce(0) { $0 + $1.position.y } / CGFloat(surfaces.count)
        )
        func rotated(_ point: CGPoint) -> CGPoint {
            let x = point.x - center.x
            let y = point.y - center.y
            return CGPoint(
                x: center.x + x * cos(angle) - y * sin(angle),
                y: center.y + x * sin(angle) + y * cos(angle)
            )
        }
        for surface in surfaces {
            surface.position = rotated(surface.position)
            surface.zRotation += angle
            surface.updateDimensionLabel()
        }
        for object in objectNodes {
            object.position = rotated(object.position)
            object.zRotation += angle
            object.updateSizeLabel()
        }
        for note in annotationNodes {
            note.position = rotated(note.position)
            note.zRotation += angle
        }
    }

    private func roomBoundingRect(padding: CGFloat) -> CGRect? {
        let surfaces = surfaceNodes
        guard !surfaces.isEmpty else { return nil }
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for node in surfaces {
            let direction = CGPoint(x: cos(node.zRotation), y: sin(node.zRotation))
            let points = [
                CGPoint(x: node.position.x - node.halfLength * direction.x,
                        y: node.position.y - node.halfLength * direction.y),
                CGPoint(x: node.position.x + node.halfLength * direction.x,
                        y: node.position.y + node.halfLength * direction.y)
            ]
            for point in points {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
        }
        return CGRect(
            x: minX - padding,
            y: minY - padding,
            width: maxX - minX + padding * 2,
            height: maxY - minY + padding * 2
        )
    }

    func recenterCamera(animated: Bool = true) {
        guard let camera, let bounds = roomBoundingRect(padding: 230) else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let targetScale = max(0.35, min(2.6, max(bounds.width, bounds.height) / 1100))
        if animated {
            camera.run(SKAction.group([
                SKAction.move(to: center, duration: 0.25),
                SKAction.scale(to: targetScale, duration: 0.25)
            ]))
        } else {
            camera.position = center
            camera.setScale(targetScale)
        }
    }

    func beginContinuousEdit() {
        guard continuousEditStart == nil else { return }
        continuousEditStart = exportEditState()
    }

    func endContinuousEdit() {
        guard let initial = continuousEditStart else { return }
        continuousEditStart = nil
        let current = exportEditState()
        guard !isUndoEquivalent(initial, current) else { return }
        appendUndo(initial)
    }

    func recordUndoState() {
        guard !isRestoringState, continuousEditStart == nil else { return }
        appendUndo(exportEditState())
    }

    private func isUndoEquivalent(
        _ lhs: FloorPlanEditState,
        _ rhs: FloorPlanEditState
    ) -> Bool {
        var left = lhs
        var right = rhs
        left.createdAt = ""
        right.createdAt = ""
        left.modifiedAt = ""
        right.modifiedAt = ""
        left.boundaryStatus = nil
        right.boundaryStatus = nil
        return left == right
    }

    private func appendUndo(_ state: FloorPlanEditState) {
        if let last = undoStack.last,
           isUndoEquivalent(last, state) {
            return
        }
        undoStack.append(state)
    }
        if undoStack.count > 25 { undoStack.removeFirst() }
        redoStack.removeAll()
        syncUndoRedoFlags()
    }

    private func syncUndoRedoFlags() {
        viewModel.canUndo = !undoStack.isEmpty
        viewModel.canRedo = !redoStack.isEmpty
    }

    func performUndo() {
        guard let previous = undoStack.popLast() else { return }
        continuousEditStart = nil
        redoStack.append(exportEditState())
        if redoStack.count > 25 { redoStack.removeFirst() }
        viewModel.markDirty(reason: "undo")
        applyEditState(previous)
        syncUndoRedoFlags()
        viewModel.statusToastMessage = "已復原上一步"
    }

    func performRedo() {
        guard let next = redoStack.popLast() else { return }
        continuousEditStart = nil
        undoStack.append(exportEditState())
        if undoStack.count > 25 { undoStack.removeFirst() }
        viewModel.markDirty(reason: "redo")
        applyEditState(next)
        syncUndoRedoFlags()
        viewModel.statusToastMessage = "已重做操作"
    }
}

// MARK: - Calibration and centralized deletion

extension FloorPlanScene {
    func calibrateWholeRoom(using request: FloorPlanCalibrationRequest) {
        guard !handledCalibrationRequestIDs.contains(request.id) else { return }
        handledCalibrationRequestIDs.insert(request.id)
        guard !viewModel.isWallLocked else {
            viewModel.statusToastMessage = "牆體已鎖定，請先解鎖再執行全域校準"
            return
        }
        let ratio = request.ratio
        guard ratio.isFinite, ratio > 0.1, ratio < 10 else { return }
        let surfaces = surfaceNodes
        guard !surfaces.isEmpty else { return }
        recordUndoState()
        let center = CGPoint(
            x: surfaces.reduce(0) { $0 + $1.position.x } / CGFloat(surfaces.count),
            y: surfaces.reduce(0) { $0 + $1.position.y } / CGFloat(surfaces.count)
        )
        for surface in surfaces {
            surface.applyGlobalScale(ratio: ratio, around: center)
        }
        for object in objectNodes {
            object.applyGlobalScale(ratio: ratio, around: center)
        }
        for note in annotationNodes {
            note.position = CGPoint(
                x: center.x + (note.position.x - center.x) * ratio,
                y: center.y + (note.position.y - center.y) * ratio
            )
        }
        viewModel.calibrationState = SavedCalibrationState(
            scaleFactor: (viewModel.calibrationState?.scaleFactor ?? 1) * Double(ratio),
            referenceOriginalMeters: request.referenceOriginalMeters,
            referenceMeasuredMeters: request.referenceMeasuredMeters,
            calibratedAt: EditStateDateFormatter.nowString()
        )
        viewModel.markDirty(reason: "calibrate_whole_room")
        recalculateAreaAndExteriorDimensions()
        viewModel.statusToastMessage = String(
            format: "已依基準尺全域縮放校準 (比例 %.3fx)",
            Double(ratio)
        )
    }

    func deleteSurface(_ surface: FloorPlanSurface) {
        guard surface.parent != nil else { return }
        let convertsDoorToWall = surface.capturedSurface.category == .door
        if viewModel.isWallLocked && (surface.isProtectedByWallLock || convertsDoorToWall) {
            viewModel.statusToastMessage = "牆體已鎖定，請先解鎖再刪除或轉換牆面"
            return
        }
        if convertsDoorToWall {
            // setRepresentation already records Undo once; do not duplicate.
            surface.setRepresentation(.solidWall)
            surface.deselect()
            if viewModel.selectedSurface === surface {
                viewModel.selectedSurface = nil
            }
            viewModel.markDirty(reason: "delete_door_replace_wall")
        } else {
            recordUndoState()
            viewModel.deletedSurfaceIDs.insert(surface.capturedSurface.identifier.uuidString)
            surface.removeFromParent()
            surface.deselect()
            if viewModel.selectedSurface === surface {
                viewModel.selectedSurface = nil
            }
            viewModel.markDirty(reason: "delete_surface")
        }
        recalculateAreaAndExteriorDimensions()
    }

    func deleteObject(_ object: FloorPlanObject) {
        guard object.parent != nil else { return }
        recordUndoState()
        if let id = object.capturedObject?.identifier {
            viewModel.deletedObjectIDs.insert(id.uuidString)
        }
        object.removeFromParent()
        object.deselect()
        if viewModel.selectedObject === object { viewModel.selectedObject = nil }
        viewModel.markDirty(reason: "delete_object")
    }

    func deleteAnnotation(_ annotation: FloorPlanAnnotation) {
        guard annotation.parent != nil else { return }
        recordUndoState()
        annotation.removeFromParent()
        annotation.removeHighlight()
        if viewModel.selectedAnnotation === annotation { viewModel.selectedAnnotation = nil }
        viewModel.markDirty(reason: "delete_annotation")
    }
}

// MARK: - Initial nodes and selection

private extension FloorPlanScene {
    func drawSurfaces() {
        let geometry = FloorPlanGeometry(
            capturedRoom: capturedRoom,
            editState: viewModel.initialEditState,
            scaleFactor: viewModel.calibrationState.map { CGFloat($0.scaleFactor) }
        )
        for item in geometry.surfaces {
            addChild(FloorPlanSurface(capturedSurface: item.source, geometry: item))
        }
    }

    func drawObjects() {
        let geometry = FloorPlanGeometry(
            capturedRoom: capturedRoom,
            editState: viewModel.initialEditState,
            scaleFactor: viewModel.calibrationState.map { CGFloat($0.scaleFactor) }
        )
        for item in geometry.objects {
            addChild(FloorPlanObject(geometry: item))
        }
    }

    func selectSurface(_ node: FloorPlanSurface) {
        deselectSurface()
        node.select()
        viewModel.selectedSurface = node
    }

    func deselectSurface() {
        guard let selected = viewModel.selectedSurface else { return }
        selected.deselect()
        viewModel.selectedSurface = nil
    }

    func selectObject(_ node: FloorPlanObject) {
        deselectObject()
        node.select()
        viewModel.selectedObject = node
    }

    func deselectObject() {
        guard let selected = viewModel.selectedObject else { return }
        selected.deselect()
        viewModel.selectedObject = nil
    }

    func selectAnnotation(_ node: FloorPlanAnnotation) {
        deselectAnnotation()
        node.highlight()
        viewModel.selectedAnnotation = node
    }

    func deselectAnnotation() {
        guard let selected = viewModel.selectedAnnotation else { return }
        selected.removeHighlight()
        viewModel.selectedAnnotation = nil
    }

    func findAncestor<T: SKNode>(ofType type: T.Type, in hitNodes: [SKNode]) -> T? {
        for node in hitNodes {
            var current: SKNode? = node
            while let candidate = current {
                if let match = candidate as? T, !match.isHidden { return match }
                current = candidate.parent
            }
        }
        return nil
    }
}

// MARK: - SpriteKit gestures

private extension FloorPlanScene {
    @objc func panGestureAction(_ sender: UIPanGestureRecognizer) {
        guard let view else { return }
        let location = convertPoint(fromView: sender.location(in: view))
        if let object = viewModel.selectedObject,
           object.contains(location) || isDraggingObject {
            switch sender.state {
            case .began:
                isDraggingObject = true
                beginContinuousEdit()
            case .changed:
                object.position = location
                viewModel.markDirty(reason: "move_object")
            case .ended, .cancelled, .failed:
                isDraggingObject = false
                endContinuousEdit()
            default:
                break
            }
            return
        }
        if let annotation = viewModel.selectedAnnotation,
           annotation.contains(location) || isDraggingAnnotation {
            switch sender.state {
            case .began:
                isDraggingAnnotation = true
                beginContinuousEdit()
            case .changed:
                annotation.position = location
                viewModel.markDirty(reason: "move_annotation")
            case .ended, .cancelled, .failed:
                isDraggingAnnotation = false
                endContinuousEdit()
            default:
                break
            }
            return
        }
        guard let camera else { return }
        switch sender.state {
        case .began:
            previousCameraPosition = camera.position
        case .changed:
            let translation = sender.translation(in: view)
            let angle = -camera.zRotation
            let rotated = CGPoint(
                x: translation.x * cos(angle) - translation.y * sin(angle),
                y: translation.x * sin(angle) + translation.y * cos(angle)
            )
            camera.position = CGPoint(
                x: previousCameraPosition.x - rotated.x * camera.xScale,
                y: previousCameraPosition.y + rotated.y * camera.xScale
            )
        default:
            break
        }
    }

    @objc func pinchGestureAction(_ sender: UIPinchGestureRecognizer) {
        guard let camera else { return }
        if sender.state == .began { previousCameraScale = camera.xScale }
        camera.setScale(max(0.2, min(4, previousCameraScale / sender.scale)))
    }

    @objc func rotationGestureAction(_ sender: UIRotationGestureRecognizer) {
        guard let camera else { return }
        if sender.state == .began || sender.state == .changed {
            camera.zRotation += sender.rotation
            sender.rotation = 0
        }
    }

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let view else { return }
        let location = convertPoint(fromView: gesture.location(in: view))
        let hit = nodes(at: location)
        if let note = findAncestor(ofType: FloorPlanAnnotation.self, in: hit) {
            deselectSurface(); deselectObject(); selectAnnotation(note)
        } else if let object = findAncestor(ofType: FloorPlanObject.self, in: hit) {
            deselectSurface(); deselectAnnotation(); selectObject(object)
        } else if let surface = findAncestor(ofType: FloorPlanSurface.self, in: hit) {
            deselectObject(); deselectAnnotation(); selectSurface(surface)
        } else {
            deselectSurface(); deselectObject(); deselectAnnotation()
        }
    }

    func addCamera() {
        let node = SKCameraNode()
        addChild(node)
        camera = node
    }
}

// MARK: - Furniture, annotation and image export

extension FloorPlanScene {
    private func preferredManualPlacementPoint() -> CGPoint {
        if let camera { return camera.position }
        if let bounds = roomBoundingRect(padding: 0) {
            return CGPoint(x: bounds.midX, y: bounds.midY)
        }
        return .zero
    }

    func addNewObject(with category: CapturedRoom.Object.Category) {
        recordUndoState()
        let node = FloorPlanObject(
            withCategory: category,
            objectPosition: preferredManualPlacementPoint()
        )
        node.name = "manual_object"
        if let data = try? JSONEncoder().encode(category) {
            node.userData = NSMutableDictionary(dictionary: [
                Self.manualCategoryDataKey: data,
                Self.manualObjectIDKey: UUID().uuidString
            ])
        }
        node.isHidden = !viewModel.showFurniture
        node.setLabelVisible(viewModel.showFurnitureLabels)
        addChild(node)
        viewModel.markDirty(reason: "add_object")
    }

    func addExampleAnnotations() {
        guard let camera else { return }
        recordUndoState()
        let note = FloorPlanAnnotation(
            title: "區域標註",
            subtitle: "點擊編輯文字",
            fontSize: 36,
            fontColor: AppTheme.windowStroke
        )
        note.position = camera.position
        setUUID(UUID(), on: note, key: Self.annotationIDKey)
        addChild(note)
        viewModel.markDirty(reason: "add_annotation")
    }

    func exportImage(with format: ImageFormat) {
        deselectSurface()
        deselectObject()
        deselectAnnotation()
        let safeName = viewModel.roomUsage.replacingOccurrences(of: "/", with: "_")
        let base = "\(viewModel.floorLabel)_\(safeName)"
        if format == .dxf {
            guard let data = generateDXF().data(using: .utf8),
                  let directory = FileManager.default.urls(
                    for: .documentDirectory,
                    in: .userDomainMask
                  ).first else { return }
            let url = directory.appendingPathComponent("\(base).dxf")
            do {
                try data.write(to: url)
                presentShareSheet(with: url)
            } catch {
                print("Error saving DXF: \(error.localizedDescription)")
            }
            return
        }
        guard let image = renderBlueprintSheet() else {
            viewModel.statusToastMessage = "藍圖匯出失敗，請稍後再試"
            return
        }
        let data: Data?
        switch format {
        case .png:
            data = image.pngData()
        case .jpeg:
            data = image.jpegData(compressionQuality: 0.95)
        case .pdf:
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: image.size))
            data = renderer.pdfData { context in
                context.beginPage()
                image.draw(in: CGRect(origin: .zero, size: image.size))
            }
        case .dxf:
            return
        }
        guard let data,
              let directory = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
              ).first else { return }
        let url = directory.appendingPathComponent("\(base).\(format.rawValue)")
        do {
            try data.write(to: url)
            presentShareSheet(with: url)
        } catch {
            print("Error saving image: \(error.localizedDescription)")
        }
    }
}

// MARK: - AutoCAD DXF generator

extension FloorPlanScene {
    func generateDXF() -> String {
        let factor = 100.0 / Double(DrawParameters.scalingFactor)
        func fmt(_ value: Double) -> String { String(format: "%.2f", value) }
        func degrees(_ radians: Double) -> Double {
            var value = radians * 180 / .pi
            value = value.truncatingRemainder(dividingBy: 360)
            if value < 0 { value += 360 }
            return value
        }
        var output: [String] = []
        func addLine(_ layer: String, _ a: CGPoint, _ b: CGPoint) {
            output += [
                "0", "LINE", "8", layer,
                "10", fmt(Double(a.x) * factor),
                "20", fmt(Double(a.y) * factor), "30", "0.0",
                "11", fmt(Double(b.x) * factor),
                "21", fmt(Double(b.y) * factor), "31", "0.0"
            ]
        }
        func addArc(
            _ layer: String,
            center: CGPoint,
            radius: CGFloat,
            start: Double,
            end: Double
        ) {
            output += [
                "0", "ARC", "8", layer,
                "10", fmt(Double(center.x) * factor),
                "20", fmt(Double(center.y) * factor), "30", "0.0",
                "40", fmt(Double(radius) * factor),
                "50", fmt(start), "51", fmt(end)
            ]
        }
        func addText(
            _ layer: String,
            position: CGPoint,
            height: Double,
            angle: Double,
            text: String
        ) {
            output += [
                "0", "TEXT", "8", layer,
                "10", fmt(Double(position.x) * factor),
                "20", fmt(Double(position.y) * factor), "30", "0.0",
                "40", fmt(height), "50", fmt(angle), "1", text
            ]
        }

        output += [
            "0", "SECTION", "2", "HEADER",
            "9", "$INSUNITS", "70", "5", "0", "ENDSEC"
        ]
        let layers = [
            ("WALLS", "7"), ("DOORS", "1"), ("WINDOWS", "5"),
            ("OPENINGS", "4"), ("STRUCTURE", "30"),
            ("DIMENSIONS", "3"), ("FURNITURE", "8")
        ]
        output += ["0", "SECTION", "2", "TABLES", "0", "TABLE", "2", "LAYER", "70", "\(layers.count)"]
        for layer in layers {
            output += ["0", "LAYER", "2", layer.0, "70", "0", "62", layer.1, "6", "CONTINUOUS"]
        }
        output += ["0", "ENDTAB", "0", "ENDSEC", "0", "SECTION", "2", "ENTITIES"]

        for wall in currentDerivedWalls() {
            addLine("WALLS", wall.start, wall.end)
            var labelAngle = degrees(Double(wall.angle))
            var offset: CGFloat = 18
            if labelAngle > 90 && labelAngle < 270 {
                labelAngle = degrees(Double(wall.angle) + .pi)
                offset = -18
            }
            let labelPosition = CGPoint(
                x: wall.midpoint.x - sin(wall.angle) * offset,
                y: wall.midpoint.y + cos(wall.angle) * offset
            )
            addText(
                "DIMENSIONS",
                position: labelPosition,
                height: 12,
                angle: labelAngle,
                text: String(format: "%.1f cm", Double(wall.length) * factor)
            )
        }

        for surface in surfaceNodes where !viewModel.deletedSurfaceIDs.contains(
            surface.capturedSurface.identifier.uuidString
        ) {
            let line = segment(for: surface)
            switch surface.effectiveRepresentation {
            case .solidWall:
                break
            case .wideOpening:
                addLine("OPENINGS", line.start, line.end)
            case .beam, .column:
                let center = surface.position
                let halfWidth = surface.effectiveRepresentation == .column
                    ? max(min(surface.halfLength, 20), 12) : surface.halfLength
                let halfDepth = max(surface.thicknessMeters * DrawParameters.scalingFactor / 2, 8)
                let direction = CGPoint(x: cos(surface.zRotation), y: sin(surface.zRotation))
                let normal = CGPoint(x: -direction.y, y: direction.x)
                let corners = [
                    CGPoint(x: center.x - halfWidth * direction.x - halfDepth * normal.x,
                            y: center.y - halfWidth * direction.y - halfDepth * normal.y),
                    CGPoint(x: center.x + halfWidth * direction.x - halfDepth * normal.x,
                            y: center.y + halfWidth * direction.y - halfDepth * normal.y),
                    CGPoint(x: center.x + halfWidth * direction.x + halfDepth * normal.x,
                            y: center.y + halfWidth * direction.y + halfDepth * normal.y),
                    CGPoint(x: center.x - halfWidth * direction.x + halfDepth * normal.x,
                            y: center.y - halfWidth * direction.y + halfDepth * normal.y)
                ]
                for index in corners.indices {
                    addLine("STRUCTURE", corners[index], corners[(index + 1) % corners.count])
                }
            case .source:
                switch surface.capturedSurface.category {
                case .wall:
                    break
                case .door:
                    let hinge = line.start
                    let end = CGPoint(
                        x: hinge.x + line.length * cos(surface.zRotation + surface.openDirection.angle),
                        y: hinge.y + line.length * sin(surface.zRotation + surface.openDirection.angle)
                    )
                    addLine("DOORS", hinge, end)
                    let base = degrees(Double(surface.zRotation))
                    addArc(
                        "DOORS",
                        center: hinge,
                        radius: line.length,
                        start: surface.openDirection == .clockwise ? degrees(Double(surface.zRotation - .pi / 4)) : base,
                        end: surface.openDirection == .clockwise ? base : degrees(Double(surface.zRotation + .pi / 4))
                    )
                case .window:
                    addLine("WINDOWS", line.start, line.end)
                case .opening:
                    addLine("OPENINGS", line.start, line.end)
                default:
                    break
                }
            }
        }

        for object in objectNodes where !object.isHidden {
            let width = CGFloat(object.currentWidthCm / factor)
            let height = CGFloat(object.currentHeightCm / factor)
            let local = [
                CGPoint(x: -width / 2, y: -height / 2),
                CGPoint(x: width / 2, y: -height / 2),
                CGPoint(x: width / 2, y: height / 2),
                CGPoint(x: -width / 2, y: height / 2)
            ]
            let world = local.map { point in
                CGPoint(
                    x: object.position.x + point.x * cos(object.zRotation) - point.y * sin(object.zRotation),
                    y: object.position.y + point.x * sin(object.zRotation) + point.y * cos(object.zRotation)
                )
            }
            for index in world.indices {
                addLine("FURNITURE", world[index], world[(index + 1) % world.count])
            }
        }
        output += ["0", "ENDSEC", "0", "EOF"]
        return output.joined(separator: "\r\n")
    }
}

// MARK: - Blueprint sheet and share sheet

extension FloorPlanScene {
    func presentShareSheet(with fileURL: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                ?? windowScene.windows.first?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }

    func renderBlueprintSheet() -> UIImage? {
        guard let view,
              let crop = roomBoundingRect(padding: 185),
              let texture = view.texture(from: self, crop: crop) else { return nil }
        let plan = UIImage(cgImage: texture.cgImage())
        let width: CGFloat = 1800
        let header: CGFloat = 165
        let footer: CGFloat = 115
        let margin: CGFloat = 48
        let maximumPlanHeight: CGFloat = 1800
        let scale = min(
            (width - margin * 2) / max(plan.size.width, 1),
            maximumPlanHeight / max(plan.size.height, 1)
        )
        let planSize = CGSize(width: plan.size.width * scale, height: plan.size.height * scale)
        let canvas = CGSize(
            width: width,
            height: header + planSize.height + footer + margin * 2
        )
        return UIGraphicsImageRenderer(size: canvas).image { context in
            let cg = context.cgContext
            AppTheme.canvasBg.setFill()
            cg.fill(CGRect(origin: .zero, size: canvas))
            UIColor(red: 0.11, green: 0.13, blue: 0.16, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: width, height: header))
            let title = "\(viewModel.floorLabel)  \(viewModel.roomUsage)"
            (title as NSString).draw(
                at: CGPoint(x: margin, y: 34),
                withAttributes: [
                    .font: UIFont.boldSystemFont(ofSize: 44),
                    .foregroundColor: UIColor.white
                ]
            )
            let areaText = viewModel.isRoomBoundaryClosed
                ? String(
                    format: "室內實測面積：約 %.2f 坪（%.1f ㎡）｜ 單位：公分 (cm)",
                    viewModel.roomAreaPing,
                    viewModel.roomAreaSqm
                  )
                : "輪廓未閉合，暫不顯示坪數｜ 單位：公分 (cm)"
            (areaText as NSString).draw(
                at: CGPoint(x: margin, y: 98),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 28, weight: .semibold),
                    .foregroundColor: UIColor(red: 0.96, green: 0.84, blue: 0.56, alpha: 1)
                ]
            )
            let frame = CGRect(
                x: (width - planSize.width) / 2,
                y: header + margin,
                width: planSize.width,
                height: planSize.height
            )
            plan.draw(in: frame)
            AppTheme.dimensionLine.withAlphaComponent(0.35).setStroke()
            cg.setLineWidth(2)
            cg.stroke(frame)
            let footerY = header + margin + planSize.height + 28
            let legend = "圖例：■ 黑色＝結構牆   ■ 橘色＝門扇開向   ■ 藍色＝窗戶   ■ 灰線＝向量家具"
            (legend as NSString).draw(
                at: CGPoint(x: margin, y: footerY),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 24, weight: .medium),
                    .foregroundColor: AppTheme.dimensionText
                ]
            )
            (AppTheme.footerText as NSString).draw(
                at: CGPoint(x: margin, y: footerY + 42),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 22),
                    .foregroundColor: UIColor.gray
                ]
            )
        }
    }
}
