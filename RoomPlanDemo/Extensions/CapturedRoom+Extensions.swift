//
//  CapturedRoom+Extensions.swift
//  RoomPlanPDP
//
//  Created by Baidetskyi Yurii on 24.01.2025.
//

import RoomPlan

extension CapturedRoom.Object.Category {
    var displayName: String {
        switch self {
        case .storage:
            return "收納櫃/衣櫃"
        case .refrigerator:
            return "冰箱"
        case .stove:
            return "瓦斯爐/爐具"
        case .bed:
            return "床鋪"
        case .sink:
            return "水槽/洗手台"
        case .washerDryer:
            return "洗衣/烘衣機"
        case .toilet:
            return "馬桶"
        case .bathtub:
            return "浴缸"
        case .oven:
            return "烤箱"
        case .dishwasher:
            return "洗碗機"
        case .table:
            return "桌子"
        case .sofa:
            return "沙發"
        case .chair:
            return "椅子"
        case .fireplace:
            return "壁爐"
        case .television:
            return "電視"
        case .stairs:
            return "樓梯"
        @unknown default:
            return "未知物件"
        }
    }
    
    var imageName: String {
        switch self {
        case .storage:
            return "wardrobe"
        case .refrigerator:
            return "machinery"
        case .stove:
            return "stove"
        case .bed:
            return "bed"
        case .sink:
            return "sink"
        case .washerDryer:
            return "dishwasher"
        case .toilet:
            return "toilet"
        case .bathtub:
            return "bath"
        case .oven:
            return "stove"
        case .dishwasher:
            return "dishwasher"
        case .table:
            return "table"
        case .sofa:
            return "sofa"
        case .chair:
            return "armchair"
        case .fireplace:
            return "fireplace"
        case .television:
            return "tv-monitor"
        case .stairs:
            return "steps"
        @unknown default:
            return ""
        }
    }
}
