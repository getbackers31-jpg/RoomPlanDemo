import UIKit
import SwiftUI

struct AppTheme {
    // 品牌與浮水印（日後想好品牌名稱可直接改這裡，5 秒全站換膚）
    static let appTitle: String = "空間掃描 Pro"
    static let footerText: String = "空間掃描 Pro ｜ LiDAR 建築藍圖丈量系統"
    
    // UI 主題色（中性建築工程風）
    static let primaryBarBg: Color = Color(red: 0.11, green: 0.13, blue: 0.16)
    static let accentBlue: Color = Color(red: 0.16, green: 0.48, blue: 0.84)
    static let accentAmber: Color = Color(red: 0.90, green: 0.52, blue: 0.16)
    static let toggleActiveBg: Color = Color(red: 0.14, green: 0.42, blue: 0.36)
    static let toggleInactiveBg: Color = Color(red: 0.24, green: 0.27, blue: 0.31)
    
    // 藍圖畫布配色 (UIColor for SpriteKit)
    static let canvasBg: UIColor = UIColor(red: 0.985, green: 0.988, blue: 0.992, alpha: 1.0)
    static let gridMinor: UIColor = UIColor(red: 0.88, green: 0.90, blue: 0.93, alpha: 0.55)
    static let gridMajor: UIColor = UIColor(red: 0.78, green: 0.82, blue: 0.88, alpha: 0.75)
    static let wallStroke: UIColor = UIColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1.0)
    static let doorStroke: UIColor = UIColor(red: 0.88, green: 0.44, blue: 0.18, alpha: 1.0)
    static let doorFill: UIColor = UIColor(red: 0.88, green: 0.44, blue: 0.18, alpha: 0.12)
    static let windowStroke: UIColor = UIColor(red: 0.16, green: 0.48, blue: 0.84, alpha: 1.0)
    static let furnitureStroke: UIColor = UIColor(red: 0.28, green: 0.32, blue: 0.38, alpha: 1.0)
    static let furnitureFill: UIColor = UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 0.92)
    static let dimensionLine: UIColor = UIColor(red: 0.25, green: 0.28, blue: 0.32, alpha: 1.0)
    static let dimensionText: UIColor = UIColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1.0)
}

struct DrawParameters {
    // 1 公尺 = 200 pt（1 公分 = 2 pt）
    static let scalingFactor: CGFloat = 200
    
    static let floorPlanSize: CGSize = .init(width: 2400, height: 2400)
    static let floorPlanAnchorPoint: CGPoint = .init(x: 0.5, y: 0.5)
    
    static let wallWidth: CGFloat = 22.0
    static let surfaceWidth: CGFloat = 14.0
    static let hideSurfaceWidth: CGFloat = 24.0
    static let windowWidth: CGFloat = 14.0
    static let doorArcWidth: CGFloat = 3.5
    static let objectOutlineWidth: CGFloat = 3.0

    static let gridZPosition: CGFloat = -100
    static let hideSurfaceZPosition: CGFloat = 2
    static let windowZPosition: CGFloat = 10
    static let windowArcZPosition: CGFloat = 21
    static let doorZPosition: CGFloat = 20
    static let doorArcZPosition: CGFloat = 21
    static let objectZPosition: CGFloat = 15
    static let objectOutlineZPosition: CGFloat = 31
    static let dimensionZPosition: CGFloat = 36
    static let annotationZPosition: CGFloat = 40
    
    static let floorPlanBackgroundColor: UIColor = AppTheme.canvasBg
    static let floorPlanSurfaceColor: UIColor = AppTheme.canvasBg
}