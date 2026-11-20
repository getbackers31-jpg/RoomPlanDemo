import SwiftUI
import SpriteKit
import RoomPlan

struct FloorPlanSceneView: View {
    private let capturedRoom: CapturedRoom
    @ObservedObject var viewModel: FloorPlanViewModel
    @Binding var floorPlanScene: FloorPlanScene?
    
    init(
        capturedRoom: CapturedRoom,
        viewModel: FloorPlanViewModel,
        floorPlanScene: Binding<FloorPlanScene?>
    ) {
        self.capturedRoom = capturedRoom
        self.viewModel = viewModel
        self._floorPlanScene = floorPlanScene
    }
    
    var body: some View {
        FloorPlanSceneCanvas(
            capturedRoom: capturedRoom,
            viewModel: viewModel,
            onSceneCreated: { scene in
                floorPlanScene = scene
            }
        )
    }
}

private struct FloorPlanSceneCanvas: UIViewRepresentable {
    private let capturedRoom: CapturedRoom
    @ObservedObject var viewModel: FloorPlanViewModel
    let onSceneCreated: (FloorPlanScene) -> Void

    init(
        capturedRoom: CapturedRoom,
        viewModel: FloorPlanViewModel,
        onSceneCreated: @escaping (FloorPlanScene) -> Void
    ) {
        self.capturedRoom = capturedRoom
        self.viewModel = viewModel
        self.onSceneCreated = onSceneCreated
    }

    func makeUIView(context: Context) -> SKView {
        let skView = SKView()
        let scene = FloorPlanScene(capturedRoom: capturedRoom, viewModel: viewModel)
        skView.presentScene(scene)
        skView.ignoresSiblingOrder = true
        DispatchQueue.main.async {
            onSceneCreated(scene)
        }
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
        
        if viewModel.shouldSaveProject {
            DispatchQueue.main.async {
                scene.saveCurrentProject()
                viewModel.shouldSaveProject = false
            }
        }
    }
}