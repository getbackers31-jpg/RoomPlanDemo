import SwiftUI
import SpriteKit
import RoomPlan

struct FloorPlanSceneView: View {
    private let capturedRoom: CapturedRoom
    @ObservedObject var viewModel: FloorPlanViewModel
    @Binding var floorPlanScene: FloorPlanScene?

    init(capturedRoom: CapturedRoom, viewModel: FloorPlanViewModel,
         floorPlanScene: Binding<FloorPlanScene?>) {
        self.capturedRoom = capturedRoom
        self.viewModel = viewModel
        self._floorPlanScene = floorPlanScene
    }

    var body: some View {
        FloorPlanSceneCanvas(capturedRoom: capturedRoom, viewModel: viewModel) { scene in
            floorPlanScene = scene
        }
    }
}

private struct FloorPlanSceneCanvas: UIViewRepresentable {
    private let capturedRoom: CapturedRoom
    @ObservedObject var viewModel: FloorPlanViewModel
    let onSceneCreated: (FloorPlanScene) -> Void

    init(capturedRoom: CapturedRoom, viewModel: FloorPlanViewModel,
         onSceneCreated: @escaping (FloorPlanScene) -> Void) {
        self.capturedRoom = capturedRoom
        self.viewModel = viewModel
        self.onSceneCreated = onSceneCreated
    }

    final class Coordinator {
        var isActive = true
        var drainScheduled = false
        var isDraining = false
        var completedCalibrationIDs = Set<UUID>()
        var inFlight = Set<String>()

        // All reads, consumption and scene mutations run serially on main.
        // A single pending drain coalesces repeated updateUIView calls.
        func schedule(view: SKView, model: FloorPlanViewModel) {
            guard isActive, !drainScheduled, !isDraining else { return }
            drainScheduled = true
            DispatchQueue.main.async { [weak self, weak view, weak model] in
                guard let self else { return }
                self.drainScheduled = false
                guard self.isActive, let view, let model,
                      let scene = view.scene as? FloorPlanScene else { return }
                self.isDraining = true
                defer { self.isDraining = false }
                self.consume(scene: scene, model: model)
            }
        }

        private func run(_ key: String, _ action: () -> Void) {
            guard inFlight.insert(key).inserted else { return }
            defer { inFlight.remove(key) }
            action()
        }

        private func consume(scene: FloorPlanScene, model: FloorPlanViewModel) {
            // Clear each request BEFORE invoking its action. A new request
            // produced by the action is not erased by a trailing reset.
            if let category = model.furnitureToAdd {
                run("furnitureToAdd") {
                    model.furnitureToAdd = nil
                    scene.addNewObject(with: category)
                }
            }
            if model.shouldAddText {
                run("shouldAddText") {
                    model.shouldAddText = false
                    scene.addExampleAnnotations()
                }
            }
            if let format = model.shareFormat {
                run("shareFormat") {
                    model.shareFormat = nil
                    scene.exportImage(with: format)
                }
            }
            if let request = model.calibrationRequest {
                run("calibrationRequest") {
                    model.calibrationRequest = nil
                    if completedCalibrationIDs.insert(request.id).inserted {
                        scene.calibrateWholeRoom(using: request)
                    }
                }
            }
            if model.shouldRotate90 {
                run("shouldRotate90") {
                    model.shouldRotate90 = false
                    scene.rotateView90()
                }
            }
            if model.shouldRecenter {
                run("shouldRecenter") {
                    model.shouldRecenter = false
                    scene.recenterCamera(animated: true)
                }
            }
            if model.shouldUndo {
                run("shouldUndo") {
                    model.shouldUndo = false
                    scene.performUndo()
                }
            }
            if model.shouldRedo {
                run("shouldRedo") {
                    model.shouldRedo = false
                    scene.performRedo()
                }
            }
            if model.shouldSaveProject {
                run("shouldSaveProject") {
                    model.shouldSaveProject = false
                    scene.saveCurrentProject()
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        let scene = FloorPlanScene(capturedRoom: capturedRoom, viewModel: viewModel)
        view.presentScene(scene)
        view.ignoresSiblingOrder = true
        let coordinator = context.coordinator
        let callback = onSceneCreated
        DispatchQueue.main.async { [weak view, weak coordinator] in
            guard let view, let coordinator, coordinator.isActive,
                  view.scene === scene else { return }
            callback(scene)
        }
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {
        guard let scene = view.scene as? FloorPlanScene else { return }
        scene.applyDisplaySettings(
            showFurniture: viewModel.showFurniture,
            showDimensions: viewModel.showDimensions,
            showFurnitureLabels: viewModel.showFurnitureLabels,
            showStructuralMarkers: viewModel.showStructuralMarkers
        )
        context.coordinator.schedule(view: view, model: viewModel)
    }

    static func dismantleUIView(_ view: SKView, coordinator: Coordinator) {
        coordinator.isActive = false
        view.presentScene(nil)
    }
}
