import SpriteKit
import RoomPlan

final class FloorPlanObject: SKNode {
    let capturedObject: CapturedRoom.Object?
    let objectCategory: CapturedRoom.Object.Category
    
    private var vectorContainer: SKNode?
    private var labelContainer: SKNode?
    private var nameLabel: SKLabelNode?
    private var sizeLabel: SKLabelNode?
    private var borderNode: SKShapeNode?
    
    private var baseWidthPt: CGFloat
    private var baseHeightPt: CGFloat
    
    var currentWidthCm: Double {
        let ptToCm = 100.0 / Double(DrawParameters.scalingFactor)
        return Double(baseWidthPt) * Double(abs(xScale)) * ptToCm
    }
    
    var currentHeightCm: Double {
        let ptToCm = 100.0 / Double(DrawParameters.scalingFactor)
        return Double(baseHeightPt) * Double(abs(yScale)) * ptToCm
    }
    
    init(geometry: FloorPlanObjectGeometry) {
        self.capturedObject = geometry.source
        self.objectCategory = geometry.source.category
        self.baseWidthPt = geometry.baseWidthInPoints
        self.baseHeightPt = geometry.baseDepthInPoints

        super.init()
        self.position = geometry.center
        self.zRotation = geometry.angle
        self.xScale = geometry.xScale
        self.yScale = geometry.yScale
        self.zPosition = DrawParameters.objectZPosition

        drawVectorFurniture()
        setupLabels()
        updateSizeLabel()
    }

