import SpriteKit
import RoomPlan

final class FloorPlanSurface: SKNode, Identifiable {
    let capturedSurface: CapturedRoom.Surface
    var selectedShape: SKShapeNode?
    var openDirection: OpenDirection = .clockwise
    
    private var borderNode: SKShapeNode?
    private var hideWallShape: SKShapeNode?
    private var arcShape: SKShapeNode?
    private var doorSectorShape: SKShapeNode?
    private var windowGlassShape: SKShapeNode?
    
    private var dimensionContainer: SKNode?
    private var dimensionLabel: SKLabelNode?
    private var dimensionBg: SKShapeNode?
    private var isDimensionVisible: Bool = true
    
    var halfLength: CGFloat {
        didSet {
            drawSurface()
        }
    }
    
    private var pointA: CGPoint { CGPoint(x: -halfLength, y: 0) }
    private var pointB: CGPoint { CGPoint(x: halfLength, y: 0) }
    private var pointC: CGPoint { pointB.rotateAround(point: pointA, by: openDirection.angle) }
    
    init(capturedSurface: CapturedRoom.Surface) {
        self.capturedSurface = capturedSurface
        self.halfLength = CGFloat(capturedSurface.dimensions.x) * DrawParameters.scalingFactor / 2
        
        super.init()
        
        let surfacePositionX = -CGFloat(capturedSurface.transform.position.x) * DrawParameters.scalingFactor
        let surfacePositionY = CGFloat(capturedSurface.transform.position.z) * DrawParameters.scalingFactor
        self.position = CGPoint(x: surfacePositionX, y: surfacePositionY)
        self.zRotation = -CGFloat(capturedSurface.transform.eulerAngles.z - capturedSurface.transform.eulerAngles.y)
        
        drawSurface()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension FloorPlanSurface {
    func select() { updateHighlight() }
    func deselect() { borderNode?.removeFromParent() }
    
    func setDimensionVisible(_ visible: Bool) {
        isDimensionVisible = visible
        dimensionContainer?.isHidden = !visible
    }
    
    func updateDoorOpenDirection(to newValue: OpenDirection) {
        self.openDirection = newValue
        drawSurface()
    }
    
    func updateAngleRadians(to newAngle: CGFloat) {
        self.zRotation = newAngle * (.pi / 180)
        updateDimensionLabel()
        (self.scene as? FloorPlanScene)?.recalculateAreaAndExteriorDimensions()
    }
    
    func updateAngle(to newAngle: CGFloat) {
        self.zRotation = newAngle
        updateDimensionLabel()
        (self.scene as? FloorPlanScene)?.recalculateAreaAndExteriorDimensions()
    }
    
    func updateWidth(to newValue: CGFloat) {
        halfLength = newValue
        updateHighlight()
        (self.scene as? FloorPlanScene)?.recalculateAreaAndExteriorDimensions()
    }
    
    func updateDepth(to newValue: CGFloat) {
        selectedShape?.lineWidth = newValue
        hideWallShape?.lineWidth = newValue + 2
    }
    
    func updatePosition(x: Double? = nil, y: Double? = nil, z: Double? = nil) {
        let currentPosition = self.position
        let currentZPosition = self.zPosition
        self.position = CGPoint(x: x ?? currentPosition.x, y: y ?? currentPosition.y)
        self.zPosition = z ?? currentZPosition
        (self.scene as? FloorPlanScene)?.recalculateAreaAndExteriorDimensions()
    }
    
    func applyGlobalScale(ratio: CGFloat, around origin: CGPoint) {
        self.halfLength *= ratio
        let dx = self.position.x - origin.x
        let dy = self.position.y - origin.y
        self.position = CGPoint(x: origin.x + dx * ratio, y: origin.y + dy * ratio)
        if borderNode?.parent != nil {
            updateHighlight()
        }
        updateDimensionLabel()
    }
    
    func updateDimensionLabel() {
        guard capturedSurface.category == .wall else { return }
        
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
        dimensionContainer?.isHidden = !isDimensionVisible
        
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
    func drawSurface() {
        switch capturedSurface.category {
        case .door:
            drawDoor()
        case .wall:
            drawWall()
            updateDimensionLabel()
        case .window:
            drawWindow()
        case .floor, .opening:
            break
        @unknown default:
            break
        }
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
        
        if let glass = windowGlassShape {
            glass.path = glassPath
        } else {
            let node = SKShapeNode.create(
                from: glassPath,
                strokeColor: AppTheme.windowStroke,
                lineWidth: 3.5,
                zPosition: DrawParameters.windowZPosition + 1
            )
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