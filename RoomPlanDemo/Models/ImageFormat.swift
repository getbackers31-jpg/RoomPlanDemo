import Foundation

enum ImageFormat: String, CaseIterable {
    case png
    case jpeg
    case pdf
    case dxf
    
    var descriptionFormat: String {
        switch self {
        case .png:
            "PNG"
        case .jpeg:
            "JPEG"
        case .pdf:
            "PDF"
        case .dxf:
            "DXF (CAD)"
        }
    }
}