    init(withCategory type: CapturedRoom.Object.Category, objectPosition: CGPoint = .zero) {
        self.capturedObject = nil
        self.objectCategory = type
        self.baseWidthPt = 80
        self.baseHeightPt = 60

        super.init()
        self.position = objectPosition
        self.zRotation = 0
        self.zPosition = DrawParameters.objectZPosition

        drawVectorFurniture()
        setupLabels()
        updateSizeLabel()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension FloorPlanObject {
    func updateAngle(to newAngle: CGFloat) {
        self.zRotation = newAngle * (.pi / 180)
        updateLabelOrientation()
        (scene as? FloorPlanScene)?.viewModel.markDirty(reason: "object_angle")
    }
    
    func select() {
        highlight()
    }
    
    func deselect() {
        borderNode?.removeFromParent()
        borderNode = nil
    }
    
    func setLabelVisible(_ visible: Bool) {
        labelContainer?.isHidden = !visible
    }
    
    func applyGlobalScale(ratio: CGFloat, around origin: CGPoint) {
        let dx = self.position.x - origin.x
        let dy = self.position.y - origin.y
        self.position = CGPoint(x: origin.x + dx * ratio, y: origin.y + dy * ratio)
        self.xScale *= ratio
        self.yScale *= ratio
        updateSizeLabel()
    }
    
    func updateSizeLabel() {
        sizeLabel?.text = String(format: "%.0f×%.0f", currentWidthCm, currentHeightCm)
        updateLabelOrientation()
    }
}

private extension FloorPlanObject {
    var chineseCategoryName: String {
        switch objectCategory {
        case .storage: return "櫃體"
        case .refrigerator: return "冰箱"
        case .stove: return "爐具"
        case .bed: return "床鋪"
        case .sink: return "洗手台"
        case .washerDryer: return "洗烘機"
        case .toilet: return "馬桶"
        case .bathtub: return "浴缸"
        case .oven: return "烤箱"
        case .dishwasher: return "洗碗機"
        case .table: return "桌子"
        case .sofa: return "沙發"
        case .chair: return "椅子"
        case .fireplace: return "壁爐"
        case .television: return "電視"
        case .stairs: return "樓梯"
        @unknown default: return "家具"
        }
    }
    
    func highlight() {
        borderNode?.removeFromParent()
        let rect = CGRect(x: -baseWidthPt / 2, y: -baseHeightPt / 2, width: baseWidthPt, height: baseHeightPt)
        let node = SKShapeNode(rect: rect, cornerRadius: 4)
        node.strokeColor = AppTheme.windowStroke
        node.lineWidth = 4
        node.zPosition = DrawParameters.objectOutlineZPosition
        addChild(node)
        borderNode = node
    }
    
    func drawVectorFurniture() {
        vectorContainer?.removeFromParent()
        let container = SKNode()
        container.zPosition = 0
        
        let w = baseWidthPt
        let h = baseHeightPt
        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        
        let body = SKShapeNode(rect: rect, cornerRadius: 4)
        body.fillColor = AppTheme.furnitureFill
        body.strokeColor = AppTheme.furnitureStroke
        body.lineWidth = 3.0
        container.addChild(body)
        
        let detailPath = CGMutablePath()
        switch objectCategory {
        case .bed:
            let pillowW = w * 0.36
            let pillowH = min(h * 0.22, 42)
            let topY = h / 2 - pillowH - 10
            detailPath.addRoundedRect(in: CGRect(x: -w * 0.42, y: topY, width: pillowW, height: pillowH), cornerWidth: 6, cornerHeight: 6)
            detailPath.addRoundedRect(in: CGRect(x: w * 0.06, y: topY, width: pillowW, height: pillowH), cornerWidth: 6, cornerHeight: 6)
            detailPath.move(to: CGPoint(x: -w / 2, y: topY - 14))
            detailPath.addLine(to: CGPoint(x: w / 2, y: topY - 14))
        case .sofa:
            let armW = min(w * 0.14, 24)
            let backH = min(h * 0.26, 36)
            detailPath.move(to: CGPoint(x: -w / 2 + armW, y: -h / 2))
            detailPath.addLine(to: CGPoint(x: -w / 2 + armW, y: h / 2 - backH))
            detailPath.addLine(to: CGPoint(x: w / 2 - armW, y: h / 2 - backH))
            detailPath.addLine(to: CGPoint(x: w / 2 - armW, y: -h / 2))
        case .storage:
            detailPath.move(to: CGPoint(x: -w / 2 + 8, y: 0))
            detailPath.addLine(to: CGPoint(x: w / 2 - 8, y: 0))
            let steps = max(2, Int(w / 45))
            for i in 1..<steps {
                let x = -w / 2 + (w / CGFloat(steps)) * CGFloat(i)
                detailPath.move(to: CGPoint(x: x, y: -h / 2 + 8))
                detailPath.addLine(to: CGPoint(x: x, y: h / 2 - 8))
            }
        case .table:
            let insetRect = rect.insetBy(dx: min(w * 0.1, 14), dy: min(h * 0.1, 14))
            detailPath.addRect(insetRect)
        case .bathtub:
            let innerTub = rect.insetBy(dx: min(w * 0.12, 16), dy: min(h * 0.12, 16))
            detailPath.addRoundedRect(in: innerTub, cornerWidth: 16, cornerHeight: 16)
        case .sink:
            let basin = rect.insetBy(dx: w * 0.16, dy: h * 0.18)
            detailPath.addRoundedRect(in: basin, cornerWidth: 10, cornerHeight: 10)
        case .toilet:
            detailPath.move(to: CGPoint(x: -w / 2, y: h * 0.15))
            detailPath.addLine(to: CGPoint(x: w / 2, y: h * 0.15))
            let bowl = CGRect(x: -w * 0.34, y: -h * 0.42, width: w * 0.68, height: h * 0.52)
            detailPath.addEllipse(in: bowl)
        case .stairs:
            let treads = max(4, Int(max(w, h) / 28))
            if h >= w {
                for i in 1..<treads {
                    let y = -h / 2 + (h / CGFloat(treads)) * CGFloat(i)
                    detailPath.move(to: CGPoint(x: -w / 2, y: y))
                    detailPath.addLine(to: CGPoint(x: w / 2, y: y))
                }
            } else {
                for i in 1..<treads {
                    let x = -w / 2 + (w / CGFloat(treads)) * CGFloat(i)
                    detailPath.move(to: CGPoint(x: x, y: -h / 2))
                    detailPath.addLine(to: CGPoint(x: x, y: h / 2))
                }
            }
        default:
            let insetRect = rect.insetBy(dx: min(w * 0.1, 10), dy: min(h * 0.1, 10))
            detailPath.addRect(insetRect)
        }
        
        let detailNode = SKShapeNode(path: detailPath)
        detailNode.strokeColor = AppTheme.furnitureStroke.withAlphaComponent(0.65)
        detailNode.lineWidth = 2.0
        container.addChild(detailNode)
        
        addChild(container)
        vectorContainer = container
    }
    
    func setupLabels() {
        let container = SKNode()
        container.zPosition = 5
        
        let fontSize = max(13, min(20, min(baseWidthPt, baseHeightPt) * 0.18))
        
        let name = SKLabelNode(fontNamed: "Helvetica-Bold")
        name.text = chineseCategoryName
        name.fontSize = fontSize
        name.fontColor = AppTheme.dimensionText
        name.verticalAlignmentMode = .center
        name.horizontalAlignmentMode = .center
        name.position = CGPoint(x: 0, y: fontSize * 0.62)
        
        let size = SKLabelNode(fontNamed: "Helvetica")
        size.fontSize = fontSize * 0.88
        size.fontColor = AppTheme.dimensionText.withAlphaComponent(0.8)
        size.verticalAlignmentMode = .center
        size.horizontalAlignmentMode = .center
        size.position = CGPoint(x: 0, y: -fontSize * 0.62)
        
        container.addChild(name)
        container.addChild(size)
        addChild(container)
        
        self.labelContainer = container
        self.nameLabel = name
        self.sizeLabel = size
    }
    
    func updateLabelOrientation() {
        var angleDeg = Double(zRotation) * 180.0 / .pi
        angleDeg = angleDeg.truncatingRemainder(dividingBy: 360.0)
        if angleDeg > 180 { angleDeg -= 360 }
        if angleDeg < -180 { angleDeg += 360 }
        labelContainer?.zRotation = (angleDeg > 90 || angleDeg < -90) ? .pi : 0
    }
}