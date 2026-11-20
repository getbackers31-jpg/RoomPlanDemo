import SwiftUI

struct ShareImageView: View {
    @Binding var shouldShareImage: Bool
    @Binding var shareFormat: ImageFormat?
    @Binding var roomOptionType: RoomOptionType?

    @State private var selectedFormat: ImageFormat = .png

    private let formats: [(format: ImageFormat, title: String, subtitle: String)] = [
        (.png, "PNG", "高畫質藍圖"),
        (.jpeg, "JPEG", "壓縮圖片"),
        (.pdf, "PDF", "列印報告"),
        (.dxf, "DXF (CAD)", "AutoCAD 圖檔")
    ]

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("選擇匯出格式")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(Color(red: 0.12, green: 0.14, blue: 0.18))
                Spacer()
                Button {
                    roomOptionType = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(Color(red: 0.45, green: 0.49, blue: 0.55))
                }
            }

            HStack(spacing: 10) {
                ForEach(formats, id: \.format) { item in
                    let isSelected = (selectedFormat == item.format)
                    Button {
                        selectedFormat = item.format
                    } label: {
                        VStack(spacing: 4) {
                            Text(item.title)
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(isSelected ? AppTheme.accentBlue : Color(red: 0.16, green: 0.19, blue: 0.24))
                            Text(item.subtitle)
                                .font(.caption2)
                                .foregroundColor(Color(red: 0.42, green: 0.46, blue: 0.52))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(isSelected ? AppTheme.accentBlue.opacity(0.12) : Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? AppTheme.accentBlue : Color.gray.opacity(0.25), lineWidth: isSelected ? 2 : 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                let chosen = selectedFormat
                roomOptionType = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    shareFormat = chosen
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("匯出 \(selectedFormat == .dxf ? "DXF (AutoCAD)" : selectedFormat.rawValue.uppercased()) 檔案")
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.accentBlue)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(red: 0.95, green: 0.96, blue: 0.98))
    }
}