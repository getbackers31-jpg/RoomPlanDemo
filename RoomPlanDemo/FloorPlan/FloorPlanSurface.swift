import SpriteKit
import RoomPlan
import UIKit

final class FloorPlanSurface: SKNode, Identifiable {
    let capturedSurface: CapturedRoom.Surface
    var selectedShape: SKShapeNode?
    var openDirection: OpenDirection
    var representation: FloorPlanSurfaceRepresentation {
        didSet {
            clearPresentationShapes()
            drawSurface()
            updateDimensionLabel()
        }
    }
    var isFloorToCeilingGlass: Bool {
        didSet { drawSurface() }
    }
    
    private var borderNode: SKShapeNode?
    private var hideWallShape: SKShapeNode?
    private var arcShape: SKShapeNode?
    private var doorSectorShape: SKShapeNode?
    private var windowGlassShape: SKShapeNode?
    private var structuralMarkerShape: SKShapeNode?
    private(set) var calibrationScaleFactor: CGFloat
    private var baseDepthInPoints: CGFloat
    private var depthInPoints: CGFloat
    private var customStrokeWidth: CGFloat?
    private let pointsPerMeter: CGFloat

    // Physical thickness and drawing stroke are intentionally independent.
    var thicknessMeters: CGFloat {
        get { depthInPoints / pointsPerMeter }
        set { updateThicknessMeters(to: newValue) }
    }

    var isProtectedByWallLock: Bool {
        capturedSurface.category == .wall || representation == .solidWall
    }

    private var isEditingLocked: Bool {
        isProtectedByWallLock &&
            ((scene as? FloorPlanScene)?.viewModel.isWallLocked ?? false)
    }
    
    private var dimensionContainer: SKNode?
    private var dimensionLabel: SKLabelNode?
    private var dimensionBg: SKShapeNode?
    private var isDimensionVisible: Bool = true
    
    var halfLength: CGFloat {
        didSet {
            if representation == .source,
               capturedSurface.category.floorPlanIsDoor,
               (oldValue * 2 / pointsPerMeter > FloorPlanGeometry.oversizedDoorWidthMeters)
                    != (halfLength * 2 / pointsPerMeter > FloorPlanGeometry.oversizedDoorWidthMeters) {
                clearPresentationShapes()
            }
            drawSurface()
        }
    }
    
    private var pointA: CGPoint { CGPoint(x: -halfLength, y: 0) }
    private var pointB: CGPoint { CGPoint(x: halfLength, y: 0) }
    private var pointC: CGPoint { pointB.rotateAround(point: pointA, by: openDirection.angle) }
    
