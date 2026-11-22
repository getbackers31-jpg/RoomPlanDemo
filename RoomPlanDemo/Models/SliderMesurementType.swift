//
//  SliderMesurementType.swift
//  RoomPlanPDP
//
//  Created by Baidetskyi Yurii on 24.01.2025.
//

import Foundation
import CoreGraphics

enum SliderMesurementType: Equatable, Hashable {
    case angle(CGFloat)
    case width(CGFloat)
    case depth(CGFloat)
    case position(CGFloat)

    var title: String {
        description
    }

    var description: String {
        switch self {
        case .angle:
            return "角度"
        case .width:
            return "寬度"
        case .depth:
            return "厚度"
        case .position:
            return "位置"
        }
    }

    var convertedText: String {
        switch self {
        case .angle(let radians):
            let value = radians.isFinite ? radians * 180 / .pi : 0
            return String(format: "%.1f°", value)
        case .width(let points):
            let metres = points.isFinite
                ? points / DrawParameters.scalingFactor
                : 0
            return String(format: "%.2f m", metres)
        case .depth(let metres):
            return String(format: "%.2f m", metres.isFinite ? metres : 0)
        case .position(let value):
            return String(format: "%.1f", value.isFinite ? value : 0)
        }
    }

    var minimumValueLabel: String {
        switch self {
        case .angle:
            return "-180°"
        case .width:
            let metres = closedRange.lowerBound / DrawParameters.scalingFactor
            return String(format: "%.2f m", metres)
        case .depth:
            return String(format: "%.2f m", closedRange.lowerBound)
        case .position:
            return String(format: "%.0f", closedRange.lowerBound)
        }
    }

    var maximumValueLabel: String {
        switch self {
        case .angle:
            return "180°"
        case .width:
            let metres = closedRange.upperBound / DrawParameters.scalingFactor
            return String(format: "%.2f m", metres)
        case .depth:
            return String(format: "%.2f m", closedRange.upperBound)
        case .position:
            return String(format: "%.0f", closedRange.upperBound)
        }
    }

    var closedRange: ClosedRange<CGFloat> {
        switch self {
        case .angle:
            return (-CGFloat.pi)...CGFloat.pi
        case .width(let currentValue):
            let tenMetersInPoints = DrawParameters.scalingFactor * 10
            let safeCurrent = currentValue.isFinite && currentValue > 0
                ? currentValue
                : tenMetersInPoints
            return min(10, safeCurrent)...max(tenMetersInPoints, safeCurrent)
        case .depth(let currentValue):
            let safeCurrent = currentValue.isFinite && currentValue > 0
                ? currentValue
                : 1
            return min(0.05, safeCurrent)...max(1, safeCurrent)
        case .position:
            return -2000...2000
        }
    }
}
