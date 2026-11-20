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

enum DisplayUnit: String, Codable, Equatable {
    case centimeter
    case millimeter
}

enum EditStateDateFormatter {
    static func makeFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
    
    static func string(from date: Date) -> String {
        makeFormatter().string(from: date)
    }
    
    static func nowString() -> String {
        string(from: Date())
    }
}

struct SavedCalibrationState: Codable, Equatable {
    let scaleFactor: Double
    let referenceOriginalMeters: Double
    let referenceMeasuredMeters: Double
    let calibratedAt: String
}

struct FloorPlanEditState: Codable {
    static let currentSchemaVersion: Int = 2
    
    static var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.3.0"
    }
    
    var schemaVersion: Int
    var appVersion: String
    var createdAt: String
    var modifiedAt: String
    var displayUnit: DisplayUnit
    var calibration: SavedCalibrationState?
    
    let surfaces: [String: SavedSurfaceState]
    let objects: [String: SavedObjectState]
    let cameraRotation: Double
    var manualObjects: [SavedManualObjectState]? = nil
    var annotations: [SavedAnnotationState]? = nil
    
    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case appVersion
        case createdAt
        case modifiedAt
        case displayUnit
        case calibration
        case surfaces
        case objects
        case cameraRotation
        case manualObjects
        case annotations
    }
    
    init(
        schemaVersion: Int = FloorPlanEditState.currentSchemaVersion,
        appVersion: String = FloorPlanEditState.currentAppVersion,
        createdAt: String? = nil,
        modifiedAt: String? = nil,
        displayUnit: DisplayUnit = .centimeter,
        calibration: SavedCalibrationState? = nil,
        surfaces: [String: SavedSurfaceState],
        objects: [String: SavedObjectState],
        cameraRotation: Double,
        manualObjects: [SavedManualObjectState]? = nil,
        annotations: [SavedAnnotationState]? = nil
    ) {
        let now = EditStateDateFormatter.nowString()
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.createdAt = (createdAt?.isEmpty == false) ? createdAt! : now
        self.modifiedAt = (modifiedAt?.isEmpty == false) ? modifiedAt! : now
        self.displayUnit = displayUnit
        self.calibration = calibration
        self.surfaces = surfaces
        self.objects = objects
        self.cameraRotation = cameraRotation
        self.manualObjects = manualObjects
        self.annotations = annotations
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? "0.2.0"
        self.createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        self.modifiedAt = try container.decodeIfPresent(String.self, forKey: .modifiedAt) ?? ""
        self.displayUnit = try container.decodeIfPresent(DisplayUnit.self, forKey: .displayUnit) ?? .centimeter
        self.calibration = try container.decodeIfPresent(SavedCalibrationState.self, forKey: .calibration)
        self.surfaces = try container.decodeIfPresent([String: SavedSurfaceState].self, forKey: .surfaces) ?? [:]
        self.objects = try container.decodeIfPresent([String: SavedObjectState].self, forKey: .objects) ?? [:]
        self.cameraRotation = try container.decodeIfPresent(Double.self, forKey: .cameraRotation) ?? 0.0
        self.manualObjects = try container.decodeIfPresent([SavedManualObjectState].self, forKey: .manualObjects)
        self.annotations = try container.decodeIfPresent([SavedAnnotationState].self, forKey: .annotations)
    }
    
    static func migrateIfNeeded(
        _ state: FloorPlanEditState,
        fallbackCreatedAt: Date? = nil,
        fallbackModifiedAt: Date? = nil
    ) -> FloorPlanEditState {
        var migrated = state
        if migrated.schemaVersion < currentSchemaVersion {
            if migrated.createdAt.isEmpty {
                migrated.createdAt = EditStateDateFormatter.string(from: fallbackCreatedAt ?? Date())
            }
            if migrated.modifiedAt.isEmpty {
                migrated.modifiedAt = EditStateDateFormatter.string(from: fallbackModifiedAt ?? fallbackCreatedAt ?? Date())
            }
            migrated.schemaVersion = currentSchemaVersion
        } else if migrated.createdAt.isEmpty {
            migrated.createdAt = EditStateDateFormatter.string(from: fallbackCreatedAt ?? Date())
        }
        return migrated
    }
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
    
    private func backupURL(for url: URL) -> URL {
        let name = url.lastPathComponent
        let bakName: String
        if name.hasSuffix(".json") {
            bakName = String(name.dropLast(5)) + ".bak.json"
        } else {
            bakName = name + ".bak.json"
        }
        return url.deletingLastPathComponent().appendingPathComponent(bakName)
    }
    
    private func safeWrite<T: Codable>(
        _ value: T,
        to destinationURL: URL,
        encoder: JSONEncoder,
        decoder: JSONDecoder = JSONDecoder()
    ) throws {
        let fm = FileManager.default
        let tmpURL = destinationURL.appendingPathExtension("tmp")
        let bakURL = backupURL(for: destinationURL)
        let bakTmpURL = bakURL.appendingPathExtension("tmp")
        
        defer {
            if fm.fileExists(atPath: tmpURL.path) {
                try? fm.removeItem(at: tmpURL)
            }
            if fm.fileExists(atPath: bakTmpURL.path) {
                try? fm.removeItem(at: bakTmpURL)
            }
        }
        
        // 1. 新資料寫入 .tmp
        let encodedData = try encoder.encode(value)
        try encodedData.write(to: tmpURL, options: .atomic)
        
        // 2. 確認 .tmp 可以重新解碼
        let verifyData = try Data(contentsOf: tmpURL)
        _ = try decoder.decode(T.self, from: verifyData)
        
        // 3. 驗證通過後，先將現有原檔複製成 .bak.json（僅保留上一版，原檔暫留至替換完成）
        if fm.fileExists(atPath: destinationURL.path) {
            if fm.fileExists(atPath: bakTmpURL.path) {
                try? fm.removeItem(at: bakTmpURL)
            }
            try fm.copyItem(at: destinationURL, to: bakTmpURL)
            if fm.fileExists(atPath: bakURL.path) {
                _ = try fm.replaceItemAt(bakURL, withItemAt: bakTmpURL)
            } else {
                try fm.moveItem(at: bakTmpURL, to: bakURL)
            }
        }
        
        // 4. 用 .tmp 原子替換正式檔（成功後 .tmp 已被移走）
        if fm.fileExists(atPath: destinationURL.path) {
            _ = try fm.replaceItemAt(destinationURL, withItemAt: tmpURL)
        } else {
            try fm.moveItem(at: tmpURL, to: destinationURL)
        }
    }
    
    private func loadWithBackupFallback<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        decoder: JSONDecoder = JSONDecoder()
    ) -> T? {
        if let data = try? Data(contentsOf: url),
           let decoded = try? decoder.decode(type, from: data) {
            return decoded
        }
        let bakURL = backupURL(for: url)
        if let bakData = try? Data(contentsOf: bakURL),
           let decoded = try? decoder.decode(type, from: bakData) {
            print("RoomProjectStore 主檔異常，已自動從備份復原: \(bakURL.lastPathComponent)")
            return decoded
        }
        return nil
    }
    
    func loadIndex() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = loadWithBackupFallback([SavedRoomProject].self, from: indexURL, decoder: decoder) {
            projects = decoded.sorted { $0.updatedAt > $1.updatedAt }
        } else {
            projects = []
        }
    }
    
    private func persistIndex() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            try safeWrite(projects, to: indexURL, encoder: encoder, decoder: decoder)
        } catch {
            print("RoomProjectStore 索引寫入失敗: \(error.localizedDescription)")
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
        
        let now = Date()
        let nowISO = EditStateDateFormatter.string(from: now)
        let existingProject = projects.first(where: { $0.id == id })
        var stateToSave = editState
        stateToSave.schemaVersion = FloorPlanEditState.currentSchemaVersion
        stateToSave.appVersion = FloorPlanEditState.currentAppVersion
        if stateToSave.createdAt.isEmpty {
            stateToSave.createdAt = existingProject.map { EditStateDateFormatter.string(from: $0.createdAt) } ?? nowISO
        }
        stateToSave.modifiedAt = nowISO
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let decoder = JSONDecoder()
        do {
            try safeWrite(capturedRoom, to: roomURL, encoder: encoder, decoder: decoder)
            try safeWrite(stateToSave, to: editURL, encoder: encoder, decoder: decoder)
        } catch {
            print("RoomProjectStore 存檔失敗: \(error.localizedDescription)")
            return nil
        }
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
        return loadWithBackupFallback(CapturedRoom.self, from: url)
    }
    
    func loadEditState(for project: SavedRoomProject) -> FloorPlanEditState? {
        let url = storageDirectory.appendingPathComponent(project.editStateFileName)
        guard let decoded = loadWithBackupFallback(FloorPlanEditState.self, from: url) else {
            return nil
        }
        
        if decoded.schemaVersion < FloorPlanEditState.currentSchemaVersion {
            let legacyBackupName = project.editStateFileName.replacingOccurrences(
                of: ".json",
                with: ".v\(decoded.schemaVersion).bak.json"
            )
            let legacyBackupURL = storageDirectory.appendingPathComponent(legacyBackupName)
            if FileManager.default.fileExists(atPath: url.path) &&
               !FileManager.default.fileExists(atPath: legacyBackupURL.path) {
                try? FileManager.default.copyItem(at: url, to: legacyBackupURL)
            }
            return FloorPlanEditState.migrateIfNeeded(
                decoded,
                fallbackCreatedAt: project.createdAt,
                fallbackModifiedAt: project.updatedAt
            )
        }
        return decoded
    }
    
    func deleteProject(_ project: SavedRoomProject) {
        let fm = FileManager.default
        let roomURL = storageDirectory.appendingPathComponent(project.roomFileName)
        let editURL = storageDirectory.appendingPathComponent(project.editStateFileName)
        let legacyEditURL = storageDirectory.appendingPathComponent(
            project.editStateFileName.replacingOccurrences(of: ".json", with: ".v1.bak.json")
        )
        for target in [roomURL, backupURL(for: roomURL), editURL, backupURL(for: editURL), legacyEditURL] {
            try? fm.removeItem(at: target)
        }
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
    var editStateCreatedAt: String? = nil
    var displayUnit: DisplayUnit = .centimeter
    var calibrationState: SavedCalibrationState? = nil
    
    // Commit 3 (v0.3.0-beta.1)：未存檔狀態管理
    @Published var isDirty: Bool = false
    @Published var shouldDismissAfterSave: Bool = false
    @Published var didCompleteSaveForDismiss: Bool = false
    
    func markDirty(reason: String) {
        DispatchQueue.main.async {
            if !self.isDirty {
                self.isDirty = true
            }
            print("[DirtyState] marked dirty: \(reason)")
        }
    }
    
    // Commit 5 (v0.3.0)：牆體鎖定（操作偏好，不納入幾何資料）
    @Published var isWallLocked: Bool = false
    
    func setWallLocked(_ locked: Bool) {
        let applyUpdate = {
            if self.isWallLocked == locked { return }
            self.isWallLocked = locked
            if let pid = self.savedProjectID {
                UserDefaults.standard.set(locked, forKey: "wall_locked_\(pid.uuidString)")
            }
        }
        if Thread.isMainThread {
            applyUpdate()
        } else {
            DispatchQueue.main.async(execute: applyUpdate)
        }
    }
    
    func loadWallLockPreference(for projectID: UUID?) {
        guard let pid = projectID else { return }
        let key = "wall_locked_\(pid.uuidString)"
        let applyLoad = {
            if UserDefaults.standard.object(forKey: key) != nil {
                self.isWallLocked = UserDefaults.standard.bool(forKey: key)
            } else {
                self.isWallLocked = false
            }
        }
        if Thread.isMainThread {
            applyLoad()
        } else {
            DispatchQueue.main.async(execute: applyLoad)
        }
    }
    
    func clearDirty() {
        DispatchQueue.main.async {
            self.isDirty = false
        }
    }
}

extension Notification.Name {
    static let floorPlanModelDidMutate = Notification.Name("floorPlanModelDidMutate")
}