    init(capturedSurface: CapturedRoom.Surface, geometry: FloorPlanSurfaceGeometry) {
        self.capturedSurface = capturedSurface
        self.openDirection = geometry.openDirection
        self.representation = geometry.representation
        self.isFloorToCeilingGlass = geometry.isFloorToCeilingGlass
        let scale = geometry.scaleFactor.isFinite && geometry.scaleFactor > 0
            ? geometry.scaleFactor : 1
        let ppm = geometry.pointsPerMeter.isFinite && geometry.pointsPerMeter > 0
            ? geometry.pointsPerMeter : 200
        let depth = geometry.depthInMeters.isFinite && geometry.depthInMeters > 0
            ? geometry.depthInMeters : 0.1
        self.pointsPerMeter = ppm
        self.calibrationScaleFactor = scale
        self.baseDepthInPoints = depth * ppm / scale
        self.depthInPoints = depth * ppm
        self.customStrokeWidth = geometry.strokeWidth.flatMap {
            $0.isFinite && $0 > 0 ? $0 : nil
        }
        self.halfLength = geometry.halfLength.isFinite && geometry.halfLength >= 0
            ? geometry.halfLength : 0

        super.init()

        self.position = geometry.center.x.isFinite && geometry.center.y.isFinite
            ? geometry.center : .zero
        self.zRotation = geometry.angle.isFinite ? geometry.angle : 0
        drawSurface()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension FloorPlanSurface {
    var effectiveRepresentation: FloorPlanSurfaceRepresentation {
        if representation == .source,
           capturedSurface.category.floorPlanIsDoor,
           halfLength * 2 / pointsPerMeter > FloorPlanGeometry.oversizedDoorWidthMeters {
            return .wideOpening
        }
        return representation
    }

    var isOversizedDoor: Bool {
        capturedSurface.category.floorPlanIsDoor &&
            halfLength * 2 / pointsPerMeter > FloorPlanGeometry.oversizedDoorWidthMeters
    }

    var isWallGeometry: Bool {
        switch effectiveRepresentation {
        case .solidWall:
            return true
        case .source:
            return capturedSurface.category == .wall
        case .wideOpening, .beam, .column:
            return false
        }
    }

    var isNoiseFragment: Bool {
        isWallGeometry &&
            halfLength * 2 / pointsPerMeter < FloorPlanGeometry.minimumWallSegmentLengthMeters
    }

    var isRoomBoundaryGeometry: Bool {
        switch effectiveRepresentation {
        case .solidWall, .wideOpening:
            return true
        case .beam, .column:
            return false
        case .source:
            // These are candidate boundary spans, not additional solid walls.
            // Scene boundary evaluation must still reject invalid topology.
            switch capturedSurface.category {
            case .wall, .door, .window, .opening:
                return true
            default:
                return false
            }
        }
    }

    func select() { updateHighlight() }

    func deselect() {
        borderNode?.removeFromParent()
        borderNode = nil
    }

    func setDimensionVisible(_ visible: Bool) {
        isDimensionVisible = visible
        updateDimensionLabel()
    }

    func updateDoorOpenDirection(to newValue: OpenDirection) {
        guard !isEditingLocked, openDirection != newValue else { return }
        (scene as? FloorPlanScene)?.recordUndoState()
        openDirection = newValue
        drawSurface()
        markDirty(reason: "door_open_direction")
    }

    // Restore methods are for snapshot/load only: no lock, Undo or Dirty events.
    func restoreOpenDirection(to value: OpenDirection) {
        openDirection = value
        drawSurface()
    }

    func restoreStrokeWidth(to value: CGFloat?) {
        if let value {
            guard value.isFinite, value > 0 else { return }
        }
        customStrokeWidth = value
        drawSurface()
    }

    func restoreThicknessMeters(to value: CGFloat) {
        guard value.isFinite, value > 0 else { return }
        let points = value * pointsPerMeter
        let base = points / calibrationScaleFactor
        guard points.isFinite, base.isFinite, base > 0 else { return }
        depthInPoints = points
        baseDepthInPoints = base
        drawSurface()
    }

    func setRepresentation(_ newValue: FloorPlanSurfaceRepresentation) {
        // Also protect entry INTO solidWall while locked, not only exit from it.
        let locked = (scene as? FloorPlanScene)?.viewModel.isWallLocked ?? false
        guard !(locked && (isProtectedByWallLock || newValue == .solidWall)),
              representation != newValue else { return }
        (scene as? FloorPlanScene)?.recordUndoState()
        representation = newValue
        markDirty(reason: "surface_representation")
        (scene as? FloorPlanScene)?.recalculateAreaAndExteriorDimensions()
    }

    func setFloorToCeilingGlass(_ enabled: Bool) {
        guard !isEditingLocked, isFloorToCeilingGlass != enabled else { return }
        (scene as? FloorPlanScene)?.recordUndoState()
        isFloorToCeilingGlass = enabled
        markDirty(reason: "floor_to_ceiling_glass")
    }

    func restoreCalibrationScaleFactor(to value: CGFloat) {
        guard value.isFinite, value > 0 else { return }
        let depth = baseDepthInPoints * value
        guard depth.isFinite, depth > 0 else { return }
        calibrationScaleFactor = value
        depthInPoints = depth
        drawSurface()
    }

    // Continuous edit entry points: the caller owns begin/endContinuousEdit.
    // No degree conversion, snapping or per-value Undo insertion occurs here.
    func updateAngleRadians(to newAngle: CGFloat) {
        guard !isEditingLocked, newAngle.isFinite,
              zRotation != newAngle else { return }
        zRotation = newAngle
        updateDimensionLabel()
        if borderNode?.parent != nil { updateHighlight() }
        markDirty(reason: "surface_angle")
        (scene as? FloorPlanScene)?.recalculateAreaAndExteriorDimensions()
    }

    func updateAngle(to newAngle: CGFloat) {
        updateAngleRadians(to: newAngle)
    }

    func updateWidth(to newValue: CGFloat) {
        guard !isEditingLocked, newValue.isFinite, newValue > 0,
              newValue != halfLength else { return }
        halfLength = newValue
        markDirty(reason: "surface_width")
        (scene as? FloorPlanScene)?.recalculateAreaAndExteriorDimensions()
    }

    func updateDepth(to newValue: CGFloat) {
        guard !isEditingLocked, newValue.isFinite, newValue > 0,
              customStrokeWidth != newValue else { return }
        customStrokeWidth = newValue
        drawSurface()
        markDirty(reason: "surface_stroke_width")
    }

    func updateThicknessMeters(to newValue: CGFloat) {
        guard !isEditingLocked, newValue.isFinite, newValue > 0,
              newValue != thicknessMeters else { return }
        let points = newValue * pointsPerMeter
        let base = points / calibrationScaleFactor
        guard points.isFinite, base.isFinite, base > 0 else { return }
        depthInPoints = points
        baseDepthInPoints = base
        drawSurface()
        markDirty(reason: "surface_thickness")
    }

    func updatePosition(x: Double? = nil, y: Double? = nil, z: Double? = nil) {
        guard !isEditingLocked else { return }
        let nextX = x.map { CGFloat($0) } ?? position.x
        let nextY = y.map { CGFloat($0) } ?? position.y
        let nextZ = z.map { CGFloat($0) } ?? zPosition
        guard nextX.isFinite, nextY.isFinite, nextZ.isFinite,
              nextX != position.x || nextY != position.y || nextZ != zPosition else { return }
        position = CGPoint(x: nextX, y: nextY)
        zPosition = nextZ
        markDirty(reason: "surface_position")
        (scene as? FloorPlanScene)?.recalculateAreaAndExteriorDimensions()
    }

    // The Scene owns the single Undo/Dirty transaction for global calibration.
    func applyGlobalScale(ratio: CGFloat, around origin: CGPoint) {
        guard !isEditingLocked, ratio.isFinite, ratio > 0,
              origin.x.isFinite, origin.y.isFinite else { return }
        let scale = calibrationScaleFactor * ratio
        let depth = baseDepthInPoints * scale
        let length = halfLength * ratio
        let point = CGPoint(
            x: origin.x + (position.x - origin.x) * ratio,
            y: origin.y + (position.y - origin.y) * ratio
        )
        guard scale.isFinite, scale > 0, depth.isFinite, depth > 0,
              length.isFinite, length >= 0,
              point.x.isFinite, point.y.isFinite else { return }
        calibrationScaleFactor = scale
        depthInPoints = depth
        position = point
        halfLength = length
        // Stroke is a drawing preference and deliberately does not scale.
        drawSurface()
    }

    func updateDimensionLabel() {
        guard isWallGeometry else {
            dimensionContainer?.removeFromParent()
            dimensionContainer = nil
            dimensionLabel = nil
            dimensionBg = nil
            return
        }
        
        let lengthCm = Double(halfLength * 2 / pointsPerMeter) * 100.0
        let text = String(format: "%.0f cm", lengthCm)
        
        if dimensionLabel == nil {
            let container = SKNode()
            container.zPosition = DrawParameters.dimensionZPosition
            
            let label = SKLabelNode(fontNamed: "Helvetica-Bold")
            label.fontSize = 20
            label.fontColor = AppTheme.dimensionText
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            
            let bg = SKShapeNode()
            bg.fillColor = UIColor.white.withAlphaComponent(0.92)
            bg.strokeColor = AppTheme.dimensionLine.withAlphaComponent(0.35)
            bg.lineWidth = 1.2
            bg.zPosition = -1
            
            container.addChild(bg)
            container.addChild(label)
            addChild(container)
            
            self.dimensionContainer = container
            self.dimensionLabel = label
            self.dimensionBg = bg
        }
        
        dimensionLabel?.text = text
        dimensionContainer?.isHidden = !isDimensionVisible || lengthCm < 25.0
        
        if let label = dimensionLabel, let bg = dimensionBg {
            let padX: CGFloat = 8
            let padY: CGFloat = 4
            let rect = CGRect(
                x: -label.frame.width / 2 - padX,
                y: -label.frame.height / 2 - padY,
                width: label.frame.width + padX * 2,
                height: label.frame.height + padY * 2
            )
            bg.path = CGPath(roundedRect: rect, cornerWidth: 5, cornerHeight: 5, transform: nil)
        }
        
        var angleDeg = Double(zRotation) * 180.0 / .pi
        angleDeg = angleDeg.truncatingRemainder(dividingBy: 360.0)
        if angleDeg > 180 { angleDeg -= 360 }
        if angleDeg < -180 { angleDeg += 360 }
        
        if angleDeg > 90 || angleDeg < -90 {
            dimensionContainer?.zRotation = .pi
            dimensionContainer?.position = CGPoint(x: 0, y: -28)
        } else {
            dimensionContainer?.zRotation = 0
            dimensionContainer?.position = CGPoint(x: 0, y: 28)
        }
    }
}

private extension FloorPlanSurface {
    func markDirty(reason: String) {
        (scene as? FloorPlanScene)?.viewModel.markDirty(reason: reason)
    }

    func drawSurface() {
        let wasSelected = borderNode?.parent != nil
        clearPresentationShapes()
        switch effectiveRepresentation {
        case .solidWall:
            drawWall()
        case .wideOpening:
            drawWideOpening()
        case .beam, .column:
            drawStructuralMarker()
        case .source:
            drawSourceSurface()
        }
        if let width = customStrokeWidth {
            let target = selectedShape ?? structuralMarkerShape
            target?.lineWidth = width
            hideWallShape?.lineWidth = width + 2
        }
        updateDimensionLabel()
        if wasSelected { updateHighlight() }
    }

    func drawSourceSurface() {
        switch capturedSurface.category {
        case .door:
            drawDoor()
        case .wall:
            drawWall()
            updateDimensionLabel()
        case .window:
            drawWindow()
        case .opening:
            break
        case .floor:
            break
        @unknown default:
            break
        }
    }

    func clearPresentationShapes() {
        [selectedShape, hideWallShape, arcShape, doorSectorShape, windowGlassShape, structuralMarkerShape]
            .forEach { $0?.removeFromParent() }
        selectedShape = nil
        hideWallShape = nil
        arcShape = nil
        doorSectorShape = nil
        windowGlassShape = nil
        structuralMarkerShape = nil
    }
    
    func drawWall(with wallWidth: CGFloat = DrawParameters.wallWidth) {
        let wallPath = CGMutablePath.create(from: pointA, to: pointB)
        if let existingWall = selectedShape {
            existingWall.path = wallPath
        } else {
            let newWallShape = SKShapeNode.create(
                from: wallPath,
                strokeColor: AppTheme.wallStroke,
                lineWidth: wallWidth
            )
            newWallShape.lineCap = .square
            selectedShape = newWallShape
            addChild(newWallShape)
        }
    }
    
    func drawDoor() {
        let doorPath = CGMutablePath.create(from: pointA, to: pointC)
        let hideWallPath = CGMutablePath.create(from: pointA, to: pointB)
        let doorArcPath = createArcPath()
        let sectorPath = createDoorSectorPath()
        
        if let hideWallShape = hideWallShape {
            hideWallShape.path = hideWallPath
        } else {
            let node = SKShapeNode.create(
                from: hideWallPath,
                strokeColor: AppTheme.canvasBg,
                lineWidth: DrawParameters.hideSurfaceWidth,
                zPosition: DrawParameters.hideSurfaceZPosition
            )
            self.hideWallShape = node
            addChild(node)
        }

        if let sector = doorSectorShape {
            sector.path = sectorPath
        } else {
            let node = SKShapeNode(path: sectorPath)
            node.fillColor = AppTheme.doorFill
            node.strokeColor = .clear
            node.zPosition = DrawParameters.doorZPosition - 1
            self.doorSectorShape = node
            addChild(node)
        }
        
        if let doorShape = selectedShape {
            doorShape.path = doorPath
        } else {
            let node = SKShapeNode.create(
                from: doorPath,
                strokeColor: AppTheme.doorStroke,
                lineWidth: 8.0,
                zPosition: DrawParameters.doorZPosition
            )
            node.lineCap = .square
            selectedShape = node
            addChild(node)
        }
        
        if let doorArcShape = arcShape {
            doorArcShape.path = doorArcPath
        } else {
            let node = SKShapeNode.create(
                from: doorArcPath,
                strokeColor: AppTheme.doorStroke,
                lineWidth: DrawParameters.doorArcWidth,
                zPosition: DrawParameters.doorArcZPosition
            )
            self.arcShape = node
            addChild(node)
        }
    }

    func drawWideOpening() {
        let path = CGMutablePath()
        let openingLine = CGMutablePath.create(from: pointA, to: pointB)
        path.addPath(openingLine.copy(dashingWithPhase: 0, lengths: [10, 7]))
        let jambLength: CGFloat = 12
        for point in [pointA, pointB] {
            path.move(to: CGPoint(x: point.x, y: -jambLength / 2))
            path.addLine(to: CGPoint(x: point.x, y: jambLength / 2))
        }
        if let shape = selectedShape {
            shape.path = path
        } else {
            let shape = SKShapeNode.create(
                from: path,
                strokeColor: UIColor(red: 0.12, green: 0.55, blue: 0.48, alpha: 1),
                lineWidth: 7,
                zPosition: DrawParameters.doorZPosition
            )
            shape.lineCap = .square
            selectedShape = shape
            addChild(shape)
        }
    }

    func drawStructuralMarker() {
        let markerWidth: CGFloat
        if effectiveRepresentation == .column {
            markerWidth = min(max(halfLength * 2, 24), 40)
        } else {
            markerWidth = halfLength * 2
        }
        let markerDepth = max(depthInPoints, 16)
        let rect = CGRect(
            x: -markerWidth / 2,
            y: -markerDepth / 2,
            width: markerWidth,
            height: markerDepth
        )
        if structuralMarkerShape == nil {
            let shape = SKShapeNode(rect: rect)
            let markerColor = UIColor(red: 0.47, green: 0.31, blue: 0.72, alpha: 1)
            shape.fillColor = markerColor.withAlphaComponent(0.35)
            shape.strokeColor = markerColor
            shape.lineWidth = 2
            shape.zPosition = DrawParameters.wallWidth
            structuralMarkerShape = shape
            addChild(shape)
        } else {
            structuralMarkerShape?.path = CGPath(rect: rect, transform: nil)
        }
    }
    
    func drawWindow() {
        let hideWallPath = CGMutablePath.create(from: pointA, to: pointB)
        let framePath = CGMutablePath.create(from: pointA, to: pointB)
        
        let glassPath = CGMutablePath()
        let offset: CGFloat = 5.0
        glassPath.move(to: CGPoint(x: -halfLength, y: offset))
        glassPath.addLine(to: CGPoint(x: halfLength, y: offset))
        glassPath.move(to: CGPoint(x: -halfLength, y: -offset))
        glassPath.addLine(to: CGPoint(x: halfLength, y: -offset))
        
        if let hideWallShape = hideWallShape {
            hideWallShape.path = hideWallPath
        } else {
            let node = SKShapeNode.create(
                from: hideWallPath,
                strokeColor: AppTheme.canvasBg,
                lineWidth: DrawParameters.hideSurfaceWidth,
                zPosition: DrawParameters.hideSurfaceZPosition
            )
            self.hideWallShape = node
            addChild(node)
        }
        
        if let windowShape = selectedShape {
            windowShape.path = framePath
        } else {
            let node = SKShapeNode.create(
                from: framePath,
                strokeColor: AppTheme.windowStroke.withAlphaComponent(0.35),
                lineWidth: DrawParameters.windowWidth,
                zPosition: DrawParameters.windowZPosition
            )
            node.lineCap = .butt
            selectedShape = node
            addChild(node)
        }
        
        let isFilledGlass = isFloorToCeilingGlass
        let displayedGlassPath: CGPath
        if isFilledGlass {
            displayedGlassPath = CGPath(
                rect: CGRect(x: -halfLength, y: -8, width: halfLength * 2, height: 16),
                transform: nil
            )
        } else {
            displayedGlassPath = glassPath
        }

        if let glass = windowGlassShape {
            glass.path = displayedGlassPath
            glass.fillColor = AppTheme.windowStroke.withAlphaComponent(0.28)
            glass.strokeColor = AppTheme.windowStroke
            glass.lineWidth = isFilledGlass ? 1.5 : 3.5
        } else {
            let node = SKShapeNode(path: displayedGlassPath)
            node.strokeColor = AppTheme.windowStroke
            node.lineWidth = isFilledGlass ? 1.5 : 3.5
            node.fillColor = AppTheme.windowStroke.withAlphaComponent(0.28)
            node.zPosition = DrawParameters.windowZPosition + 1
            self.windowGlassShape = node
            addChild(node)
        }
    }
    
    func createArcPath() -> CGPath {
        let doorArcPath = CGMutablePath()
        doorArcPath.addArc(
            center: pointA,
            radius: halfLength * 2,
            startAngle: openDirection.arcStartAngle,
            endAngle: openDirection.arcEndAngle,
            clockwise: true
        )
        let dashPattern: [CGFloat] = [14.0, 8.0]
        return doorArcPath.copy(dashingWithPhase: 0, lengths: dashPattern)
    }
    
    func createDoorSectorPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: pointA)
        path.addLine(to: pointB)
        path.addArc(
            center: pointA,
            radius: halfLength * 2,
            startAngle: openDirection.arcStartAngle,
            endAngle: openDirection.arcEndAngle,
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
    
    func updateHighlight() {
        let highlightRect = calculateBoundingRect()
        borderNode?.removeFromParent()
        borderNode = SKShapeNode(rect: highlightRect)
        borderNode?.strokeColor = AppTheme.windowStroke.withAlphaComponent(0.35)
        borderNode?.lineWidth = DrawParameters.wallWidth + 4
        borderNode?.zPosition = DrawParameters.wallWidth + 2
        borderNode?.glowWidth = 6
        if let borderNode = borderNode { addChild(borderNode) }
    }
    
    func calculateBoundingRect() -> CGRect {
        let width = halfLength * 2
        return CGRect(x: -width / 2, y: -2.5, width: width, height: 5.0)
    }
}

