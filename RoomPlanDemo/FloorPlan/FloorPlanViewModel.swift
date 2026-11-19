import Foundation
import RoomPlan

final class FloorPlanViewModel: ObservableObject {
    @Published var selectedSurface: FloorPlanSurface? = nil
    @Published var selectedObject: FloorPlanObject? = nil
    @Published var selectedAnnotation: FloorPlanAnnotation?
    @Published var selectedType: DetailsType?
    @Published var roomOptionType: RoomOptionType?
    @Published var furnitureToAdd: CapturedRoom.Object.Category?
    @Published var shouldAddFurniture: Bool = false
    @Published var shouldAddText: Bool = false
    @Published var shouldShareImage: Bool = false
    @Published var shareFormat: ImageFormat? = nil
    
    // 正交直角對齊與基準尺全域校準
    @Published var shouldOrthogonalize: Bool = false
    @Published var calibrationScaleRatio: CGFloat? = nil
    @Published var statusToastMessage: String? = nil
    
    // 第一階段：面積坪數、空間用途、藍圖圖層開關與修圖輔助
    @Published var roomAreaSqm: Double = 0.0
    @Published var roomAreaPing: Double = 0.0
    @Published var roomUsage: String = "室內空間"
    
    @Published var showFurniture: Bool = true
    @Published var showDimensions: Bool = true
    @Published var showFurnitureLabels: Bool = true
    
    @Published var shouldRotate90: Bool = false
    @Published var shouldRecenter: Bool = false
    @Published var shouldUndo: Bool = false
    @Published var shouldRedo: Bool = false
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false
}