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
    /// 一鍵將所有偏差在 20 度以內的牆面與門窗對齊至主軸正交直角 (0° / 90° / 180° / 270°)
    func orthogonalizeWalls() {
        let surfaceNodes = children.compactMap { $0 as? FloorPlanSurface }
        let wallNodes = surfaceNodes.filter { $0.capturedSurface.category == .wall }
        guard let primaryWall = wallNodes.max(by: { $0.halfLength < $1.halfLength }) else { return }
        
        let baseAngle = primaryWall.zRotation
        let snapStep: CGFloat = .pi / 2 // 90度
        let maxDeviation: CGFloat = 20.0 * (.pi / 180.0) // 容許20度內自動拉直，保留刻意設計的斜牆
        var alignedCount = 0
        
        for node in surfaceNodes {
            let diff = node.zRotation - baseAngle
            let nearestQuarter = round(diff / snapStep) * snapStep
            let residual = atan2(sin(diff - nearestQuarter), cos(diff - nearestQuarter))
            
            if abs(residual) <= maxDeviation {
                node.zRotation = baseAngle + nearestQuarter
                alignedCount += 1
            }
        }
        
        // 同步將整張平面圖旋轉至水平/垂直正放視角
        if let camera = self.camera {
            camera.zRotation = baseAngle
        }
        
        viewModel.statusToastMessage = "已完成 \(alignedCount) 面牆體與門窗正交直角對齊"
    }
    
    /// 依據單面基準牆的實測比例，等比例校準整張空間平面圖
    func calibrateWholeRoom(by ratio: CGFloat) {
        guard ratio > 0.1 && ratio < 10.0 else { return }
        let surfaceNodes = children.compactMap { $0 as? FloorPlanSurface }
        let objectNodes = children.compactMap { $0 as? FloorPlanObject }
        guard !surfaceNodes.isEmpty else { return }
        
        // 計算所有牆面幾何中心作為縮放基準原點
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
        
        viewModel.statusToastMessage = String(format: "已依基準尺全域縮放校準 (比例 %.3fx)", ratio)
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