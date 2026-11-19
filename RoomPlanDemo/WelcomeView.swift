import SwiftUI

private enum ActiveScanRoute: Identifiable {
    case newScan
    case demo
    case saved(SavedRoomProject)
    
    var id: String {
        switch self {
        case .newScan: return "newScan"
        case .demo: return "demo"
        case .saved(let project): return project.id.uuidString
        }
    }
}

struct WelcomeView: View {
    @ObservedObject private var projectStore = RoomProjectStore.shared
    @State private var activeRoute: ActiveScanRoute? = nil
    @State private var projectToDelete: SavedRoomProject? = nil
    
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd HH:mm"
        return f
    }()
    
    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.96, blue: 0.98)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerBanner
                
                ScrollView {
                    VStack(spacing: 16) {
                        actionButtonsSection
                        savedLibrarySection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
                
                footerWatermark
            }
        }
        .fullScreenCover(item: $activeRoute) { route in
            NavigationStack {
                switch route {
                case .newScan:
                    RoomCaptureScanView(isDemo: false)
                case .demo:
                    RoomCaptureScanView(isDemo: true)
                        .toolbar(.hidden, for: .navigationBar)
                case .saved(let project):
                    RoomCaptureScanView(isDemo: false, savedProject: project)
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
        .alert("刪除空間紀錄", isPresented: Binding(
            get: { projectToDelete != nil },
            set: { if !$0 { projectToDelete = nil } }
        )) {
            Button("刪除", role: .destructive) {
                if let target = projectToDelete {
                    withAnimation {
                        projectStore.deleteProject(target)
                    }
                }
                projectToDelete = nil
            }
            Button("取消", role: .cancel) {
                projectToDelete = nil
            }
        } message: {
            Text("確定要刪除「\(projectToDelete?.name ?? "")」嗎？此操作無法復原。")
        }
    }
}

private extension WelcomeView {
    var headerBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppTheme.appTitle)
                        .font(.title2)
                        .fontWeight(.heavy)
                        .foregroundColor(.white)
                    Text("LiDAR 建築藍圖丈量・自動算坪數・AutoCAD DXF")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.78))
                }
                Spacer()
                Image(systemName: "ruler.fill")
                    .font(.title2)
                    .foregroundColor(Color(red: 0.96, green: 0.84, blue: 0.56))
                    .padding(10)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(AppTheme.primaryBarBg)
    }
    
    var actionButtonsSection: some View {
        VStack(spacing: 10) {
            Button {
                activeRoute = .newScan
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "camera.metering.matrix")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)
                        .background(Color.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("啟動新物件掃描")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("使用 iPhone LiDAR 光達建立 2D 建築藍圖與 3D 模型")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.85))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.white.opacity(0.85))
                        .fontWeight(.bold)
                }
                .padding(16)
                .background(
                    LinearGradient(
                        colors: [AppTheme.accentBlue, Color(red: 0.10, green: 0.34, blue: 0.66)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: AppTheme.accentBlue.opacity(0.32), radius: 8, y: 4)
            }
            
            Button {
                activeRoute = .demo
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.viewfinder")
                        .foregroundColor(AppTheme.accentBlue)
                    Text("開啟範例藍圖展示（測試編輯與 DXF 匯出）")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(red: 0.16, green: 0.19, blue: 0.24))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
            }
        }
    }
    
    var savedLibrarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("已儲存空間紀錄庫")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(Color(red: 0.14, green: 0.16, blue: 0.20))
                Spacer()
                Text("共 \(projectStore.projects.count) 筆")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            
            if projectStore.projects.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("尚未儲存任何空間紀錄")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Text("掃描完成或開啟範例展示後，點擊右上角「儲存」即可將藍圖與校準尺寸永久保存在手機本機。")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .padding(.horizontal, 20)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(projectStore.projects) { project in
                        projectCard(project)
                    }
                }
            }
        }
    }
    
    func projectCard(_ project: SavedRoomProject) -> some View {
        HStack(spacing: 12) {
            Button {
                activeRoute = .saved(project)
            } label: {
                HStack(spacing: 12) {
                    VStack(spacing: 2) {
                        Text(project.floorLabel)
                            .font(.caption)
                            .fontWeight(.heavy)
                            .foregroundColor(.white)
                    }
                    .frame(width: 44, height: 44)
                    .background(AppTheme.primaryBarBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(Color(red: 0.12, green: 0.14, blue: 0.18))
                        
                        Text(String(format: "約 %.2f 坪（%.1f ㎡）", project.areaPing, project.areaSqm))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(AppTheme.accentBlue)
                        
                        Text("更新：\(Self.dateFormatter.string(from: project.updatedAt))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("開啟編輯")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(AppTheme.accentBlue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.accentBlue.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .buttonStyle(.plain)
            
            Button {
                projectToDelete = project
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundColor(.red.opacity(0.75))
                    .padding(8)
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
    
    var footerWatermark: some View {
        Text(AppTheme.footerText)
            .font(.caption2)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.85))
    }
}