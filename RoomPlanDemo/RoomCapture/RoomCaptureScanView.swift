import SwiftUI
import SpriteKit
import RoomPlan
import SceneKit

struct RoomCaptureScanView: View {
    @StateObject private var viewModel: RoomCaptureViewModel = .init()
    @StateObject private var floorPlanViewModel = FloorPlanViewModel()
    @StateObject private var mockDataManager = MockDataManager()
    
    @State private var isEditingUsage: Bool = false
    @State private var draftUsage: String = ""
    
    private let isDemo: Bool
    
    init(isDemo: Bool = false) {
        self.isDemo = isDemo
    }
    
    var body: some View {
        ZStack {
            mainRoomView
            
            if isDemo || viewModel.isShowingFloorPlan {
                blueprintOverlay
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
        .alert("編輯空間用途", isPresented: $isEditingUsage) {
            TextField("例如：客廳、主臥室、書房", text: $draftUsage)
            Button("儲存") {
                let trimmed = draftUsage.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    floorPlanViewModel.roomUsage = trimmed
                }
            }
            Button("取消", role: .cancel) {}
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
    var blueprintOverlay: some View {
        VStack(spacing: 8) {
            // 1. 頂部面積坪數與用途資訊卡
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(floorPlanViewModel.roomUsage)
                            .font(.headline)
                            .foregroundColor(.white)
                        Button {
                            draftUsage = floorPlanViewModel.roomUsage
                            isEditingUsage = true
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .foregroundColor(.white.opacity(0.75))
                                .font(.subheadline)
                        }
                    }
                    
                    Text(String(format: "室內實測：約 %.2f 坪 (%.1f ㎡)", floorPlanViewModel.roomAreaPing, floorPlanViewModel.roomAreaSqm))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(red: 0.96, green: 0.84, blue: 0.56))
                }
                Spacer()
                Text("單位: cm")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppTheme.primaryBarBg.opacity(0.94))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            .padding(.horizontal, 12)
            .padding(.top, 4)
            
            // 2. 圖層開關與工程工具列
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    toggleChip(
                        title: floorPlanViewModel.showFurniture ? "含家具" : "隱藏家具",
                        icon: floorPlanViewModel.showFurniture ? "eye.fill" : "eye.slash",
                        isActive: floorPlanViewModel.showFurniture
                    ) {
                        floorPlanViewModel.showFurniture.toggle()
                    }
                    
                    toggleChip(
                        title: "尺寸標註",
                        icon: "ruler",
                        isActive: floorPlanViewModel.showDimensions
                    ) {
                        floorPlanViewModel.showDimensions.toggle()
                    }
                    
                    toggleChip(
                        title: "家具標籤",
                        icon: "tag",
                        isActive: floorPlanViewModel.showFurnitureLabels
                    ) {
                        floorPlanViewModel.showFurnitureLabels.toggle()
                    }
                    
                    Divider().frame(height: 20).background(Color.gray.opacity(0.5))
                    
                    actionChip(title: "直角對齊", icon: "angle", bg: AppTheme.accentBlue) {
                        floorPlanViewModel.shouldOrthogonalize = true
                    }
                    
                    actionChip(title: "轉 90°", icon: "rotate.right", bg: AppTheme.primaryBarBg) {
                        floorPlanViewModel.shouldRotate90 = true
                    }
                    
                    actionChip(title: "置中", icon: "scope", bg: AppTheme.primaryBarBg) {
                        floorPlanViewModel.shouldRecenter = true
                    }
                }
                .padding(.horizontal, 12)
            }
            
            // 3. 狀態提示橫幅
            if let toast = floorPlanViewModel.statusToastMessage {
                Text(toast)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.8))
                    .clipShape(Capsule())
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                            withAnimation { floorPlanViewModel.statusToastMessage = nil }
                        }
                    }
            }
            
            Spacer()
            
            // 4. 右側浮動復原 / 重做按鈕與底部圖例列
            if floorPlanViewModel.selectedObject == nil && floorPlanViewModel.selectedSurface == nil && floorPlanViewModel.selectedAnnotation == nil {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        circleToolButton(icon: "arrow.uturn.backward", enabled: floorPlanViewModel.canUndo) {
                            floorPlanViewModel.shouldUndo = true
                        }
                        circleToolButton(icon: "arrow.uturn.forward", enabled: floorPlanViewModel.canRedo) {
                            floorPlanViewModel.shouldRedo = true
                        }
                    }
                    .padding(.trailing, 14)
                }
                .padding(.bottom, 6)
                
                HStack(spacing: 12) {
                    legendItem(color: Color(uiColor: AppTheme.wallStroke), label: "結構牆")
                    legendItem(color: Color(uiColor: AppTheme.doorStroke), label: "門扇")
                    legendItem(color: Color(uiColor: AppTheme.windowStroke), label: "窗戶")
                    legendItem(color: Color(uiColor: AppTheme.furnitureStroke), label: "向量家具")
                }
                .font(.caption2)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.92))
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.1), radius: 3)
                
                RoomOptionsView(
                    selectedOption: $floorPlanViewModel.roomOptionType,
                    shouldAddFurniture: $floorPlanViewModel.shouldAddFurniture,
                    shouldAddText: $floorPlanViewModel.shouldAddText,
                    shouldShareImage: $floorPlanViewModel.shouldShareImage)
                .frame(height: 110)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
        }
    }
    
    func toggleChip(title: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(isActive ? AppTheme.toggleActiveBg : AppTheme.toggleInactiveBg)
            .clipShape(Capsule())
        }
    }
    
    func actionChip(title: String, icon: String, bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(bg)
            .clipShape(Capsule())
        }
    }
    
    func circleToolButton(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(enabled ? .white : .white.opacity(0.35))
                .frame(width: 42, height: 42)
                .background(AppTheme.primaryBarBg.opacity(enabled ? 0.9 : 0.45))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 3)
        }
        .disabled(!enabled)
    }
    
    func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundColor(.black.opacity(0.8))
        }
    }
    
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