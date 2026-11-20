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
    private let baseDepthInPoints: CGFloat
    private var depthInPoints: CGFloat
    
    private var dimensionContainer: SKNode?
    private var dimensionLabel: SKLabelNode?
    private var dimensionBg: SKShapeNode?
    private var isDimensionVisible: Bool = true
    
    var halfLength: CGFloat {
        didSet {
            if representation == .source,
               capturedSurface.category == .door,
               (oldValue * 2 / DrawParameters.scalingFactor > FloorPlanGeometry.oversizedDoorWidthMeters)
                    != (halfLength * 2 / DrawParameters.scalingFactor > FloorPlanGeometry.oversizedDoorWidthMeters) {
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
        self.calibrationScaleFactor = geometry.scaleFactor
        self.baseDepthInPoints = geometry.depthInMeters / geometry.scaleFactor * geometry.pointsPerMeter
        self.depthInPoints = geometry.depthInMeters * geometry.pointsPerMeter
        self.halfLength = geometry.halfLength
        
        super.init()
        
        self.position = geometry.center
        self.zRotation = geometry.angle
        
        drawSurface()
        if let strokeWidth = geometry.strokeWidth {
            updateDepth(to: strokeWidth)
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension FloorPlanSurface {
    var effectiveRepresentation: FloorPlanSurfaceRepresentation {
        if representation == .source,
           capturedSurface.category == .door,
           halfLength * 2 / DrawParameters.scalingFactor > FloorPlanGeometry.oversizedDoorWidthMeters {
            return .wideOpening
        }
        return representation
    }

    var isOversizedDoor: Bool {
        capturedSurface.category == .door &&
            halfLength * 2 / DrawParameters.scalingFactor > FloorPlanGeometry.oversizedDoorWidthMeters
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
            halfLength * 2 / DrawParameters.scalingFactor < FloorPlanGeometry.minimumWallSegmentLengthMeters
    }

    var isRoomBoundaryGeometry: Bool {
        isWallGeometry ||
            (effectiveRepresentation == .source && capturedSurface.category == .opening)
    }

    func select() { updateHighlight() }
    func deselect() { borderNode?.removeFromParent() }
    
    func setDimensionVisible(_ visible: Bool) {
        isDimensionVisible = visible
        dimensionContainer?.isHidden = !visible
    }
    
    func updateDoorOpenDirection(to newValue: OpenDirection) {
        self.openDirection = newValue
        drawSurface()
        markDirty(reason: "door_open_direction")
    }

    func restoreOpenDirection(to value: OpenDirection) {
        openDirection = value
        drawSurface()
    }

    func restoreStrokeWidth(to value: CGFloat?) {
        guard let value else { return }
        selectedShape?.lineWidth = value
        hideWallShape?.lineWidth = value + 2
    }

    func setRepresentation(_ newValue: FloorPlanSurfaceRepresentation) {
        guard representation != newValue else { return }
        (scene as? FloorPlanScene)?.recordUndoState()
        representation = newValue
        (scene as? FloorPlanScene)?.viewModel.markDirty(reason: "surface_representation")
        (scene as? FloorPlanScene)?.recalculateAreaAndExteriorDimensions()
    }

    func setFloorToCeilingGlass(_ enabled: Bool) {
        guard isFloorToCeilingGlass != enabled else { return }
        (scene as? FloorPlanScene)?.recordUndoState()
        isFloorToCeilingGlass = enabled
        (scene as? FloorPlanScene)?.viewModel.markDirty(reason: "floor_to_ceiling_glass")
    }

    func restoreCalibrationScaleFactor(to value: CGFloat) {
        calibrationScaleFactor = value
        depthInPoints = baseDepthInPoints * value
        drawSurface()
    }
    
    func updateAngleRadians(to newAngle: CGFloat) {
        self.zRotation = newAngle * (.pi / 180)
        updateDimensionLabel()
        (self.scene as? FloorPlanScene)?.recalculateAreaAndExteriorDimensions()
        markDirty(reason: "surface_angle")
    }
    
    func updateAngle(to newAngle: CGFloat) {
        self.zRotation = newAngle
        updateDimensionLabel()
        (self.scene as? FloorPlanScene)?.recalculateAreaAndExteriorDimensions()
        markDirty(reason: "surface_angle")
    }
    
    func updateWidth(to newValue: CGFloat) {
        halfLength = newValue
        updateHighlight()
        (self.scene as? FloorPlanScene)?.recalculateAreaAndExteriorDimensions()
        markDirty(reason: "surface_width")
    }
    
    func updateDepth(to newValue: CGFloat) {
        selectedShape?.lineWidth = newValue
        hideWallShape?.lineWidth = newValue + 2
        markDirty(reason: "surface_stroke_width")
    }
    
    func updatePosition(x: Double? = nil, y: Double? = nil, z: Double? = nil) {
        let currentPosition = self.position
        let currentZPosition = self.zPosition
        self.position = CGPoint(x: x ?? currentPosition.x, y: y ?? currentPosition.y)
        self.zPosition = z ?? currentZPosition
        (self.scene as? FloorPlanScene)?.recalculateAreaAndExteriorDimensions()
        markDirty(reason: "surface_position")
    }
    
    func applyGlobalScale(ratio: CGFloat, around origin: CGPoint) {
        calibrationScaleFactor *= ratio
        depthInPoints = baseDepthInPoints * calibrationScaleFactor
        self.halfLength *= ratio
        let dx = self.position.x - origin.x
        let dy = self.position.y - origin.y
        self.position = CGPoint(x: origin.x + dx * ratio, y: origin.y + dy * ratio)
        if borderNode?.parent != nil {
            updateHighlight()
        }
        drawSurface()
        updateDimensionLabel()
    }
    
    func updateDimensionLabel() {
        guard isWallGeometry else {
            dimensionContainer?.removeFromParent()
            dimensionContainer = nil
            dimensionLabel = nil
            dimensionBg = nil
            return
        }
        
        let lengthCm = Double(halfLength * 2 / DrawParameters.scalingFactor) * 100.0
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
        switch effectiveRepresentation {
        case .solidWall:
            drawWall()
            updateDimensionLabel()
        case .wideOpening:
            drawWideOpening()
        case .beam, .column:
            drawStructuralMarker()
        case .source:
            drawSourceSurface()
        }
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