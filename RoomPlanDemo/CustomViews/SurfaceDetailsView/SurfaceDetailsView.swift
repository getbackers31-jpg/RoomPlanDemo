import RoomPlan
import SwiftUI

struct SurfaceDetailsView: View {
    @Binding var surface: FloorPlanSurface?
    @Binding var selectedType: DetailsType?
    @ObservedObject var floorPlanViewModel: FloorPlanViewModel

    @State private var angle: CGFloat = 0
    @State private var width: CGFloat = 0
    @State private var depth: CGFloat = 0.1
    @State private var position: CGPoint = .zero
    @State private var zPosition: CGFloat = 0
    @State private var selectedDirection: OpenDirection = .clockwise
    @State private var realLengthCmText = ""
    @State private var calibrationMessage: String?
    @State private var calibrationMessageIsError = false
    @State private var showCalibrationConfirm = false
    @State private var pendingCalibrationRatio: CGFloat?
    @State private var pendingCurrentCm: Double = 0
    @State private var pendingRealCm: Double = 0

    init(
        surface: Binding<FloorPlanSurface?>,
        selectedType: Binding<DetailsType?>,
        floorPlanViewModel: FloorPlanViewModel
    ) {
        _surface = surface
        _selectedType = selectedType
        self.floorPlanViewModel = floorPlanViewModel
    }

    private var protectsSelectedSurface: Bool {
        guard let surface else { return false }
        return floorPlanViewModel.isWallLocked && surface.isProtectedByWallLock
    }

    private var blocksDoorConversion: Bool {
        guard let surface else { return false }
        return floorPlanViewModel.isWallLocked &&
            surface.capturedSurface.category == .door
    }

    private var blocksStructuralEditing: Bool {
        protectsSelectedSurface || blocksDoorConversion
    }

