import SwiftUI
import SpriteKit
import RoomPlan
import SceneKit

struct RoomCaptureScanView: View {
    @StateObject private var viewModel: RoomCaptureViewModel = .init()
    @StateObject private var floorPlanViewModel = FloorPlanViewModel()
    @StateObject private var mockDataManager = MockDataManager()
    
    private let isDemo: Bool
    
    init(isDemo: Bool = false) {
        self.isDemo = isDemo
    }
    
    var body: some View {
        ZStack {
            mainRoomView
            
            // 2D 平面圖頂部「一鍵正交直角對齊」與狀態提示橫幅
            if isDemo || viewModel.isShowingFloorPlan {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            withAnimation {
                                floorPlanViewModel.shouldOrthogonalize = true
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "angle")
                                Text("一鍵直角對齊")
                                    .fontWeight(.bold)
                            }
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Color.indigo)
                            .clipShape(Capsule())
                            .shadow(radius: 3)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    
                    if let toast = floorPlanViewModel.statusToastMessage {
                        Text(toast)
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.78))
                            .clipShape(Capsule())
                            .transition(.opacity)
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                                    withAnimation { floorPlanViewModel.statusToastMessage = nil }
                                }
                            }
                    }
                    Spacer()
                }
            }
            
            if floorPlanViewModel.selectedObject != nil {
                VStack {
                    Spacer()
                    ObjectDetailsView(
                        object: $floorPlanViewModel.selectedObject,
                        selectedType: $floorPlanViewModel.selectedType)
                    .frame(height: 200)
                    .padding(.horizontal, 20)
                }
            }
            
            if (isDemo || viewModel.isShowingFloorPlan),
               floorPlanViewModel.selectedObject == nil, floorPlanViewModel.selectedSurface == nil {
                VStack {
                    Spacer()
                    RoomOptionsView(
                        selectedOption: $floorPlanViewModel.roomOptionType,
                        shouldAddFurniture: $floorPlanViewModel.shouldAddFurniture,
                        shouldAddText: $floorPlanViewModel.shouldAddText,
                        shouldShareImage: $floorPlanViewModel.shouldShareImage)
                    .frame(height: 150)
                    .padding(.horizontal, 20)
                }
            }
            
            if floorPlanViewModel.selectedAnnotation != nil {
                VStack {
                    Spacer()
                    AnnotationsDetailsView(selectedAnnotation: $floorPlanViewModel.selectedAnnotation)
                        .frame(height: 250)
                        .padding(.horizontal, 20)
                }
            }
        }
        .onAppear {
            if !isDemo { viewModel.startSession() }
        }
        .sheet(item: $floorPlanViewModel.selectedSurface, content: { _ in
            SurfaceDetailsView(
                surface: $floorPlanViewModel.selectedSurface,
                selectedType: $floorPlanViewModel.selectedType,
                floorPlanViewModel: floorPlanViewModel)
            .presentationDetents([.fraction(0.45), .medium])
            .interactiveDismissDisabled()
            .ignoresSafeArea()
        })
        .sheet(
            isPresented: Binding(
                get: { floorPlanViewModel.roomOptionType == .exportImage },
                set: { if !$0 { floorPlanViewModel.roomOptionType = nil } }
            ), content: {
                ShareImageView(
                    shouldShareImage: $floorPlanViewModel.shouldShareImage,
                    shareFormat: $floorPlanViewModel.shareFormat,
                    roomOptionType: $floorPlanViewModel.roomOptionType)
                .presentationDetents([.fraction(0.3)])
                .interactiveDismissDisabled()
                .ignoresSafeArea()
            })
        .sheet(isPresented: $floorPlanViewModel.shouldAddFurniture,
               onDismiss: {
            floorPlanViewModel.roomOptionType = nil
            floorPlanViewModel.furnitureToAdd = nil
        }, content: {
            AddFurnitureView(floorPlanViewModel: floorPlanViewModel)
            .presentationDetents([.fraction(0.4)])
            .interactiveDismissDisabled()
            .ignoresSafeArea()
        })
        .alert("錯誤", isPresented: $viewModel.isShowError, actions: {
            Button("確定", role: .cancel) {}
        }, message: {
            Text(viewModel.errorMessage)
        })
    }
}

private extension RoomCaptureScanView {
    @ViewBuilder
    var mainRoomView: some View {
        if isDemo {
            if let finalRoom = mockDataManager.loadCapturedRoom() {
                FloorPlanSceneView(capturedRoom: finalRoom, viewModel: floorPlanViewModel)
                    .ignoresSafeArea()
            }
        } else {
            if viewModel.isShowingFloorPlan,
               let finalRoom = viewModel.getFinalRoom() {
                FloorPlanSceneView(capturedRoom: finalRoom, viewModel: floorPlanViewModel)
                    .ignoresSafeArea()
            } else {
                RoomCaptureRepresentable(roomCaptureView: viewModel.roomCaptureView)
                    .ignoresSafeArea()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { scanButtonView }
                        if !viewModel.isScanning {
                            ToolbarItem(placement: .topBarTrailing) { shareButtonView }
                        }
                    }
            }
        }
    }
    
    var scanButtonView: some View {
        let title = viewModel.isScanning ? "結束掃描" : "檢視 2D 平面圖"
        return Button(action: { viewModel.handleScanButtonTap() }) {
            Text(title)
                .foregroundColor(.white)
                .fontWeight(.regular)
                .padding(2)
                .padding(.horizontal, 5)
                .background(Color.red)
                .clipShape(Capsule())
        }
    }
    
    var shareButtonView: some View {
        Button(action: { viewModel.shareCapturedRoom() }) {
            Text("匯出 3D 模型")
                .foregroundColor(.white)
                .padding(2)
                .padding(.horizontal, 5)
                .background(Color.green)
                .clipShape(Capsule())
                .fontWeight(.regular)
        }
    }
}