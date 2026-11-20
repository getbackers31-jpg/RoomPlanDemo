import SwiftUI
import SpriteKit
import RoomPlan

struct FloorPlanSceneView: View {
    private let capturedRoom: CapturedRoom
    @ObservedObject var viewModel: FloorPlanViewModel
    @State private var floorPlanScene: FloorPlanScene?
    @State private var previewEditState: FloorPlanEditState?
    @State private var isShowing3DPreview = false
    
    init(capturedRoom: CapturedRoom, viewModel: FloorPlanViewModel) {
        self.capturedRoom = capturedRoom
        self.viewModel = viewModel
    }
    
    var body: some View {
        FloorPlanSceneCanvas(
            capturedRoom: capturedRoom,
            viewModel: viewModel,
            onSceneCreated: { scene in
                floorPlanScene = scene
            }
        )
        .overlay(alignment: .topTrailing) {
            Button {
                guard let floorPlanScene else { return }
                previewEditState = floorPlanScene.exportEditState()
                isShowing3DPreview = true
            } label: {
                Label("3D 預覽", systemImage: "cube")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.72), in: Capsule())
            }
            .disabled(floorPlanScene == nil)
            .padding(.top, 64)
            .padding(.trailing, 16)
        }
        .sheet(isPresented: $isShowing3DPreview) {
            NavigationStack {
                if let previewEditState {
                    FloorPlan3DPreviewView(
                        capturedRoom: capturedRoom,
                        editState: previewEditState
                    )
                    .navigationTitle("3D 預覽")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") {
                                isShowing3DPreview = false
                            }
                        }
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
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
        
        if viewModel.shouldSaveProject {
            DispatchQueue.main.async {
                scene.saveCurrentProject()
                viewModel.shouldSaveProject = false
            }
        }
    }
}