    var body: some View {
        VStack(spacing: 14) {
            headerView
            HStack(spacing: 24) {
                createSliderButton(for: .measurements)
                createSliderButton(for: .doorDirection)
                createSliderButton(for: .rotate)
                createSliderButton(for: .delete)
            }
            .padding(.horizontal, 20)

            if floorPlanViewModel.isWallLocked {
                Text("牆體已鎖定，請先解鎖再修改牆體或執行全域校準。")
                    .font(.caption)
                    .foregroundStyle(Color.yellow)
                    .padding(.horizontal, 20)
            }

            ScrollView(.vertical) {
                if let selectedType {
                    createDetailsContent(for: selectedType)
                }
            }
            Spacer(minLength: 0)
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
                    applyGlobalCalibration(
                        ratio: ratio,
                        referenceOriginalMeters: pendingCurrentCm / 100,
                        referenceMeasuredMeters: pendingRealCm / 100
                    )
                    calibrationMessage = String(
                        format: "已套用全圖比例校準（%.2fx，實測 %.1f cm / 掃描 %.1f cm）。",
                        ratio,
                        pendingRealCm,
                        pendingCurrentCm
                    )
                    calibrationMessageIsError = false
                }
                pendingCalibrationRatio = nil
            }
        } message: {
            Text(
                String(
                    format: "掃描長度：%.1f cm\n實測長度：%.1f cm\n縮放比例：%.2fx\n\n比例差異介於 5%%～20%% 之間，確定要以此牆校準整張平面圖嗎？",
                    pendingCurrentCm,
                    pendingRealCm,
                    pendingCalibrationRatio ?? 1
                )
            )
        }
        .onAppear(perform: loadSelection)
        .onChange(of: surface?.capturedSurface.identifier) { _, _ in
            loadSelection()
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
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    func loadSelection() {
        guard let surface else { return }
        angle = normalizedRadians(surface.zRotation)
        width = surface.halfLength * 2
        depth = surface.thicknessMeters
        position = surface.position
        zPosition = surface.zPosition
        selectedDirection = surface.openDirection
        let currentCm = width / DrawParameters.scalingFactor * 100
        realLengthCmText = String(format: "%.1f", currentCm)
    }

    func getSurfaceName(for type: CapturedRoom.Surface.Category) -> String {
        switch type {
        case .door: return "門"
        case .wall: return "牆面"
        case .opening: return "開口/通道"
        case .window: return "窗戶"
        case .floor: return "地板"
        @unknown default: return "未知結構"
        }
    }

    func normalizedRadians(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        var result = value.truncatingRemainder(dividingBy: 2 * .pi)
        if result > .pi { result -= 2 * .pi }
        if result < -.pi { result += 2 * .pi }
        return result
    }

    @ViewBuilder
    func toolLabel(for type: DetailsType) -> some View {
        VStack {
            Image(systemName: type.buttonImageName)
                .resizable()
                .frame(width: 40, height: 40)
                .foregroundStyle(.white)
            Text(type.description)
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    func createSliderButton(for type: DetailsType) -> some View {
        if let surface {
            switch type {
            case .measurements:
                switch surface.capturedSurface.category {
                case .wall, .window, .door:
                    Button {
                        withAnimation { selectedType = type }
                    } label: {
                        toolLabel(for: type)
                    }
                    .disabled(protectsSelectedSurface)
                default:
                    EmptyView()
                }
            case .doorDirection:
                switch surface.capturedSurface.category {
                case .window, .door:
                    Button {
                        withAnimation { selectedType = type }
                    } label: {
                        toolLabel(for: type)
                    }
                    .disabled(protectsSelectedSurface)
                default:
                    EmptyView()
                }
            case .delete:
                Button {
                    guard let scene = surface.scene as? FloorPlanScene else { return }
                    withAnimation {
                        scene.deleteSurface(surface)
                        if self.surface == nil {
                            selectedType = nil
                        }
                    }
                } label: {
                    toolLabel(for: type)
                }
                .disabled(blocksStructuralEditing)
            case .rotate:
                Button {
                    guard !protectsSelectedSurface else { return }
                    let next = normalizedRadians(angle + .pi / 12)
                    (surface.scene as? FloorPlanScene)?.recordUndoState()
                    surface.updateAngleRadians(to: next)
                    angle = next
                } label: {
                    toolLabel(for: type)
                }
                .disabled(protectsSelectedSurface)
            }
        }
    }

    @ViewBuilder
    func createDetailsContent(for type: DetailsType) -> some View {
        VStack(spacing: 14) {
            switch type {
            case .measurements:
                measurementContent
            case .doorDirection:
                doorDirectionContent
            case .delete, .rotate:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    var measurementContent: some View {
        if let selectedSurface = surface {
            if selectedSurface.capturedSurface.category == .window {
                Toggle(
                    "落地玻璃",
                    isOn: Binding(
                        get: { selectedSurface.isFloorToCeilingGlass },
                        set: { selectedSurface.setFloorToCeilingGlass($0) }
                    )
                )
                .tint(AppTheme.accentBlue)
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .disabled(protectsSelectedSurface)
            }

            if selectedSurface.isOversizedDoor {
                VStack(alignment: .leading, spacing: 8) {
                    Text("寬門扇改以大開口呈現，避免過大的開啟弧線")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    HStack {
                        Button("大開口") {
                            selectedSurface.setRepresentation(.wideOpening)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)
                        Button("實體牆") {
                            selectedSurface.setRepresentation(.solidWall)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                    .disabled(blocksStructuralEditing)
                }
                .padding(.horizontal, 20)
            }

            if selectedSurface.capturedSurface.category == .wall {
                VStack(alignment: .leading, spacing: 8) {
                    Text("2D 樑柱標記")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    HStack {
                        Button("樑") { selectedSurface.setRepresentation(.beam) }
                        Button("柱") { selectedSurface.setRepresentation(.column) }
                        Button("恢復牆面") { selectedSurface.setRepresentation(.source) }
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .disabled(protectsSelectedSurface)
                }
                .padding(.horizontal, 20)
            }

            calibrationContent

            Divider()
                .background(Color.white.opacity(0.5))
                .padding(.horizontal, 20)

            ContinuousMeasurementSlider(
                value: Binding(
                    get: { normalizedRadians(surface?.zRotation ?? angle) },
                    set: { newValue in
                        let normalized = normalizedRadians(newValue)
                        surface?.updateAngleRadians(to: normalized)
                        angle = normalized
                    }
                ),
                type: .angle(angle),
                isDisabled: protectsSelectedSurface,
                onEditingChanged: continuousEditingChanged
            )

            ContinuousMeasurementSlider(
                value: Binding(
                    get: { (surface?.halfLength ?? width / 2) * 2 },
                    set: { newValue in
                        surface?.updateWidth(to: newValue / 2)
                        width = newValue
                    }
                ),
                type: .width(width),
                isDisabled: protectsSelectedSurface,
                onEditingChanged: continuousEditingChanged
            )

            if selectedSurface.effectiveRepresentation != .beam,
               selectedSurface.effectiveRepresentation != .column {
                ContinuousMeasurementSlider(
                    value: Binding(
                        get: { selectedSurface.thicknessMeters },
                        set: { newValue in
                            selectedSurface.updateThicknessMeters(to: newValue)
                            depth = newValue
                        }
                    ),
                    type: .depth(depth),
                    isDisabled: protectsSelectedSurface,
                    onEditingChanged: continuousEditingChanged
                )
            }
        }
    }

    var calibrationContent: some View {
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
                    .disabled(floorPlanViewModel.isWallLocked)
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
                .disabled(floorPlanViewModel.isWallLocked)
            }
            if let calibrationMessage {
                Text(calibrationMessage)
                    .font(.caption)
                    .foregroundStyle(calibrationMessageIsError ? Color.yellow : Color.white)
            }
        }
        .padding(.horizontal, 20)
    }

    var doorDirectionContent: some View {
        HStack {
            Text("開門方向：")
                .font(.body)
                .foregroundStyle(.white)
            Spacer()
            Picker(
                "開門方向",
                selection: Binding(
                    get: { selectedDirection },
                    set: { newValue in
                        surface?.updateDoorOpenDirection(to: newValue)
                        selectedDirection = newValue
                    }
                )
            ) {
                ForEach(OpenDirection.allCases, id: \.self) { direction in
                    Text(direction.description).tag(direction)
                }
            }
            .pickerStyle(.segmented)
            .disabled(protectsSelectedSurface)
        }
        .padding(.horizontal, 20)
    }

    func continuousEditingChanged(_ isEditing: Bool) {
        guard let scene = surface?.scene as? FloorPlanScene else { return }
        if isEditing {
            scene.beginContinuousEdit()
        } else {
            scene.endContinuousEdit()
        }
    }

    func handleCalibrationTap() {
        guard !floorPlanViewModel.isWallLocked else {
            calibrationMessage = "牆體已鎖定，請先解鎖再執行全域校準。"
            calibrationMessageIsError = true
            return
        }
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
        let currentCm = Double(
            surface.halfLength * 2 / DrawParameters.scalingFactor
        ) * 100
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
            calibrationMessage = String(
                format: "比例差異超過 ±20%%（換算比例 %.2fx），已阻擋套用。請確認單位是否為公分（cm）或改選其他基準牆。",
                ratioDouble
            )
            calibrationMessageIsError = true
            return
        }
        let ratio = CGFloat(ratioDouble)
        if ratioDouble >= 0.95 && ratioDouble <= 1.05 {
            applyGlobalCalibration(
                ratio: ratio,
                referenceOriginalMeters: currentCm / 100,
                referenceMeasuredMeters: realCm / 100
            )
            calibrationMessage = String(
                format: "已套用全圖比例校準（%.2fx，實測 %.1f cm / 掃描 %.1f cm）。",
                ratioDouble,
                realCm,
                currentCm
            )
            calibrationMessageIsError = false
        } else {
            pendingCurrentCm = currentCm
            pendingRealCm = realCm
            pendingCalibrationRatio = ratio
            showCalibrationConfirm = true
        }
    }

    func applyGlobalCalibration(
        ratio: CGFloat,
        referenceOriginalMeters: Double,
        referenceMeasuredMeters: Double
    ) {
        floorPlanViewModel.calibrationRequest = FloorPlanCalibrationRequest(
            ratio: ratio,
            referenceOriginalMeters: referenceOriginalMeters,
            referenceMeasuredMeters: referenceMeasuredMeters
        )
        if let surface {
            width = surface.halfLength * 2 * ratio
            depth = surface.thicknessMeters * ratio
        }
    }
}

private struct ContinuousMeasurementSlider: View {
    @Binding var value: CGFloat
    let type: SliderMesurementType
    let isDisabled: Bool
    let onEditingChanged: (Bool) -> Void

    private var displayText: String {
        switch type {
        case .angle:
            return SliderMesurementType.angle(value).convertedText
        case .width:
            return SliderMesurementType.width(value).convertedText
        case .depth:
            return SliderMesurementType.depth(value).convertedText
        case .position:
            return SliderMesurementType.position(value).convertedText
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(type.description)
                    .foregroundStyle(.white)
                Spacer()
                Text(displayText)
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            Slider(
                value: $value,
                in: type.closedRange,
                onEditingChanged: onEditingChanged
            )
            .tint(.white)
            .disabled(isDisabled)
        }
        .padding(.horizontal, 20)
    }
}
