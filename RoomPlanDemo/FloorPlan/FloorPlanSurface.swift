import SpriteKit
import RoomPlan

final class FloorPlanSurface: SKNode, Identifiable {
    let capturedSurface: CapturedRoom.Surface
    var selectedShape: SKShapeNode?
    var openDirection: OpenDirection = .clockwise
    
    private var borderNode: SKShapeNode?
    private var hideWallShape: SKShapeNode?
    private var arcShape: SKShapeNode?
    
    // 牆面尺寸標註元件
    private var dimensionContainer: SKNode?
    private var dimensionLabel: SKLabelNode?
    private var dimensionBg: SKShapeNode?
    
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
    
    func updateDoorOpenDirection(to newValue: OpenDirection) {
        self.openDirection = newValue
        drawSurface()
    }
    
    func updateAngleRadians(to newAngle: CGFloat) {
        self.zRotation = newAngle * (.pi / 180)
        updateDimensionLabel()
    }
    
    func updateAngle(to newAngle: CGFloat) {
        self.zRotation = newAngle
        updateDimensionLabel()
    }
    
    func updateWidth(to newValue: CGFloat) {
        halfLength = newValue
        updateHighlight()
    }
    
    func updateDepth(to newValue: CGFloat) {
        selectedShape?.lineWidth = newValue
        hideWallShape?.lineWidth = newValue
    }
    
    func updatePosition(x: Double? = nil, y: Double? = nil, z: Double? = nil) {
        let currentPosition = self.position
        let currentZPosition = self.zPosition
        self.position = CGPoint(x: x ?? currentPosition.x, y: y ?? currentPosition.y)
        self.zPosition = z ?? currentZPosition
    }
    
    /// 依據全域校準比例，等比例縮放牆面長度與相對中心點的位置
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
    
    /// 更新牆面公分尺寸文字與正向角度
    func updateDimensionLabel() {
        guard capturedSurface.category == .wall else { return }
        
        let lengthCm = Double(halfLength * 2 / DrawParameters.scalingFactor) * 100.0
        let text = String(format: "%.1f cm", lengthCm)
        
        if dimensionLabel == nil {
            let container = SKNode()
            container.zPosition = 35
            
            let label = SKLabelNode(fontNamed: "Helvetica-Bold")
            label.fontSize = 24
            label.fontColor = .darkGray
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            
            let bg = SKShapeNode()
            bg.fillColor = UIColor.white.withAlphaComponent(0.88)
            bg.strokeColor = UIColor.lightGray.withAlphaComponent(0.6)
            bg.lineWidth = 1.5
            bg.zPosition = -1
            
            container.addChild(bg)
            container.addChild(label)
            addChild(container)
            
            self.dimensionContainer = container
            self.dimensionLabel = label
            self.dimensionBg = bg
        }
        
        dimensionLabel?.text = text
        
        if let label = dimensionLabel, let bg = dimensionBg {
            let padX: CGFloat = 10
            let padY: CGFloat = 6
            let rect = CGRect(
                x: -label.frame.width / 2 - padX,
                y: -label.frame.height / 2 - padY,
                width: label.frame.width + padX * 2,
                height: label.frame.height + padY * 2
            )
            bg.path = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        }
        
        // 避免文字倒置：牆面角度超過 ±90° 時自動翻轉標籤
        var angleDeg = Double(zRotation) * 180.0 / .pi
        angleDeg = angleDeg.truncatingRemainder(dividingBy: 360.0)
        if angleDeg > 180 { angleDeg -= 360 }
        if angleDeg < -180 { angleDeg += 360 }
        
        if angleDeg > 90 || angleDeg < -90 {
            dimensionContainer?.zRotation = .pi
            dimensionContainer?.position = CGPoint(x: 0, y: -34)
        } else {
            dimensionContainer?.zRotation = 0
            dimensionContainer?.position = CGPoint(x: 0, y: 34)
        }
    }
}

private extension FloorPlanSurface {
    func drawSurface() {
        switch capturedSurface.category {
        case .door: drawDoor()
        case .wall:
            drawWall()
            updateDimensionLabel()
        case .window: drawWindow()
        case .floor, .opening: break
        @unknown default: break
        }
    }
    
