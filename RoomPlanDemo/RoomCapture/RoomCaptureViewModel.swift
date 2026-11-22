import Foundation
import Combine
@preconcurrency import RoomPlan
import UIKit

enum RoomCapturePhase: Equatable {
    case idle, scanning, processing, ready, failed, cancelled
}

@MainActor
final class RoomCaptureViewModel: ObservableObject {
    @Published private(set) var roomCaptureView: RoomCaptureView
    @Published private(set) var phase: RoomCapturePhase = .idle
    @Published private(set) var autoSavedProject: SavedRoomProject?
    @Published var finalRoom: CapturedRoom?
    @Published var isShowError = false
    @Published var errorMessage = ""
    @Published private(set) var isScanning = false
    @Published var isShowingFloorPlan = false

    private let captureSessionConfig = RoomCaptureSession.Configuration()
    private var generation = UUID()
    private var processingTask: Task<Void, Never>?
    private var acceptedEnd = false

    init() {
        roomCaptureView = RoomCaptureView(frame: .zero)
        roomCaptureView.captureSession.delegate = self
    }

    func startSession() {
        guard phase != .scanning, phase != .processing else { return }
        processingTask?.cancel()
        generation = UUID()
        acceptedEnd = false
        // Each run has its own session identity. Late delegate calls from a
        // previous run cannot be mistaken for this run, even after retry.
        if phase != .idle {
            roomCaptureView.captureSession.delegate = nil
            roomCaptureView = RoomCaptureView(frame: .zero)
        }
        roomCaptureView.captureSession.delegate = self
        finalRoom = nil
        autoSavedProject = nil
        isShowingFloorPlan = false
        errorMessage = ""
        isShowError = false
        phase = .scanning
        isScanning = true
        UIApplication.shared.isIdleTimerDisabled = true
        roomCaptureView.captureSession.run(configuration: captureSessionConfig)
    }

    func stopSession() {
        guard phase == .scanning else { return }
        phase = .processing
        isScanning = false
        UIApplication.shared.isIdleTimerDisabled = false
        roomCaptureView.captureSession.stop()
    }

    func cancelSession() {
        guard phase != .cancelled else { return }
        let wasRunning = phase == .scanning
        generation = UUID()
        processingTask?.cancel()
        processingTask = nil
        acceptedEnd = true
        roomCaptureView.captureSession.delegate = nil
        phase = .cancelled
        isScanning = false
        isShowingFloorPlan = false
        UIApplication.shared.isIdleTimerDisabled = false
        if wasRunning { roomCaptureView.captureSession.stop() }
    }

    func handleScanButtonTap() {
        switch phase {
        case .idle, .failed, .cancelled:
            startSession()
        case .scanning:
            stopSession()
        case .processing:
            break
        case .ready:
            guard finalRoom != nil else { return }
            isShowingFloorPlan = true
        }
    }

    // Pure read: safe to use while SwiftUI evaluates body.
    func getFinalRoom() -> CapturedRoom? { finalRoom }

    func shareCapturedRoom() {
        guard phase == .ready, let finalRoom else {
            errorMessage = "目前沒有可匯出的空間掃描資料。"
            isShowError = true
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapturedRoom.usdz")
        do {
            try finalRoom.export(to: url)
            presentShareSheet(with: url)
        } catch {
            errorMessage = "匯出 USDZ 3D 模型失敗：\(error.localizedDescription)"
            isShowError = true
        }
    }

    private func receiveEnd(
        session: RoomCaptureSession, data: CapturedRoomData, error: Error?
    ) {
        guard session === roomCaptureView.captureSession,
              phase == .scanning || phase == .processing,
              !acceptedEnd else { return }
        acceptedEnd = true
        isScanning = false
        UIApplication.shared.isIdleTimerDisabled = false
        if let error {
            handleCaptureError(error)
            return
        }
        phase = .processing
        let token = generation
        let builder = RoomBuilder(options: [.beautifyObjects])
        processingTask = Task { @MainActor [weak self] in
            do {
                let room = try await builder.capturedRoom(from: data)
                guard !Task.isCancelled, let self,
                      self.generation == token, self.phase == .processing else { return }
                self.handleSuccessfulRoomCapture(room, token: token)
            } catch {
                guard !Task.isCancelled, let self,
                      self.generation == token, self.phase == .processing else { return }
                self.handleRoomProcessingError(error)
            }
        }
    }

    private func handleCaptureError(_ error: Error) {
        guard phase != .cancelled else { return }
        phase = .failed
        isScanning = false
        errorMessage = error.localizedDescription
        isShowError = true
    }

    private func handleRoomProcessingError(_ error: Error) {
        guard phase != .cancelled else { return }
        phase = .failed
        isScanning = false
        errorMessage = error.localizedDescription
        isShowError = true
    }

    private func handleSuccessfulRoomCapture(_ room: CapturedRoom, token: UUID) {
        guard generation == token, phase == .processing else { return }
        finalRoom = room
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let draftName = "自動儲存草稿-\(formatter.string(from: Date()))"
        // Synchronous main-actor commit: cancellation cannot interleave between
        // the generation check and draft creation. Never save in a detached task.
        autoSavedProject = RoomProjectStore.shared.saveProject(
            existingID: nil, name: draftName, floorLabel: "1F",
            areaPing: 0, areaSqm: 0, capturedRoom: room,
            editState: FloorPlanEditState(surfaces: [:], objects: [:], cameraRotation: 0)
        )
        if autoSavedProject == nil {
            errorMessage = RoomProjectStore.shared.lastErrorMessage
                ?? "自動儲存草稿失敗，請進入平面圖後手動儲存。"
            isShowError = true
        }
        phase = .ready
        processingTask = nil
    }

    private func presentShareSheet(with fileURL: URL) {
        guard let topVC = getTopViewController() else {
            errorMessage = "無法開啟分享選單，請稍後再試。"
            isShowError = true
            return
        }
        let controller = UIActivityViewController(
            activityItems: [fileURL], applicationActivities: nil
        )
        if let popover = controller.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(
                x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0
            )
            popover.permittedArrowDirections = []
        }
        topVC.present(controller, animated: true)
    }

    private func getTopViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        else { return nil }
        var top = window.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

extension RoomCaptureViewModel: RoomCaptureSessionDelegate {
    nonisolated func captureSession(
        _ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?
    ) {
        // Delegate callbacks are not assumed to run on the main thread.
        Task { @MainActor [weak self] in
            self?.receiveEnd(session: session, data: data, error: error)
        }
    }
}
