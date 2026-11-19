import RoomPlan
import SpriteKit
import RealityKit
import SwiftUI

final class FloorPlanScene: SKScene {
    let viewModel: FloorPlanViewModel
    private var previousCameraScale = CGFloat()
    private var previousCameraPosition = CGPoint()
    
    private let surfaces: [CapturedRoom.Surface]
    private let objects: [CapturedRoom.Object]
    private let capturedRoom: CapturedRoom
    
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
        drawSurfaces()
        drawObjects()
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

// MARK: - 核心工程演算法：正交直角對齊 & 單邊基準尺全域縮放
extension FloorPlanScene {
    func orthogonalizeWalls() {
        let surfaceNodes = children.compactMap { $0 as? FloorPlanSurface }
        let wallNodes = surfaceNodes.filter { $0.capturedSurface.category == .wall }
        guard let primaryWall = wallNodes.max(by: { $0.halfLength < $1.halfLength }) else { return }
        
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
        
        viewModel.statusToastMessage = "已完成 \(alignedCount) 面牆體與門窗正交直角對齊"
    }
    
    func calibrateWholeRoom(by ratio: CGFloat) {
        guard ratio > 0.1 && ratio < 10.0 else { return }
        let surfaceNodes = children.compactMap { $0 as? FloorPlanSurface }
        let objectNodes = children.compactMap { $0 as? FloorPlanObject }
        guard !surfaceNodes.isEmpty else { return }
        
        let sumX = surfaceNodes.reduce(CGFloat(0)) { $0 + $1.position.x }
        let sumY = surfaceNodes.reduce(CGFloat(0)) { $0 + $1.position.y }
        let center = CGPoint(x: sumX / CGFloat(surfaceNodes.count), y: sumY / CGFloat(surfaceNodes.count))
        
        for surface in surfaceNodes {
            surface.applyGlobalScale(ratio: ratio, around: center)
        }
        
        for obj in objectNodes {
            let dx = obj.position.x - center.x
            let dy = obj.position.y - center.y
            obj.position = CGPoint(x: center.x + dx * ratio, y: center.y + dy * ratio)
            obj.setScale(obj.xScale * ratio)
        }
        
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
        
        if let selectedObject = viewModel.selectedObject, selectedObject.contains(locationInScene) {
            if sender.state == .changed { selectedObject.position = locationInScene }
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
        addChild(newFloorPlanObject)
    }
    
    func addExampleAnnotations() {
        guard let camera = self.camera else { return }
        let annotation = FloorPlanAnnotation(title: "區域標註", subtitle: "點擊編輯文字", fontSize: 40, fontColor: .blue)
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
    
    /// 產生 1:1 公分 (cm) 比例的 AutoCAD R12 DXF 檔案內容
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
        
        // HEADER ($INSUNITS = 5 代表公分 cm)
        lines.append(contentsOf: [
            "0", "SECTION",
            "2", "HEADER",
            "9", "$INSUNITS",
            "70", "5",
            "0", "ENDSEC"
        ])
        
        // TABLES (定義 5 個 CAD 標準圖層)
        let layerDefs: [(String, String)] = [
            ("WALLS", "7"),       // 白色/黑色
            ("DOORS", "1"),       // 紅色
            ("WINDOWS", "5"),     // 藍色
            ("DIMENSIONS", "3"),  // 綠色
            ("FURNITURE", "8")    // 灰色
        ]
        lines.append(contentsOf: ["0", "SECTION", "2", "TABLES", "0", "TABLE", "2", "LAYER", "70", "\(layerDefs.count)"])
        for (name, color) in layerDefs {
            lines.append(contentsOf: ["0", "LAYER", "2", name, "70", "0", "62", color, "6", "CONTINUOUS"])
        }
        lines.append(contentsOf: ["0", "ENDTAB", "0", "ENDSEC"])
        
        // ENTITIES
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
                
                // 牆面公分文字標註 (自動修正文字正向與法向量偏移)
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
        
        // 匯出家具矩形外框
        let objectNodes = children.compactMap { $0 as? FloorPlanObject }
        for obj in objectNodes {
            let cx = Double(obj.position.x) * ptToCm
            let cy = Double(obj.position.y) * ptToCm
            let hw = Double(obj.capturedObject.dimensions.x) * 100.0 * Double(obj.xScale) / 2.0
            let hh = Double(obj.capturedObject.dimensions.z) * 100.0 * Double(obj.yScale) / 2.0
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