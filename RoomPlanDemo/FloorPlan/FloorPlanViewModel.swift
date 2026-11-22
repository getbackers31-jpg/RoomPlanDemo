import Foundation
import Combine
import CoreGraphics
import CryptoKit
import RoomPlan

// MARK: - 第二階段：本機空間紀錄庫資料模型與存檔管理器

enum FloorPlanCoordinateConvention: String, Codable, Equatable {
    case legacyEulerXZ
    case basisXZ
}

enum FloorPlanBoundaryStatus: String, Codable, Equatable {
    case empty
    case closed
    case open
    case selfIntersecting
    case ambiguous
}

struct FloorPlanBoundaryResult: Equatable {
    let status: FloorPlanBoundaryStatus
    let areaSquareMeters: Double?

    init(
        status: FloorPlanBoundaryStatus,
        areaSquareMeters: Double? = nil
    ) {
        if status == .closed,
           let areaSquareMeters,
           areaSquareMeters.isFinite,
           areaSquareMeters > 0 {
            self.status = .closed
            self.areaSquareMeters = areaSquareMeters
        } else {
            self.status = status == .closed ? .ambiguous : status
            self.areaSquareMeters = nil
        }
    }
}

enum FloorPlanPersistenceError: LocalizedError {
    case unsupportedSchema(Int)
    case invalidState(String)
    case invalidFileName
    case unavailableDocumentsDirectory
    case indexUnavailable
    case mainThreadRequired

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "此存檔使用較新的資料格式（版本 \(version)），目前版本無法安全開啟或覆寫。"
        case .invalidState(let detail):
            return "空間資料驗證失敗：\(detail)"
        case .invalidFileName:
            return "存檔檔名無效，已停止讀寫。"
        case .unavailableDocumentsDirectory:
            return "無法取得本機文件資料夾。"
        case .indexUnavailable:
            return "空間紀錄庫索引及備份無法讀取，已停止寫入以保護既有資料。"
        case .mainThreadRequired:
            return "此資料操作必須由主執行緒執行。"
        }
    }
}

struct SavedSurfaceState: Codable, Equatable {
    let x: Double
    let y: Double
    let zRotation: Double
    let halfLength: Double
    var representation: FloorPlanSurfaceRepresentation? = nil
    var isFloorToCeilingGlass: Bool? = nil
    var openDirection: OpenDirection? = nil
    var strokeWidth: Double? = nil
    var thicknessMeters: Double? = nil
}

struct SavedObjectState: Codable, Equatable {
    let x: Double
    let y: Double
    let zRotation: Double
    let xScale: Double
    let yScale: Double
}

struct SavedManualObjectState: Codable, Equatable {
    let categoryData: Data
    let x: Double
    let y: Double
    let zRotation: Double
    let xScale: Double
    let yScale: Double
    var id: UUID? = nil
}

struct SavedAnnotationState: Codable, Equatable {
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
    var id: UUID? = nil
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

struct FloorPlanCalibrationRequest: Equatable {
    let ratio: CGFloat
    let referenceOriginalMeters: Double
    let referenceMeasuredMeters: Double
    let id: UUID

    init(
        ratio: CGFloat,
        referenceOriginalMeters: Double,
        referenceMeasuredMeters: Double,
        id: UUID = UUID()
    ) {
        self.ratio = ratio
        self.referenceOriginalMeters = referenceOriginalMeters
        self.referenceMeasuredMeters = referenceMeasuredMeters
        self.id = id
    }
}

struct FloorPlanEditState: Codable, Equatable {
    static let currentSchemaVersion: Int = 4

    static var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"]
            as? String ?? "0.3.0"
    }

    var schemaVersion: Int
    var appVersion: String
    var createdAt: String
    var modifiedAt: String
    var displayUnit: DisplayUnit
    var calibration: SavedCalibrationState?

    var surfaces: [String: SavedSurfaceState]
    var objects: [String: SavedObjectState]
    var cameraRotation: Double
    var manualObjects: [SavedManualObjectState]?
    var annotations: [SavedAnnotationState]?

