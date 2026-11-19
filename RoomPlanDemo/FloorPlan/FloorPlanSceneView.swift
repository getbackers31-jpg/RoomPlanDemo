import SwiftUI
import SpriteKit
import RoomPlan

struct FloorPlanSceneView: UIViewRepresentable {
    private let capturedRoom: CapturedRoom
    @ObservedObject var viewModel: FloorPlanViewModel
    
    init(capturedRoom: CapturedRoom, viewModel: FloorPlanViewModel) {
        self.capturedRoom = capturedRoom
        self.viewModel = viewModel
    }
    
    func makeUIView(context: Context) -> SKView {
        let skView = SKView()
        let scene = FloorPlanScene(capturedRoom: capturedRoom, viewModel: viewModel)
        skView.presentScene(scene)
        skView.ignoresSiblingOrder = true
        return skView
    }
    
    func updateUIView(_ uiView: SKView, context: Context) {
        guard let scene = uiView.scene as? FloorPlanScene else { return }
        
        scene.applyDisplaySettings(
            showFurniture: viewModel.showFurniture,
            showDimensions: viewModel.showDimensions,
            showFurnitureLabels: viewModel.showFurnitureLabels
        )
        
        if let selectedFurniture = viewModel.furnitureToAdd {
            DispatchQueue.main.async {
                scene.addNewObject(with: selectedFurniture)
                viewModel.furnitureToAdd = nil
            }
        }
        
        if viewModel.shouldAddText {
            DispatchQueue.main.async {
                scene.addExampleAnnotations()
                viewModel.shouldAddText = false
            }
        }
        
        if let shareType = viewModel.shareFormat {
            DispatchQueue.main.async {
                scene.exportImage(with: shareType)
                viewModel.shareFormat = nil
            }
        }
        
        if viewModel.shouldOrthogonalize {
            DispatchQueue.main.async {
                scene.orthogonalizeWalls()
                viewModel.shouldOrthogonalize = false
            }
        }
        
        if let ratio = viewModel.calibrationScaleRatio {
            DispatchQueue.main.async {
                scene.calibrateWholeRoom(by: ratio)
                viewModel.calibrationScaleRatio = nil
            }
        }
        
        if viewModel.shouldRotate90 {
            DispatchQueue.main.async {
                scene.rotateView90()
                viewModel.shouldRotate90 = false
            }
        }
        
        if viewModel.shouldRecenter {
            DispatchQueue.main.async {
                scene.recenterCamera(animated: true)
                viewModel.shouldRecenter = false
            }
        }
        
        if viewModel.shouldUndo {
            DispatchQueue.main.async {
                scene.performUndo()
                viewModel.shouldUndo = false
            }
        }
        
        if viewModel.shouldRedo {
            DispatchQueue.main.async {
                scene.performRedo()
                viewModel.shouldRedo = false
            }
        }
    }
}