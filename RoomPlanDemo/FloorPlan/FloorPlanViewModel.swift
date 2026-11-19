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
    
    // 正交直角對齊與基準尺全域校準控制
    @Published var shouldOrthogonalize: Bool = false
    @Published var calibrationScaleRatio: CGFloat? = nil
    @Published var statusToastMessage: String? = nil
}