import SwiftUI
import RoomPlan

struct SurfaceDetailsView: View {
    @Binding var surface: FloorPlanSurface?
    @Binding var selectedType: DetailsType?
    @ObservedObject var floorPlanViewModel: FloorPlanViewModel
    
    @State private var angle: CGFloat = 0
    @State private var width: CGFloat = 0
    @State private var depth: CGFloat = 0
    @State private var position: CGPoint = .init(x: 0, y: 0)
    @State private var zPosition: CGFloat = 0
    @State private var selectedDirection: OpenDirection = .clockwise
    @State private var realLengthCmText: String = ""
    @State private var calibrationMessage: String? = nil
    @State private var calibrationMessageIsError: Bool = false
    @State private var showCalibrationConfirm: Bool = false
    @State private var pendingCalibrationRatio: CGFloat? = nil
    @State private var pendingCurrentCm: Double = 0
    @State private var pendingRealCm: Double = 0
    
    init(surface: Binding<FloorPlanSurface?>,
         selectedType: Binding<DetailsType?>,
         floorPlanViewModel: FloorPlanViewModel) {
        _surface = surface
        _selectedType = selectedType
        self.floorPlanViewModel = floorPlanViewModel
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 20) {
                    headerView
                    
                    ScrollView(.horizontal) {
                        HStack(spacing: 20) {
                            ForEach(DetailsType.allCases, id: \.self) { type in
                                createSliderButton(for: type)
                            }
                        }
                    }
                }
                .padding(20)
            }
            
            ScrollView(.vertical) {
                if let selectedType {
                    createDetailsContent(for: selectedType)
                }
            }
            
            Spacer()
        }
        .background(Color.teal)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .alert("確認校準整張平面圖？", isPresented: $showCalibrationConfirm) {
            Button("取消", role: .cancel) {
                pendingCalibrationRatio = nil
                calibrationMessage = "已取消套用比例校準。"
                calibrationMessageIsError = false
            }
            Button("確認校準") {
                if let ratio = pendingCalibrationRatio {
                    applyGlobalCalibration(ratio: ratio)
                    calibrationMessage = String(format: "已套用全圖比例校準（%.2fx，實測 %.1f cm / 掃描 %.1f cm）。", ratio, pendingRealCm, pendingCurrentCm)
                    calibrationMessageIsError = false
                }
                pendingCalibrationRatio = nil
            }
        } message: {
            Text(String(format: "掃描長度：%.1f cm\n實測長度：%.1f cm\n縮放比例：%.2fx\n\n比例差異介於 5%%～20%% 之間，確定要以此牆校準整張平面圖嗎？", pendingCurrentCm, pendingRealCm, pendingCalibrationRatio ?? 1.0))
        }
        .onAppear {
            if let surface {
                let rotationInDegrees = surface.zRotation * (180 / .pi)
                let snappedAngle = round(rotationInDegrees / 15) * 15
                angle = snappedAngle.truncatingRemainder(dividingBy: 360)
                width = surface.halfLength * 2
                depth = surface.selectedShape?.lineWidth ?? 0
                position = surface.position
                zPosition = surface.zPosition
                selectedDirection = surface.openDirection
                // 預設帶入目前 LiDAR 掃描出的公分數 (scalingFactor = 200 代表 1公尺 = 200pt -> 1cm = 2pt)
                let currentCm = (surface.halfLength * 2 / DrawParameters.scalingFactor) * 100.0
                realLengthCmText = String(format: "%.1f", currentCm)
            }
        }
    }
}

private extension SurfaceDetailsView {
    var headerView: some View {
        HStack {
            if let surface {
                Text(getSurfaceName(for: surface.capturedSurface.category))
                    .font(.largeTitle)
                    .foregroundStyle(.white)
            }
            Spacer()
            Button {
                withAnimation {
                    selectedType = nil
                    surface?.deselect()
                    surface = nil
                }
            } label: {
                Image(systemName: "xmark.square.fill")
                    .resizable()
                    .frame(width: 40, height: 40)
                    .foregroundStyle(.white)
            }
        }
    }
    
    func getSurfaceName(for type: CapturedRoom.Surface.Category) -> String {
        switch type {
        case .door: "門"
        case .wall: "牆面"
        case .opening: "開口/通道"
        case .window: "窗戶"
        case .floor: "地板"
        @unknown default: "未知結構"
        }
    }
    
    @ViewBuilder
    func createSliderButton(for type: DetailsType) -> some View {
        if let surface {
            switch type {
            case .measurements:
                switch surface.capturedSurface.category {
                case .wall, .window, .door:
                    Button { withAnimation { selectedType = type } } label: {
                        VStack {
                            Image(systemName: type.buttonImageName).resizable().frame(width: 40, height: 40).foregroundStyle(.white)
                            Text(type.description).foregroundStyle(.white)
                        }
                    }
                default:
                    EmptyView()
                }
            case .doorDirection:
                switch surface.capturedSurface.category {
                case .window, .door:
                    Button { withAnimation { selectedType = type } } label: {
                        VStack {
                            Image(systemName: type.buttonImageName).resizable().frame(width: 40, height: 40).foregroundStyle(.white)
                            Text(type.description).foregroundStyle(.white)
                        }
                    }
                default:
                    EmptyView()
                }
            case .delete:
                Button {
                    withAnimation {
                        surface.removeFromParent(); NotificationCenter.default.post(name: .floorPlanModelDidMutate, object: "delete_surface")
                        selectedType = nil
                        surface.deselect()
                        self.surface = nil
                    }
                } label: {
                    VStack {
                        Image(systemName: type.buttonImageName).resizable().frame(width: 40, height: 40).foregroundStyle(.white)
                        Text(type.description).foregroundStyle(.white)
                    }
                }
            case .rotate:
                Button {
                    withAnimation {
                        let incrementedAngle = angle + 15
                        let snappedAngle = round(incrementedAngle / 15) * 15
                        let normalizedAngle = snappedAngle.truncatingRemainder(dividingBy: 360)
                        surface.updateAngleRadians(to: normalizedAngle)
                        angle = normalizedAngle
                    }
                } label: {
                    VStack {
                        Image(systemName: type.buttonImageName).resizable().frame(width: 40, height: 40).foregroundStyle(.white)
                        Text(type.description).foregroundStyle(.white)
                    }
                }
            }
        }
    }
    