    var coordinateConvention: FloorPlanCoordinateConvention
    var deletedSurfaceIDs: Set<String>
    var deletedObjectIDs: Set<String>
    var boundaryStatus: FloorPlanBoundaryStatus?

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
        case coordinateConvention
        case deletedSurfaceIDs
        case deletedObjectIDs
        case boundaryStatus
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
        annotations: [SavedAnnotationState]? = nil,
        coordinateConvention: FloorPlanCoordinateConvention = .basisXZ,
        deletedSurfaceIDs: Set<String> = [],
        deletedObjectIDs: Set<String> = [],
        boundaryStatus: FloorPlanBoundaryStatus? = nil
    ) {
        let now = EditStateDateFormatter.nowString()

        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.createdAt = createdAt.flatMap { $0.isEmpty ? nil : $0 } ?? now
        self.modifiedAt = modifiedAt.flatMap { $0.isEmpty ? nil : $0 } ?? now
        self.displayUnit = displayUnit
        self.calibration = calibration
        self.surfaces = surfaces
        self.objects = objects
        self.cameraRotation = cameraRotation
        self.manualObjects = manualObjects
        self.annotations = annotations
        self.coordinateConvention = coordinateConvention
        self.deletedSurfaceIDs = deletedSurfaceIDs
        self.deletedObjectIDs = deletedObjectIDs
        self.boundaryStatus = boundaryStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let version = try container.decodeIfPresent(
            Int.self,
            forKey: .schemaVersion
        ) ?? 1

        guard version <= Self.currentSchemaVersion else {
            throw FloorPlanPersistenceError.unsupportedSchema(version)
        }

        guard version >= 1 else {
            throw FloorPlanPersistenceError.invalidState(
                "schemaVersion 必須大於或等於 1。"
            )
        }

        schemaVersion = version

        appVersion = try container.decodeIfPresent(
            String.self,
            forKey: .appVersion
        ) ?? "0.2.0"

        createdAt = try container.decodeIfPresent(
            String.self,
            forKey: .createdAt
        ) ?? ""

        modifiedAt = try container.decodeIfPresent(
            String.self,
            forKey: .modifiedAt
        ) ?? ""

        displayUnit = try container.decodeIfPresent(
            DisplayUnit.self,
            forKey: .displayUnit
        ) ?? .centimeter

        calibration = try container.decodeIfPresent(
            SavedCalibrationState.self,
            forKey: .calibration
        )

        surfaces = try container.decodeIfPresent(
            [String: SavedSurfaceState].self,
            forKey: .surfaces
        ) ?? [:]

        objects = try container.decodeIfPresent(
            [String: SavedObjectState].self,
            forKey: .objects
        ) ?? [:]

        cameraRotation = try container.decodeIfPresent(
            Double.self,
            forKey: .cameraRotation
        ) ?? 0

        manualObjects = try container.decodeIfPresent(
            [SavedManualObjectState].self,
            forKey: .manualObjects
        )

        annotations = try container.decodeIfPresent(
            [SavedAnnotationState].self,
            forKey: .annotations
        )

        coordinateConvention = try container.decodeIfPresent(
            FloorPlanCoordinateConvention.self,
            forKey: .coordinateConvention
        ) ?? .legacyEulerXZ

        deletedSurfaceIDs = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .deletedSurfaceIDs
        ) ?? []

        deletedObjectIDs = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .deletedObjectIDs
        ) ?? []

        boundaryStatus = try container.decodeIfPresent(
            FloorPlanBoundaryStatus.self,
            forKey: .boundaryStatus
        )
    }

    static func migrateIfNeeded(
        _ state: FloorPlanEditState,
        fallbackCreatedAt: Date? = nil,
        fallbackModifiedAt: Date? = nil,
        projectID: UUID? = nil
    ) -> FloorPlanEditState {
        guard state.schemaVersion <= currentSchemaVersion else {
            return state
        }

        var migrated = state

        if migrated.createdAt.isEmpty {
            migrated.createdAt = EditStateDateFormatter.string(
                from: fallbackCreatedAt ?? Date()
            )
        }

        if migrated.modifiedAt.isEmpty {
            migrated.modifiedAt = EditStateDateFormatter.string(
                from: fallbackModifiedAt ?? fallbackCreatedAt ?? Date()
            )
        }

        migrated.ensureStableIDs(projectID: projectID)
        migrated.schemaVersion = currentSchemaVersion

        return migrated
    }

    mutating func ensureStableIDs(projectID: UUID? = nil) {
        if var values = manualObjects {
            for index in values.indices where values[index].id == nil {
                values[index].id = Self.legacyStableID(
                    projectID: projectID,
                    kind: "manualObject",
                    index: index
                )
            }
            manualObjects = values
        }

        if var values = annotations {
            for index in values.indices where values[index].id == nil {
                values[index].id = Self.legacyStableID(
                    projectID: projectID,
                    kind: "annotation",
                    index: index
                )
            }
            annotations = values
        }
    }

    func validateForPersistence() throws {
        guard schemaVersion >= 1,
              schemaVersion <= Self.currentSchemaVersion else {
            throw FloorPlanPersistenceError.unsupportedSchema(
                schemaVersion
            )
        }

        guard cameraRotation.isFinite else {
            throw FloorPlanPersistenceError.invalidState(
                "相機角度不是有限數值。"
            )
        }

        for (key, value) in surfaces {
            guard UUID(uuidString: key) != nil,
                  value.x.isFinite,
                  value.y.isFinite,
                  value.zRotation.isFinite,
                  value.halfLength.isFinite,
                  value.halfLength >= 0 else {
                throw FloorPlanPersistenceError.invalidState(
                    "牆面或開口資料無效。"
                )
            }

            if let width = value.strokeWidth {
                guard width.isFinite, width > 0 else {
                    throw FloorPlanPersistenceError.invalidState(
                        "畫筆線寬無效。"
                    )
                }
            }

            if let thickness = value.thicknessMeters {
                guard thickness.isFinite, thickness > 0 else {
                    throw FloorPlanPersistenceError.invalidState(
                        "實體厚度無效。"
                    )
                }
            }
        }

        for (key, value) in objects {
            guard UUID(uuidString: key) != nil,
                  Self.validTransform(
                    x: value.x,
                    y: value.y,
                    angle: value.zRotation,
                    xScale: value.xScale,
                    yScale: value.yScale
                  ) else {
                throw FloorPlanPersistenceError.invalidState(
                    "掃描家具資料無效。"
                )
            }
        }

        for key in deletedSurfaceIDs.union(deletedObjectIDs) {
            guard UUID(uuidString: key) != nil else {
                throw FloorPlanPersistenceError.invalidState(
                    "刪除紀錄包含無效識別碼。"
                )
            }
        }

        var manualIDs = Set<UUID>()

        for value in manualObjects ?? [] {
            guard Self.validTransform(
                x: value.x,
                y: value.y,
                angle: value.zRotation,
                xScale: value.xScale,
                yScale: value.yScale
            ) else {
                throw FloorPlanPersistenceError.invalidState(
                    "手動家具資料無效。"
                )
            }

            _ = try JSONDecoder().decode(
                CapturedRoom.Object.Category.self,
                from: value.categoryData
            )

            if let id = value.id,
               !manualIDs.insert(id).inserted {
                throw FloorPlanPersistenceError.invalidState(
                    "手動家具識別碼重複。"
                )
            }
        }

        var annotationIDs = Set<UUID>()

        for value in annotations ?? [] {
            let components = [
                value.x,
                value.y,
                value.zRotation,
                value.fontSize,
                value.red,
                value.green,
                value.blue,
                value.alpha
            ]

            guard components.allSatisfy({ $0.isFinite }),
                  value.fontSize > 0,
                  (0...1).contains(value.red),
                  (0...1).contains(value.green),
                  (0...1).contains(value.blue),
                  (0...1).contains(value.alpha) else {
                throw FloorPlanPersistenceError.invalidState(
                    "文字標註資料無效。"
                )
            }

            if let id = value.id,
               !annotationIDs.insert(id).inserted {
                throw FloorPlanPersistenceError.invalidState(
                    "文字標註識別碼重複。"
                )
            }
        }

        if let calibration {
            guard calibration.scaleFactor.isFinite,
                  calibration.scaleFactor > 0,
                  calibration.referenceOriginalMeters.isFinite,
                  calibration.referenceOriginalMeters > 0,
                  calibration.referenceMeasuredMeters.isFinite,
                  calibration.referenceMeasuredMeters > 0 else {
                throw FloorPlanPersistenceError.invalidState(
                    "比例校準資料無效。"
                )
            }
        }
    }

    private static func validTransform(
        x: Double,
        y: Double,
        angle: Double,
        xScale: Double,
        yScale: Double
    ) -> Bool {
        x.isFinite &&
        y.isFinite &&
        angle.isFinite &&
        xScale.isFinite &&
        yScale.isFinite &&
        abs(xScale) > 0 &&
        abs(yScale) > 0
    }

    private static func legacyStableID(
        projectID: UUID?,
        kind: String,
        index: Int
    ) -> UUID {
        let namespace = projectID?.uuidString ?? "RoomPlanLegacy"
        let seed = "\(namespace)|\(kind)|\(index)"
        var bytes = Array(
            SHA256.hash(data: Data(seed.utf8)).prefix(16)
        )

        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
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

// MARK: - 本機紀錄庫：版本化資料檔與索引提交

final class RoomProjectStore: ObservableObject {
    static let shared = RoomProjectStore()

    @Published private(set) var projects: [SavedRoomProject] = []
    @Published private(set) var lastErrorMessage: String? = nil

    private let indexFileName = "saved_room_projects_index.json"
    private let folderName = "SavedRoomProjects"
    private var isIndexWritable = false

    init() {
        if Thread.isMainThread {
            loadIndex()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.loadIndex()
            }
        }
    }

    private func requireMainThread() -> Bool {
        guard Thread.isMainThread else {
            let message = FloorPlanPersistenceError
                .mainThreadRequired.localizedDescription

            DispatchQueue.main.async { [weak self] in
                self?.lastErrorMessage = message
            }

            return false
        }

        return true
    }

    private func storageDirectory() throws -> URL {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw FloorPlanPersistenceError
                .unavailableDocumentsDirectory
        }

        let directory = docs.appendingPathComponent(
            folderName,
            isDirectory: true
        )

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        return directory
    }

    private func fileURL(
        named name: String,
        in directory: URL
    ) throws -> URL {
        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.contains("\\"),
              !name.contains("\0"),
              name == (name as NSString).lastPathComponent else {
            throw FloorPlanPersistenceError.invalidFileName
        }

        return directory.appendingPathComponent(name)
    }

    private func backupURL(for url: URL) -> URL {
        let name = url.lastPathComponent
        let backupName: String

        if name.hasSuffix(".json") {
            backupName = String(name.dropLast(5)) + ".bak.json"
        } else {
            backupName = name + ".bak.json"
        }

        return url.deletingLastPathComponent()
            .appendingPathComponent(backupName)
    }

    private func validateDecodedValue<T>(_ value: T) throws {
        if let state = value as? FloorPlanEditState {
            try state.validateForPersistence()
        }

        if let index = value as? [SavedRoomProject] {
            var ids = Set<UUID>()

            for project in index {
                guard ids.insert(project.id).inserted,
                      project.areaPing.isFinite,
                      project.areaSqm.isFinite,
                      project.areaPing >= 0,
                      project.areaSqm >= 0,
                      project.createdAt.timeIntervalSince1970.isFinite,
                      project.updatedAt.timeIntervalSince1970.isFinite else {
                    throw FloorPlanPersistenceError.invalidState(
                        "空間紀錄庫索引無效。"
                    )
                }

                let directory = try storageDirectory()

                _ = try fileURL(
                    named: project.roomFileName,
                    in: directory
                )

                _ = try fileURL(
                    named: project.editStateFileName,
                    in: directory
                )
            }
        }
    }

    private func isUnsupportedSchema(_ error: Error) -> Bool {
        guard let persistenceError =
                error as? FloorPlanPersistenceError else {
            return false
        }

        if case .unsupportedSchema = persistenceError {
            return true
        }

        return false
    }

    private func safeWrite<T: Codable>(
        _ value: T,
        to destinationURL: URL,
        encoder: JSONEncoder,
        decoder: JSONDecoder = JSONDecoder()
    ) throws {
        let fm = FileManager.default
        let token = UUID().uuidString

        let temporaryURL = destinationURL
            .appendingPathExtension("\(token).tmp")

        let backup = backupURL(for: destinationURL)

        defer {
            try? fm.removeItem(at: temporaryURL)
        }

        try validateDecodedValue(value)

        let encodedData = try encoder.encode(value)
        try encodedData.write(to: temporaryURL, options: .atomic)

        let verifiedData = try Data(contentsOf: temporaryURL)
        let verifiedValue = try decoder.decode(
            T.self,
            from: verifiedData
        )

        try validateDecodedValue(verifiedValue)

        if fm.fileExists(atPath: destinationURL.path) {
            let oldData = try Data(contentsOf: destinationURL)

            do {
                let oldValue = try decoder.decode(
                    T.self,
                    from: oldData
                )

                try validateDecodedValue(oldValue)

                try oldData.write(to: backup, options: .atomic)
            } catch {
                if isUnsupportedSchema(error) {
                    throw error
                }

                if let backupData = try? Data(contentsOf: backup),
                   let backupValue = try? decoder.decode(
                    T.self,
                    from: backupData
                   ) {
                    try validateDecodedValue(backupValue)
                }
            }
        }

        try verifiedData.write(
            to: destinationURL,
            options: .atomic
        )
    }

    private func loadWithBackupFallback<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        let primaryError: Error

        do {
            let data = try Data(contentsOf: url)
            let decoded = try decoder.decode(type, from: data)
            try validateDecodedValue(decoded)
            return decoded
        } catch {
            if isUnsupportedSchema(error) {
                throw error
            }

            primaryError = error
        }

        let backup = backupURL(for: url)

        do {
            let data = try Data(contentsOf: backup)
            let decoded = try decoder.decode(type, from: data)
            try validateDecodedValue(decoded)

            print(
                "RoomProjectStore 主檔異常，已自動從備份復原: \(backup.lastPathComponent)"
            )

            return decoded
        } catch {
            if isUnsupportedSchema(error) {
                throw error
            }

            throw primaryError
        }
    }

    func loadIndex() {
        guard requireMainThread() else { return }

        do {
            let directory = try storageDirectory()
            let indexURL = directory.appendingPathComponent(
                indexFileName
            )

            let fm = FileManager.default
            let hasPrimary = fm.fileExists(
                atPath: indexURL.path
            )
            let hasBackup = fm.fileExists(
                atPath: backupURL(for: indexURL).path
            )

            if !hasPrimary && !hasBackup {
                projects = []
                isIndexWritable = true
                lastErrorMessage = nil
                return
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let decoded = try loadWithBackupFallback(
                [SavedRoomProject].self,
                from: indexURL,
                decoder: decoder
            )

            projects = decoded.sorted {
                $0.updatedAt > $1.updatedAt
            }

            isIndexWritable = true
            lastErrorMessage = nil
        } catch {
            isIndexWritable = false
            lastErrorMessage = error.localizedDescription
        }
    }

    private func persistIndex(
        _ proposedProjects: [SavedRoomProject]
    ) throws {
        let directory = try storageDirectory()
        let indexURL = directory.appendingPathComponent(
            indexFileName
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            try safeWrite(
                proposedProjects,
                to: indexURL,
                encoder: encoder,
                decoder: decoder
            )
        } catch {
            print(
                "RoomProjectStore 索引寫入失敗: \(error.localizedDescription)"
            )
            throw error
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
        guard requireMainThread() else { return nil }

        guard isIndexWritable else {
            lastErrorMessage = FloorPlanPersistenceError
                .indexUnavailable.localizedDescription
            return nil
        }

        guard areaPing.isFinite,
              areaSqm.isFinite,
              areaPing >= 0,
              areaSqm >= 0 else {
            lastErrorMessage = FloorPlanPersistenceError
                .invalidState("面積數值無效。")
                .localizedDescription
            return nil
        }

        var uncommittedURLs: [URL] = []

        do {
            guard editState.schemaVersion <=
                    FloorPlanEditState.currentSchemaVersion else {
                throw FloorPlanPersistenceError.unsupportedSchema(
                    editState.schemaVersion
                )
            }

            let directory = try storageDirectory()
            let id = existingID ?? UUID()
            let generation = UUID().uuidString

            let roomFile = "room_\(id.uuidString)_\(generation).json"
            let editFile = "edit_\(id.uuidString)_\(generation).json"

            let roomURL = try fileURL(
                named: roomFile,
                in: directory
            )

            let editURL = try fileURL(
                named: editFile,
                in: directory
            )

            let now = Date()
            let existingProject = projects.first {
                $0.id == id
            }

            var stateToSave = FloorPlanEditState.migrateIfNeeded(
                editState,
                fallbackCreatedAt: existingProject?.createdAt ?? now,
                fallbackModifiedAt: now,
                projectID: id
            )

            stateToSave.appVersion =
                FloorPlanEditState.currentAppVersion

            stateToSave.modifiedAt =
                EditStateDateFormatter.string(from: now)

            stateToSave.ensureStableIDs(projectID: id)
            try stateToSave.validateForPersistence()

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            uncommittedURLs = [roomURL, editURL]

            try safeWrite(
                capturedRoom,
                to: roomURL,
                encoder: encoder
            )

            try safeWrite(
                stateToSave,
                to: editURL,
                encoder: encoder
            )

            let project = SavedRoomProject(
                id: id,
                name: name,
                floorLabel: floorLabel,
                areaPing: areaPing,
                areaSqm: areaSqm,
                createdAt: existingProject?.createdAt ?? now,
                updatedAt: now,
                roomFileName: roomFile,
                editStateFileName: editFile
            )

            var proposedProjects = projects

            if let index = proposedProjects.firstIndex(
                where: { $0.id == id }
            ) {
                proposedProjects[index] = project
            } else {
                proposedProjects.append(project)
            }

            proposedProjects.sort {
                $0.updatedAt > $1.updatedAt
            }

            try persistIndex(proposedProjects)

            uncommittedURLs.removeAll()
            projects = proposedProjects
            lastErrorMessage = nil

            return project
        } catch {
            for url in uncommittedURLs {
                try? FileManager.default.removeItem(at: url)
            }

            lastErrorMessage = error.localizedDescription

            print(
                "RoomProjectStore 存檔失敗: \(error.localizedDescription)"
            )

            return nil
        }
    }

    func loadCapturedRoom(
        for project: SavedRoomProject
    ) -> CapturedRoom? {
        guard requireMainThread() else { return nil }

        do {
            let directory = try storageDirectory()
            let url = try fileURL(
                named: project.roomFileName,
                in: directory
            )

            let room = try loadWithBackupFallback(
                CapturedRoom.self,
                from: url
            )

            lastErrorMessage = nil
            return room
        } catch {
            lastErrorMessage = error.localizedDescription
            return nil
        }
    }

    func loadEditState(
        for project: SavedRoomProject
    ) -> FloorPlanEditState? {
        guard requireMainThread() else { return nil }

        do {
            let directory = try storageDirectory()
            let url = try fileURL(
                named: project.editStateFileName,
                in: directory
            )

            let decoded = try loadWithBackupFallback(
                FloorPlanEditState.self,
                from: url
            )

            let migrated = FloorPlanEditState.migrateIfNeeded(
                decoded,
                fallbackCreatedAt: project.createdAt,
                fallbackModifiedAt: project.updatedAt,
                projectID: project.id
            )

            try migrated.validateForPersistence()

            lastErrorMessage = nil
            return migrated
        } catch {
            lastErrorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteProject(_ project: SavedRoomProject) {
        guard requireMainThread() else { return }

        guard isIndexWritable else {
            lastErrorMessage = FloorPlanPersistenceError
                .indexUnavailable.localizedDescription
            return
        }

        guard projects.contains(where: { $0.id == project.id }) else {
            return
        }

        let proposedProjects = projects.filter {
            $0.id != project.id
        }

        do {
            try persistIndex(proposedProjects)
            projects = proposedProjects
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
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

    // 基準尺全域校準
    @Published var calibrationRequest: FloorPlanCalibrationRequest? = nil
    @Published var statusToastMessage: String? = nil

    // 第一階段：面積坪數、空間用途、藍圖圖層開關與修圖輔助
    @Published var roomAreaSqm: Double = 0.0
    @Published var roomAreaPing: Double = 0.0
    @Published var roomUsage: String = "室內空間"
    @Published var floorLabel: String = "1F"

    @Published var showFurniture: Bool = true
    @Published var showDimensions: Bool = true
    @Published var showFurnitureLabels: Bool = true
    @Published var showStructuralMarkers: Bool = true

    @Published var shouldRotate90: Bool = false
    @Published var shouldRecenter: Bool = false
    @Published var shouldUndo: Bool = false
    @Published var shouldRedo: Bool = false
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false

    // 第二階段：專案儲存與讀取狀態
    @Published var savedProjectID: UUID? = nil
    @Published var shouldSaveProject: Bool = false

    var initialEditState: FloorPlanEditState? = nil
    var editStateCreatedAt: String? = nil
    var displayUnit: DisplayUnit = .centimeter
    var calibrationState: SavedCalibrationState? = nil

    var coordinateConvention: FloorPlanCoordinateConvention = .basisXZ
    var deletedSurfaceIDs: Set<String> = []
    var deletedObjectIDs: Set<String> = []

    @Published private(set) var modelRevision: UInt64 = 0
    @Published private(set) var savedRevision: UInt64 = 0
    @Published private(set) var boundaryStatus:
        FloorPlanBoundaryStatus = .empty

    var isRoomBoundaryClosed: Bool {
        boundaryStatus == .closed
    }

    // Commit 3 (v0.3.0-beta.1)：未存檔狀態管理
    @Published var isDirty: Bool = false
    @Published var shouldDismissAfterSave: Bool = false
    @Published var didCompleteSaveForDismiss: Bool = false

    // Commit 5 (v0.3.0)：牆體鎖定（操作偏好，不納入幾何資料）
    @Published var isWallLocked: Bool = false

    private func performOnMain(
        _ operation: @escaping () -> Void
    ) {
        if Thread.isMainThread {
            operation()
        } else {
            DispatchQueue.main.async(execute: operation)
        }
    }

    func markDirty(reason: String) {
        performOnMain { [weak self] in
            guard let self else { return }

            self.modelRevision &+= 1
            self.isDirty = true

            print("[DirtyState] marked dirty: \(reason)")
        }
    }

    func clearDirty(
        ifRevisionMatches revision: UInt64? = nil
    ) {
        performOnMain { [weak self] in
            guard let self else { return }

            if let revision,
               revision != self.modelRevision {
                return
            }

            self.savedRevision = self.modelRevision
            self.isDirty = false
        }
    }

    func updateBoundaryResult(
        _ result: FloorPlanBoundaryResult,
        revision: UInt64
    ) {
        performOnMain { [weak self] in
            guard let self,
                  revision == self.modelRevision else {
                return
            }

            self.boundaryStatus = result.status

            if result.status == .closed,
               let area = result.areaSquareMeters {
                self.roomAreaSqm = area
                self.roomAreaPing = area * 0.3025
            } else {
                self.roomAreaSqm = 0
                self.roomAreaPing = 0
            }
        }
    }

    func adoptSavedProject(
        _ project: SavedRoomProject,
        preservingWallLock: Bool = true
    ) {
        performOnMain { [weak self] in
            guard let self else { return }

            let previousID = self.savedProjectID
            let previousLock = self.isWallLocked

            self.savedProjectID = project.id

            if preservingWallLock {
                self.isWallLocked = previousLock

                UserDefaults.standard.set(
                    previousLock,
                    forKey: "wall_locked_\(project.id.uuidString)"
                )
            } else if previousID != project.id {
                self.loadWallLockPreference(for: project.id)
            }
        }
    }

    func setWallLocked(_ locked: Bool) {
        performOnMain { [weak self] in
            guard let self,
                  self.isWallLocked != locked else {
                return
            }

            self.isWallLocked = locked

            if let projectID = self.savedProjectID {
                UserDefaults.standard.set(
                    locked,
                    forKey: "wall_locked_\(projectID.uuidString)"
                )
            }
        }
    }

    func loadWallLockPreference(for projectID: UUID?) {
        performOnMain { [weak self] in
            guard let self else { return }

            guard let projectID else {
                self.isWallLocked = false
                return
            }

            let key = "wall_locked_\(projectID.uuidString)"

            if UserDefaults.standard.object(forKey: key) != nil {
                self.isWallLocked = UserDefaults.standard.bool(
                    forKey: key
                )
            } else {
                self.isWallLocked = false
            }
        }
    }
}

extension Notification.Name {
    static let floorPlanModelDidMutate =
        Notification.Name("floorPlanModelDidMutate")
}
