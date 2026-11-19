//
//  SliderMesurementType.swift
//  RoomPlanPDP
//
//  Created by Baidetskyi Yurii on 19.01.2025.
//

import Foundation

enum SliderMesurementType: Equatable, Hashable {
    case angle(CGFloat)
    case width(CGFloat)
    case depth(CGFloat)
    case xPosition(Double)
    case yPosition(Double)
    case zPosition(Double)
    
    var convertedText: String {
        switch self {
        case .angle(let updatedValue):
            "\(Int(updatedValue.radiansToDegrees))°"
        case .width(let updatedValue), .depth(let updatedValue):
            String(format: "%.2f 公尺", updatedValue / 100)
        case .xPosition(let updatedValue), .yPosition(let updatedValue), .zPosition(let updatedValue):
            "\(updatedValue)"
        }
    }
    
    var title: String {
        switch self {
        case .angle:
            "調整角度："
        case .width:
            "調整長度："
        case .depth:
            "調整厚度："
        case .xPosition:
            "X 軸位置："
        case .yPosition:
            "Y 軸位置："
        case .zPosition:
            "Z 軸位置："
        }
    }
    
    var minimumValueLabel: String {
        switch self {
        case .angle:
            "-180°"
        case .width:
            "10 cm"
        case .depth:
            "0 m"
        case .xPosition, .yPosition, .zPosition:
            ""
        }
    }
    
    var maximumValueLabel: String {
        switch self {
        case .angle:
            "180°"
        case .width:
            "10 m"
        case .depth:
            "1 m"
        case .xPosition, .yPosition, .zPosition:
            ""
        }
    }
    
    var closedRange: ClosedRange<CGFloat> {
        switch self {
        case .angle:
            -(.pi)...(.pi)
        case .width:
            10...1000
        case .depth:
            1...100
        case .xPosition, .yPosition, .zPosition:
            0...0
        }
    }
}