    func createDetailsContent(for type: DetailsType) -> some View {
        VStack(spacing: 14) {
            switch type {
            case .measurements:
                // 使用此牆作為全圖比例校準基準
                VStack(alignment: .leading, spacing: 8) {
                    Text("使用此牆作為全圖比例校準基準")
                        .font(.headline)
                        .foregroundStyle(.white)
                    HStack {
                        TextField("實測公分 (cm)", text: $realLengthCmText)
                            .keyboardType(.decimalPad)
                            .padding(10)
                            .background(Color.white)
                            .cornerRadius(10)
                        
                        Button {
                            handleCalibrationTap()
                        } label: {
                            Text("校準整張平面圖")
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.orange)
                                .cornerRadius(10)
                        }
                    }
                    if let calibrationMessage {
                        Text(calibrationMessage)
                            .font(.caption)
                            .foregroundStyle(calibrationMessageIsError ? Color.yellow : Color.white)
                    }
                }
                .padding(.horizontal, 20)
                
                Divider().background(Color.white.opacity(0.5)).padding(.horizontal, 20)
                
                AdjustMesurementView(
                    sliderBinding: Binding(
                        get: { surface?.zRotation ?? 0 },
                        set: { newValue in surface?.updateAngle(to: newValue); angle = newValue }),
                    sliderType: .angle(angle),
                    newPosition: .constant(""))
                
                AdjustMesurementView(
                    sliderBinding: Binding(
                        get: { (surface?.halfLength ?? 0) * 2 },
                        set: { newValue in surface?.updateWidth(to: newValue / 2); width = newValue }),
                    sliderType: .width(width),
                    newPosition: .constant(""))
                
                AdjustMesurementView(
                    sliderBinding: Binding(
                        get: { surface?.selectedShape?.lineWidth ?? 0 },
                        set: { newValue in surface?.updateDepth(to: newValue); depth = newValue }),
                    sliderType: .depth(depth),
                    newPosition: .constant(""))
                
            case .doorDirection:
                HStack {
                    Text("開門方向：").font(.body).foregroundStyle(.white)
                    Spacer()
                    Picker("開門方向", selection: Binding(
                        get: { selectedDirection },
                        set: { newValue in surface?.updateDoorOpenDirection(to: newValue); selectedDirection = newValue; NotificationCenter.default.post(name: .floorPlanModelDidMutate, object: "door_open_direction") }
                    )) {
                        ForEach(OpenDirection.allCases, id: \.self) { direction in
                            Text(direction.description).tag(direction)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 20)
            case .delete, .rotate:
                EmptyView()
            }
        }
    }

    func handleCalibrationTap() {
        guard let surface else {
            calibrationMessage = "請先選取一面牆作為校準基準。"
            calibrationMessageIsError = true
            return
        }
        let trimmed = realLengthCmText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let realCm = Double(trimmed),
              realCm.isFinite,
              realCm > 0,
              realCm <= 100000 else {
            calibrationMessage = "請輸入大於 0 且不超過 100,000 的有效實測公分數值（cm）。"
            calibrationMessageIsError = true
            return
        }
        let currentCm = Double(surface.halfLength * 2 / DrawParameters.scalingFactor) * 100.0
        guard currentCm.isFinite, currentCm > 0 else {
            calibrationMessage = "目前基準牆長度無效，無法計算縮放比例。"
            calibrationMessageIsError = true
            return
        }
        let ratioDouble = realCm / currentCm
        guard ratioDouble.isFinite, ratioDouble > 0 else {
            calibrationMessage = "縮放比例計算異常，請檢查輸入數值。"
            calibrationMessageIsError = true
            return
        }
        if ratioDouble < 0.8 || ratioDouble > 1.2 {
            calibrationMessage = String(format: "比例差異超過 ±20%%（換算比例 %.2fx），已阻擋套用。請確認單位是否為公分（cm）或改選其他基準牆。", ratioDouble)
            calibrationMessageIsError = true
            return
        }
        let ratio = CGFloat(ratioDouble)
        if ratioDouble >= 0.95 && ratioDouble <= 1.05 {
            applyGlobalCalibration(ratio: ratio)
            calibrationMessage = String(format: "已套用全圖比例校準（%.2fx，實測 %.1f cm / 掃描 %.1f cm）。", ratioDouble, realCm, currentCm)
            calibrationMessageIsError = false
        } else {
            pendingCurrentCm = currentCm
            pendingRealCm = realCm
            pendingCalibrationRatio = ratio
            showCalibrationConfirm = true
        }
    }

    func applyGlobalCalibration(ratio: CGFloat) {
        floorPlanViewModel.calibrationScaleRatio = ratio
        if let surface {
            width = (surface.halfLength * 2) * ratio
        }
        NotificationCenter.default.post(name: .floorPlanModelDidMutate, object: "global_calibration")
    }
}
