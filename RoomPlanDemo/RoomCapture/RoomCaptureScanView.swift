import SwiftUI
import SpriteKit
import RoomPlan

struct RoomCaptureScanView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: RoomCaptureViewModel = .init()
    @StateObject private var floorPlanViewModel = FloorPlanViewModel()
    @StateObject private var mockDataManager = MockDataManager()
    
    @State private var isEditingUsage: Bool = false
    @State private var draftUsage: String = ""
    @State private var draftFloor: String = "1F"
    @State private var loadedSavedRoom: CapturedRoom? = nil
    @State private var savedRoomLoadFailed: Bool = false
    @State private var showThermalWarning: Bool = false
    @State private var showCancelScanConfirm: Bool = false
    @State private var showUnsavedChangesAlert: Bool = false
    @State private var hasInitializedAppearance: Bool = false
    
    private let isDemo: Bool
    private let savedProject: SavedRoomProject?
    
    init(isDemo: Bool = false, savedProject: SavedRoomProject? = nil) {
        self.isDemo = isDemo
        self.savedProject = savedProject
    }
    
    private var isDisplayingBlueprint: Bool {
        isDemo || savedProject != nil || viewModel.isShowingFloorPlan
    }
    
    var body: some View {
        ZStack {
            mainRoomView
            
            if isDisplayingBlueprint {
                blueprintOverlay
            } else {
                liveScanOverlay
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
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            let state = ProcessInfo.processInfo.thermalState
            if !isDisplayingBlueprint && (state == .serious || state == .critical) {
                showThermalWarning = true
            }
        }
        .alert("裝置溫度偏高", isPresented: $showThermalWarning) {
            Button("我知道了", role: .cancel) {}
        } message: {
            Text("iPhone 目前發熱較明顯，可能會造成光達掃描漂移或降頻。建議先結束本次掃描並儲存，待降溫後再繼續。")
        }
        .alert("確定要放棄本次掃描？", isPresented: $showCancelScanConfirm) {
            Button("繼續掃描", role: .cancel) {}
            Button("放棄並返回", role: .destructive) {
                UIApplication.shared.isIdleTimerDisabled = false
                dismiss()
            }
        } message: {
            Text("目前掃描中的空間進度尚未儲存，返回首頁將會清空。")
        }
        .onReceive(NotificationCenter.default.publisher(for: .floorPlanModelDidMutate)) { note in
            let reason = (note.object as? String) ?? "detail_panel_edit"
            floorPlanViewModel.markDirty(reason: reason)
        }
        .onChange(of: floorPlanViewModel.didCompleteSaveForDismiss) { done in
            if done {
                floorPlanViewModel.didCompleteSaveForDismiss = false
                dismiss()
            }
        }
        .alert("尚有未儲存的修改", isPresented: $showUnsavedChangesAlert) {
            Button("儲存並離開") {
                floorPlanViewModel.shouldDismissAfterSave = true
                floorPlanViewModel.shouldSaveProject = true
            }
            Button("放棄修改", role: .destructive) {
                floorPlanViewModel.clearDirty()
                dismiss()
            }
            Button("繼續編輯", role: .cancel) {}
        } message: {
            Text("離開後未儲存的編輯將會遺失，重新開啟時會恢復為上次存檔狀態。")
        }
        .toolbar(isDisplayingBlueprint ? .hidden : .visible, for: .navigationBar)
        .onAppear {
            guard !hasInitializedAppearance else { return }
            hasInitializedAppearance = true
            if let project = savedProject {
                floorPlanViewModel.savedProjectID = project.id
                floorPlanViewModel.loadWallLockPreference(for: project.id)
                floorPlanViewModel.roomUsage = project.name
                floorPlanViewModel.floorLabel = project.floorLabel
                floorPlanViewModel.roomAreaPing = project.areaPing
                floorPlanViewModel.roomAreaSqm = project.areaSqm
                floorPlanViewModel.initialEditState = RoomProjectStore.shared.loadEditState(for: project)
                if let room = RoomProjectStore.shared.loadCapturedRoom(for: project) {
                    loadedSavedRoom = room
                } else {
                    savedRoomLoadFailed = true
                }
            } else if !isDemo {
                UIApplication.shared.isIdleTimerDisabled = true
                viewModel.startSession()
            }
        }
        .alert("編輯空間資訊", isPresented: $isEditingUsage) {
            TextField("空間名稱（如：客廳、主臥室）", text: $draftUsage)
            TextField("樓層（如：1F、2F）", text: $draftFloor)
            Button("儲存") {
                var didChangeMeta = false
                let trimmedName = draftUsage.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedName.isEmpty && trimmedName != floorPlanViewModel.roomUsage {
                    floorPlanViewModel.roomUsage = trimmedName
                    didChangeMeta = true
                }
                let trimmedFloor = draftFloor.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedFloor.isEmpty && trimmedFloor != floorPlanViewModel.floorLabel {
                    floorPlanViewModel.floorLabel = trimmedFloor
                    didChangeMeta = true
                }
                if didChangeMeta {
                    floorPlanViewModel.markDirty(reason: "edit_room_info")
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
    var liveScanOverlay: some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "viewfinder")
                    .foregroundColor(Color(red: 0.96, green: 0.84, blue: 0.56))
                Text(viewModel.isScanning
                     ? "緩慢平穩掃描四周牆面、門窗與家具，完成後點擊右上角結束掃描"
                     : "掃描已完成，可檢視 2D 藍圖或匯出 3D 模型")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.black.opacity(0.72))
            .clipShape(Capsule())
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            Spacer()
            
            if !viewModel.isScanning {
                Button {
                    floorPlanViewModel.autoOrthogonalizeOnLoad = true
                    viewModel.handleScanButtonTap()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                        Text("檢視 2D 藍圖並自動直角對齊")
                            .fontWeight(.bold)
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 13)
                    .background(AppTheme.accentBlue)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.28), radius: 6, y: 3)
                }
                .padding(.bottom, 28)
            }
        }
    }
    
    var blueprintOverlay: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    if floorPlanViewModel.isDirty && !isDemo {
                        showUnsavedChangesAlert = true
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.14))
                        .clipShape(Circle())
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(floorPlanViewModel.floorLabel)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.accentBlue)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        
                        Text(floorPlanViewModel.roomUsage)
                            .font(.headline)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Button {
                            draftUsage = floorPlanViewModel.roomUsage
                            draftFloor = floorPlanViewModel.floorLabel
                            isEditingUsage = true
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .foregroundColor(.white.opacity(0.75))
                                .font(.subheadline)
                        }
                    }
                    
                    Text(String(format: "室內實測：約 %.2f 坪 (%.1f ㎡)", floorPlanViewModel.roomAreaPing, floorPlanViewModel.roomAreaSqm))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(red: 0.96, green: 0.84, blue: 0.56))
                }
                
                Spacer()
                
                Button {
                    floorPlanViewModel.shouldSaveProject = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: floorPlanViewModel.savedProjectID == nil ? "square.and.arrow.down.fill" : "checkmark.circle.fill")
                        Text(floorPlanViewModel.savedProjectID == nil ? "儲存" : "更新")
                    }
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(AppTheme.accentAmber)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppTheme.primaryBarBg.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            .padding(.horizontal, 12)
            .padding(.top, 4)
            
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
                        title: floorPlanViewModel.isWallLocked ? "已鎖牆" : "鎖牆",
                        icon: floorPlanViewModel.isWallLocked ? "lock.fill" : "lock.open",
                        isActive: floorPlanViewModel.isWallLocked
                    ) {
                        floorPlanViewModel.setWallLocked(!floorPlanViewModel.isWallLocked)
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
            
            if let toast = floorPlanViewModel.statusToastMessage {
                Text(toast)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.82))
                    .clipShape(Capsule())
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                            withAnimation { floorPlanViewModel.statusToastMessage = nil }
                        }
                    }
            }
            
            Spacer()
            
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
        if savedProject != nil {
            if let room = loadedSavedRoom {
                FloorPlanSceneView(capturedRoom: room, viewModel: floorPlanViewModel)
                    .ignoresSafeArea()
            } else if savedRoomLoadFailed {
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("找不到此空間的存檔資料")
                        .font(.headline)
                    Button("返回首頁") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("載入空間藍圖中...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        } else if isDemo {
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
                        ToolbarItem(placement: .topBarLeading) {
                            Button("取消") {
                                if viewModel.isScanning {
                                    showCancelScanConfirm = true
                                } else {
                                    dismiss()
                                }
                            }
                                .foregroundColor(.white)
                        }
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