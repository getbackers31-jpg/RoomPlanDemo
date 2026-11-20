import Foundation
import RoomPlan

// MARK: - 第二階段：本機空間紀錄庫資料模型與存檔管理器

struct SavedSurfaceState: Codable {
    let x: Double
    let y: Double
    let zRotation: Double
    let halfLength: Double
}

struct SavedObjectState: Codable {
    let x: Double
    let y: Double
    let zRotation: Double
    let xScale: Double
    let yScale: Double
}

struct SavedManualObjectState: Codable {
    let categoryData: Data
    let x: Double
    let y: Double
    let zRotation: Double
    let xScale: Double
    let yScale: Double
}

struct SavedAnnotationState: Codable {
    let title: String
    let subtitle: String
    let x: Double
    let y: Double
    let zRotation: Double
    let fontSize: Double
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

struct FloorPlanEditState: Codable {
    let surfaces: [String: SavedSurfaceState]
    let objects: [String: SavedObjectState]
    let cameraRotation: Double
    var manualObjects: [SavedManualObjectState]? = nil
    var annotations: [SavedAnnotationState]? = nil
}

struct SavedRoomProject: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var floorLabel: String
    var areaPing: Double
    var areaSqm: Double
    var createdAt: Date
    var updatedAt: Date
    var roomFileName: String
    var editStateFileName: String
}

final class RoomProjectStore: ObservableObject {
    static let shared = RoomProjectStore()
    
    @Published private(set) var projects: [SavedRoomProject] = []
    
    private let indexFileName = "saved_room_projects_index.json"
    private let folderName = "SavedRoomProjects"
    
    private var storageDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private var indexURL: URL {
        storageDirectory.appendingPathComponent(indexFileName)
    }
    
    init() {
        loadIndex()
    }
    
    func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL) else {
            projects = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([SavedRoomProject].self, from: data) {
            projects = decoded.sorted { $0.updatedAt > $1.updatedAt }
        }
    }
    
    private func persistIndex() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(projects) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }
    
    @discardableResult
    func saveProject(
        existingID: UUID?,
        name: String,
        floorLabel: String,
        areaPing: Double,
        areaSqm: Double,
        capturedRoom: CapturedRoom,
        editState: FloorPlanEditState
    ) -> SavedRoomProject? {
        let id = existingID ?? UUID()
        let roomFile = "room_\(id.uuidString).json"
        let editFile = "edit_\(id.uuidString).json"
        let roomURL = storageDirectory.appendingPathComponent(roomFile)
        let editURL = storageDirectory.appendingPathComponent(editFile)
        
        let encoder = JSONEncoder()
        do {
            let roomData = try encoder.encode(capturedRoom)
            try roomData.write(to: roomURL, options: .atomic)
            
            let editData = try encoder.encode(editState)
            try editData.write(to: editURL, options: .atomic)
        } catch {
            print("RoomProjectStore 存檔失敗: \(error.localizedDescription)")
            return nil
        }
        
        let now = Date()
        let project: SavedRoomProject
        if let idx = projects.firstIndex(where: { $0.id == id }) {
            var updated = projects[idx]
            updated.name = name
            updated.floorLabel = floorLabel
            updated.areaPing = areaPing
            updated.areaSqm = areaSqm
            updated.updatedAt = now
            projects[idx] = updated
            project = updated
        } else {
            project = SavedRoomProject(
                id: id,
                name: name,
                floorLabel: floorLabel,
                areaPing: areaPing,
                areaSqm: areaSqm,
                createdAt: now,
                updatedAt: now,
                roomFileName: roomFile,
                editStateFileName: editFile
            )
            projects.insert(project, at: 0)
        }
        
        projects.sort { $0.updatedAt > $1.updatedAt }
        persistIndex()
        return project
    }
    
    func loadCapturedRoom(for project: SavedRoomProject) -> CapturedRoom? {
        let url = storageDirectory.appendingPathComponent(project.roomFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CapturedRoom.self, from: data)
    }
    
    func loadEditState(for project: SavedRoomProject) -> FloorPlanEditState? {
        let url = storageDirectory.appendingPathComponent(project.editStateFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FloorPlanEditState.self, from: data)
    }
    
    func deleteProject(_ project: SavedRoomProject) {
        let roomURL = storageDirectory.appendingPathComponent(project.roomFileName)
        let editURL = storageDirectory.appendingPathComponent(project.editStateFileName)
        try? FileManager.default.removeItem(at: roomURL)
        try? FileManager.default.removeItem(at: editURL)
        projects.removeAll { $0.id == project.id }
        persistIndex()
    }
}

// MARK: - 2D 平面圖 ViewModel

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
    @Published var floorLabel: String = "1F"
    
    @Published var showFurniture: Bool = true
    @Published var showDimensions: Bool = true
    @Published var showFurnitureLabels: Bool = true
    
    @Published var shouldRotate90: Bool = false
    @Published var shouldRecenter: Bool = false
    @Published var shouldUndo: Bool = false
    @Published var shouldRedo: Bool = false
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false
    
    // 第二階段：專案儲存與讀取狀態
    @Published var savedProjectID: UUID? = nil
    @Published var shouldSaveProject: Bool = false
    @Published var autoOrthogonalizeOnLoad: Bool = false
    var initialEditState: FloorPlanEditState? = nil
}