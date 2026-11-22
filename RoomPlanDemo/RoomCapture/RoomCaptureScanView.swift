import Foundation
import SwiftUI
import SpriteKit
import RoomPlan
import UIKit

@MainActor
struct RoomCaptureScanView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = RoomCaptureViewModel()
    @StateObject private var floorPlanViewModel = FloorPlanViewModel()
    @StateObject private var mockDataManager = MockDataManager()
    @State private var isEditingUsage = false
    @State private var draftUsage = ""
    @State private var draftFloor = "1F"
    @State private var loadedSavedRoom: CapturedRoom?
    @State private var demoRoom: CapturedRoom?
    @State private var savedRoomLoadFailed = false
    @State private var showThermalWarning = false
    @State private var showCancelScanConfirm = false
    @State private var showUnsavedChangesAlert = false
    @State private var hasInitializedAppearance = false
    @State private var floorPlanScene: FloorPlanScene?
    @State private var previewEditState: FloorPlanEditState?
    @State private var previewCapturedRoom: CapturedRoom?
    @State private var isShowing3DPreview = false
    @State private var preparedForBlueprint = false
    private let isDemo: Bool
    private let savedProject: SavedRoomProject?

    init(isDemo: Bool = false, savedProject: SavedRoomProject? = nil) {
        self.isDemo = isDemo
        self.savedProject = savedProject
    }

    private var blueprintRoom: CapturedRoom? {
        guard preparedForBlueprint else { return nil }
        if savedProject != nil { return loadedSavedRoom }
        if isDemo { return demoRoom }
        guard viewModel.phase == .ready, viewModel.isShowingFloorPlan else { return nil }
        return viewModel.getFinalRoom()
    }

    private var isDisplayingBlueprint: Bool { blueprintRoom != nil }

    var body: some View {
        ZStack {
            mainRoomView
            if isDisplayingBlueprint { blueprintOverlay }
            else if savedProject == nil && !isDemo { liveScanOverlay }
            if isDisplayingBlueprint, floorPlanViewModel.selectedObject != nil {
                VStack {
                    Spacer()
                    ObjectDetailsView(object: $floorPlanViewModel.selectedObject,
                                      selectedType: $floorPlanViewModel.selectedType)
                        .frame(height: 200).padding(.horizontal, 20)
                }
            }
            if isDisplayingBlueprint, floorPlanViewModel.selectedAnnotation != nil {
                VStack {
                    Spacer()
                    AnnotationsDetailsView(selectedAnnotation: $floorPlanViewModel.selectedAnnotation)
                        .frame(height: 250).padding(.horizontal, 20)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(isDisplayingBlueprint ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            if !isDisplayingBlueprint {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消", action: requestLeave)
                }
                if savedProject == nil && !isDemo {
                    ToolbarItem(placement: .topBarTrailing) { scanButtonView }
                    if viewModel.phase == .ready {
                        ToolbarItem(placement: .topBarTrailing) { shareButtonView }
                    }
                }
            }
        }
        .onAppear(perform: initializeAppearance)
        .onDisappear {
            // A preview sheet must not cancel the parent editor. Only an
            // unfinished capture is invalidated when this screen disappears.
            if viewModel.phase == .scanning || viewModel.phase == .processing {
                viewModel.cancelSession()
            }
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: viewModel.autoSavedProject?.id) { _, _ in
            adoptAutoSavedDraft()
        }
        .onChange(of: viewModel.phase) { _, phase in
            if phase == .ready { adoptAutoSavedDraft() }
        }
        .onChange(of: floorPlanViewModel.didCompleteSaveForDismiss) { _, done in
            if done {
                floorPlanViewModel.didCompleteSaveForDismiss = false
                leaveScreen()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            let state = ProcessInfo.processInfo.thermalState
            if viewModel.phase == .scanning && (state == .serious || state == .critical) {
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
            Button("放棄並返回", role: .destructive, action: leaveScreen)
        } message: {
            Text("目前掃描中的空間進度尚未儲存，返回首頁將會清空。")
        }
        .alert("尚有未儲存的修改", isPresented: $showUnsavedChangesAlert) {
            Button("儲存並離開") {
                floorPlanViewModel.shouldDismissAfterSave = true
                floorPlanViewModel.shouldSaveProject = true
            }
            Button("放棄修改", role: .destructive, action: leaveScreen)
            Button("繼續編輯", role: .cancel) {}
        } message: {
            Text("離開後未儲存的編輯將會遺失，重新開啟時會恢復為上次存檔狀態。")
        }
        .alert("編輯空間資訊", isPresented: $isEditingUsage) {
            TextField("空間名稱（如：客廳、主臥室）", text: $draftUsage)
            TextField("樓層（如：1F、2F）", text: $draftFloor)
            Button("儲存", action: saveMetadata)
            Button("取消", role: .cancel) {}
        }
        .alert("錯誤", isPresented: $viewModel.isShowError) {
            Button("確定", role: .cancel) {}
        } message: { Text(viewModel.errorMessage) }
        .sheet(item: $floorPlanViewModel.selectedSurface) { _ in
            SurfaceDetailsView(surface: $floorPlanViewModel.selectedSurface,
                               selectedType: $floorPlanViewModel.selectedType,
                               floorPlanViewModel: floorPlanViewModel)
                .presentationDetents([.fraction(0.45), .medium])
                .interactiveDismissDisabled().ignoresSafeArea()
        }
        .sheet(isPresented: Binding(
            get: { floorPlanViewModel.roomOptionType == .exportImage },
            set: { if !$0 { floorPlanViewModel.roomOptionType = nil } }
        )) {
            ShareImageView(shouldShareImage: $floorPlanViewModel.shouldShareImage,
                           shareFormat: $floorPlanViewModel.shareFormat,
                           roomOptionType: $floorPlanViewModel.roomOptionType)
                .presentationDetents([.fraction(0.3)])
                .interactiveDismissDisabled().ignoresSafeArea()
        }
        .sheet(isPresented: $floorPlanViewModel.shouldAddFurniture, onDismiss: {
            floorPlanViewModel.roomOptionType = nil
            // Do not clear furnitureToAdd here: the canvas owns consumption.
        }) {
            AddFurnitureView(floorPlanViewModel: floorPlanViewModel)
                .presentationDetents([.fraction(0.4)])
                .interactiveDismissDisabled().ignoresSafeArea()
        }
        .sheet(isPresented: $isShowing3DPreview) {
            NavigationStack {
                if let previewCapturedRoom {
                    FloorPlan3DPreviewView(capturedRoom: previewCapturedRoom,
                                           editState: previewEditState)
                        .navigationTitle("3D 預覽")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("完成") { isShowing3DPreview = false }
                            }
                        }
                }
            }
            .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
    }
}

private extension RoomCaptureScanView {
    func initializeAppearance() {
        guard !hasInitializedAppearance else { return }
        hasInitializedAppearance = true
        if let project = savedProject {
            floorPlanViewModel.adoptSavedProject(project)
            floorPlanViewModel.roomUsage = project.name
            floorPlanViewModel.floorLabel = project.floorLabel
            floorPlanViewModel.initialEditState = RoomProjectStore.shared.loadEditState(for: project)
            loadedSavedRoom = RoomProjectStore.shared.loadCapturedRoom(for: project)
            savedRoomLoadFailed = loadedSavedRoom == nil
            preparedForBlueprint = loadedSavedRoom != nil
        } else if isDemo {
            demoRoom = mockDataManager.loadCapturedRoom()
            savedRoomLoadFailed = demoRoom == nil
            preparedForBlueprint = demoRoom != nil
        } else {
            viewModel.startSession()
        }
    }

    func adoptAutoSavedDraft() {
        guard savedProject == nil, !isDemo,
              let project = viewModel.autoSavedProject,
              floorPlanViewModel.savedProjectID != project.id else { return }
        floorPlanViewModel.adoptSavedProject(project)
    }

    func enterBlueprint() {
        guard viewModel.phase == .ready, viewModel.getFinalRoom() != nil else { return }
        // Synchronous adoption before setting either presentation gate.
        adoptAutoSavedDraft()
        preparedForBlueprint = true
        viewModel.handleScanButtonTap()
    }

    func requestLeave() {
        if viewModel.phase == .scanning || viewModel.phase == .processing {
            showCancelScanConfirm = true
        } else if isDisplayingBlueprint && floorPlanViewModel.isDirty && !isDemo {
            showUnsavedChangesAlert = true
        } else { leaveScreen() }
    }

    func leaveScreen() {
        viewModel.cancelSession()
        UIApplication.shared.isIdleTimerDisabled = false
        dismiss()
    }

    func saveMetadata() {
        let name = draftUsage.trimmingCharacters(in: .whitespacesAndNewlines)
        let floor = draftFloor.trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = false
        if !name.isEmpty && name != floorPlanViewModel.roomUsage {
            floorPlanViewModel.roomUsage = name
            changed = true
        }
        if !floor.isEmpty && floor != floorPlanViewModel.floorLabel {
            floorPlanViewModel.floorLabel = floor
            changed = true
        }
        if changed { floorPlanViewModel.markDirty(reason: "edit_room_info") }
    }

    @ViewBuilder var mainRoomView: some View {
        if let room = blueprintRoom {
            FloorPlanSceneView(capturedRoom: room, viewModel: floorPlanViewModel,
                               floorPlanScene: $floorPlanScene).ignoresSafeArea()
        } else if savedProject != nil || isDemo {
            if savedRoomLoadFailed {
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle).foregroundStyle(.orange)
                    Text("找不到此空間的存檔資料").font(.headline)
                    Button("返回首頁", action: leaveScreen).buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("載入空間藍圖中...").foregroundStyle(.secondary)
                }
            }
        } else {
            RoomCaptureRepresentable(roomCaptureView: viewModel.roomCaptureView)
                .id(ObjectIdentifier(viewModel.roomCaptureView))
                .ignoresSafeArea()
        }
    }

    var scanButtonView: some View {
        Button {
            if viewModel.phase == .ready { enterBlueprint() }
            else { viewModel.handleScanButtonTap() }
        } label: {
            Text(scanButtonTitle).foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Color.red).clipShape(Capsule())
        }
        .disabled(viewModel.phase == .processing)
    }

    var scanButtonTitle: String {
        switch viewModel.phase {
        case .idle: return "開始掃描"
        case .scanning: return "結束掃描"
        case .processing: return "處理中..."
        case .ready: return "檢視 2D 平面圖"
        case .failed: return "重新掃描"
        case .cancelled: return "開始掃描"
        }
    }

    var shareButtonView: some View {
        Button(action: viewModel.shareCapturedRoom) {
            Text("匯出 3D 模型").foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Color.green).clipShape(Capsule())
        }
        .disabled(viewModel.phase != .ready)
    }

    var scanStatusText: String {
        switch viewModel.phase {
        case .idle: return "準備開始掃描"
        case .scanning:
            return "緩慢掃描牆面、門窗與家具；轉角、斜角及寬開口請放慢並多繞一圈補齊"
        case .processing: return "正在處理空間掃描資料，請稍候..."
        case .ready: return "掃描已完成，可檢視 2D 藍圖或匯出 3D 模型"
        case .failed: return "掃描或資料處理失敗，請重新掃描。"
        case .cancelled: return "掃描已取消"
        }
    }

    var liveScanOverlay: some View {
        VStack {
            Text(scanStatusText).font(.caption).foregroundStyle(.white)
                .padding(12).background(Color.black.opacity(0.72))
                .clipShape(Capsule()).padding(.horizontal, 16)
            Spacer()
            if viewModel.phase == .processing {
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text("正在處理空間掃描資料，請稍候...").foregroundStyle(.white)
                }
                .padding(24).background(Color.black.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else if viewModel.phase == .ready {
                Button(action: enterBlueprint) {
                    Label("檢視 2D 藍圖", systemImage: "map")
                        .foregroundStyle(.white).padding(16)
                        .background(AppTheme.accentBlue).clipShape(Capsule())
                }
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    var blueprintOverlay: some View {
        VStack(spacing: 8) {
            blueprintHeader
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    toggleChip(title: floorPlanViewModel.showFurniture ? "含家具" : "隱藏家具",
                               icon: "eye", isActive: floorPlanViewModel.showFurniture) {
                        floorPlanViewModel.showFurniture.toggle()
                    }
                    toggleChip(title: floorPlanViewModel.isWallLocked ? "已鎖牆" : "鎖牆",
                               icon: floorPlanViewModel.isWallLocked ? "lock.fill" : "lock.open",
                               isActive: floorPlanViewModel.isWallLocked) {
                        floorPlanViewModel.setWallLocked(!floorPlanViewModel.isWallLocked)
                    }
                    toggleChip(title: "尺寸標註", icon: "ruler",
                               isActive: floorPlanViewModel.showDimensions) {
                        floorPlanViewModel.showDimensions.toggle()
                    }
                    toggleChip(title: "樑柱標記", icon: "square.dashed",
                               isActive: floorPlanViewModel.showStructuralMarkers) {
                        floorPlanViewModel.showStructuralMarkers.toggle()
                    }
                    toggleChip(title: "家具標籤", icon: "tag",
                               isActive: floorPlanViewModel.showFurnitureLabels) {
                        floorPlanViewModel.showFurnitureLabels.toggle()
                    }
                    actionChip(title: "轉 90°", icon: "rotate.right") {
                        floorPlanViewModel.shouldRotate90 = true
                    }
                    actionChip(title: "置中", icon: "scope") {
                        floorPlanViewModel.shouldRecenter = true
                    }
                }.padding(.horizontal, 12)
            }
            if let toast = floorPlanViewModel.statusToastMessage {
                Text(toast).font(.footnote).foregroundStyle(.white)
                    .padding(10).background(Color.black.opacity(0.82)).clipShape(Capsule())
                    .task(id: toast) {
                        try? await Task.sleep(for: .seconds(2.6))
                        guard !Task.isCancelled,
                              floorPlanViewModel.statusToastMessage == toast else { return }
                        floorPlanViewModel.statusToastMessage = nil
                    }
            }
            Spacer()
            if floorPlanViewModel.selectedObject == nil &&
                floorPlanViewModel.selectedSurface == nil &&
                floorPlanViewModel.selectedAnnotation == nil {
                HStack {
                    Spacer()
                    circleToolButton(icon: "arrow.uturn.backward", enabled: floorPlanViewModel.canUndo) {
                        floorPlanViewModel.shouldUndo = true
                    }
                    circleToolButton(icon: "arrow.uturn.forward", enabled: floorPlanViewModel.canRedo) {
                        floorPlanViewModel.shouldRedo = true
                    }
                }.padding(.trailing, 14)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        legendItem(color: Color(uiColor: AppTheme.wallStroke), label: "結構牆")
                        legendItem(color: Color(uiColor: AppTheme.doorStroke), label: "門扇")
                        legendItem(color: Color(uiColor: AppTheme.windowStroke), label: "窗戶")
                        legendItem(color: Color(uiColor: AppTheme.furnitureStroke), label: "向量家具")
                        legendItem(color: .purple, label: "樑柱標記")
                    }.font(.caption2).padding(10).background(Color.white.opacity(0.92))
                }
                RoomOptionsView(selectedOption: $floorPlanViewModel.roomOptionType,
                                shouldAddFurniture: $floorPlanViewModel.shouldAddFurniture,
                                shouldAddText: $floorPlanViewModel.shouldAddText,
                                shouldShareImage: $floorPlanViewModel.shouldShareImage)
                    .frame(height: 110).padding(.horizontal, 16).padding(.bottom, 4)
            }
        }
    }

    var blueprintHeader: some View {
        HStack(spacing: 10) {
            Button(action: requestLeave) {
                Image(systemName: "chevron.left").foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(floorPlanViewModel.floorLabel).font(.caption2).bold()
                    Text(floorPlanViewModel.roomUsage).font(.headline).lineLimit(1)
                    Button {
                        draftUsage = floorPlanViewModel.roomUsage
                        draftFloor = floorPlanViewModel.floorLabel
                        isEditingUsage = true
                    } label: { Image(systemName: "pencil.circle.fill") }
                }
                if floorPlanViewModel.isRoomBoundaryClosed {
                    Text(String(format: "室內實測：約 %.2f 坪 (%.1f ㎡)",
                                floorPlanViewModel.roomAreaPing, floorPlanViewModel.roomAreaSqm))
                        .font(.caption).foregroundStyle(.yellow)
                } else {
                    Text("輪廓未閉合").font(.caption).foregroundStyle(.yellow)
                }
            }.foregroundStyle(.white)
            Spacer(minLength: 0)
            Button {
                guard let scene = floorPlanScene else { return }
                previewEditState = scene.exportEditState()
                previewCapturedRoom = scene.capturedRoom
                isShowing3DPreview = true
            } label: { Label("3D 預覽", systemImage: "cube").font(.caption) }
            .disabled(floorPlanScene == nil)
            Button {
                floorPlanViewModel.shouldSaveProject = true
            } label: {
                Text(floorPlanViewModel.savedProjectID == nil ? "儲存" : "更新").font(.caption).bold()
            }
            .disabled(floorPlanScene == nil)
        }
        .tint(.white).padding(12).background(AppTheme.primaryBarBg.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 12)
    }

    func toggleChip(title: String, icon: String, isActive: Bool,
                    action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.white)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(isActive ? AppTheme.toggleActiveBg : AppTheme.toggleInactiveBg)
                .clipShape(Capsule())
        }
    }

    func actionChip(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(AppTheme.primaryBarBg).clipShape(Capsule())
        }
    }

    func circleToolButton(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(AppTheme.primaryBarBg.opacity(enabled ? 0.9 : 0.45))
                .clipShape(Circle())
        }.disabled(!enabled)
    }

    func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.black.opacity(0.8))
        }
    }
}