    func drawWall(with wallWidth: CGFloat = DrawParameters.wallWidth) {
        let wallPath = CGMutablePath.create(from: pointA, to: pointB)
        if let existingWall = selectedShape {
            existingWall.path = wallPath
        } else {
            let newWallShape = SKShapeNode.create(from: wallPath, strokeColor: .black, lineWidth: wallWidth)
            newWallShape.lineCap = .square
            selectedShape = newWallShape
            addChild(newWallShape)
        }
    }
    
    func drawDoor() {
        let doorPath = CGMutablePath.create(from: pointA, to: pointC)
        let hideWallPath = CGMutablePath.create(from: pointA, to: pointB)
        let doorArcPath = createArcPath()
        
        if let doorShape = selectedShape {
            doorShape.path = doorPath
        } else {
            let doorShape = SKShapeNode.create(from: doorPath, zPosition: DrawParameters.doorZPosition)
            doorShape.lineCap = .square
            selectedShape = doorShape
            addChild(doorShape)
        }
        
        if let hideWallShape = hideWallShape {
            hideWallShape.path = hideWallPath
        } else {
            let hideWallShape = SKShapeNode.create(from: hideWallPath, strokeColor: DrawParameters.floorPlanSurfaceColor, lineWidth: DrawParameters.hideSurfaceWidth, zPosition: DrawParameters.hideSurfaceZPosition)
            self.hideWallShape = hideWallShape
            addChild(hideWallShape)
        }
        
        if let doorArcShape = arcShape {
            doorArcShape.path = doorArcPath
        } else {
            let doorArcShape = SKShapeNode.create(from: doorArcPath, lineWidth: DrawParameters.doorArcWidth, zPosition: DrawParameters.doorArcZPosition)
            self.arcShape = doorArcShape
            addChild(doorArcShape)
        }
    }
    
    func drawWindow() {
        let windowPath = CGMutablePath.create(from: pointA, to: pointC)
        let hideWallPath = CGMutablePath.create(from: pointA, to: pointB)
        let windowArcPath = createArcPath()
        
        if let windowShape = selectedShape {
            windowShape.path = windowPath
        } else {
            let windowShape = SKShapeNode.create(from: windowPath, zPosition: DrawParameters.windowZPosition)
            windowShape.lineCap = .square
            selectedShape = windowShape
            addChild(windowShape)
        }
        
        if let hideWallShape = hideWallShape {
            hideWallShape.path = hideWallPath
        } else {
            let hideWallShape = SKShapeNode.create(from: hideWallPath, strokeColor: DrawParameters.floorPlanSurfaceColor, lineWidth: DrawParameters.hideSurfaceWidth, zPosition: DrawParameters.hideSurfaceZPosition)
            self.hideWallShape = hideWallShape
            addChild(hideWallShape)
        }
        
        if let windowArcShape = arcShape {
            windowArcShape.path = windowArcPath
        } else {
            let windowArcShape = SKShapeNode.create(from: windowArcPath, lineWidth: DrawParameters.doorArcWidth, zPosition: DrawParameters.windowZPosition)
            self.arcShape = windowArcShape
            addChild(windowArcShape)
        }
    }
    
    func createArcPath() -> CGPath {
        let doorArcPath = CGMutablePath()
        doorArcPath.addArc(center: pointA, radius: halfLength * 2, startAngle: openDirection.arcStartAngle, endAngle: openDirection.arcEndAngle, clockwise: true)
        let dashPattern: [CGFloat] = [24.0, 8.0]
        return doorArcPath.copy(dashingWithPhase: 1, lengths: dashPattern)
    }
    
    func updateHighlight() {
        let highlightRect = calculateBoundingRect()
        borderNode?.removeFromParent()
        borderNode = SKShapeNode(rect: highlightRect)
        borderNode?.strokeColor = .blue.withAlphaComponent(0.2)
        borderNode?.lineWidth = DrawParameters.surfaceWidth + 2
        borderNode?.zPosition = DrawParameters.surfaceWidth + 1
        borderNode?.glowWidth = DrawParameters.surfaceWidth + 2
        if let borderNode = borderNode { addChild(borderNode) }
    }
    
    func calculateBoundingRect() -> CGRect {
        let width = halfLength * 2
        return CGRect(x: -width / 2, y: -2.5, width: width, height: 5.0)
    }
}