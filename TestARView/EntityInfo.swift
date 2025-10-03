//
//  EntityInfo.swift
//  TestARView
//
//  Created by Assistant on R 7/09/26.
//

import Foundation
import RealityKit

// エンティティのカテゴリを定義するenum
enum EntityCategory: String, CaseIterable, Codable {
    // 構造
    case wall = "Wall"
    case floor = "Floor"

    // 家具・設備
    case storage = "storage"
    case television = "television"
    case bathtub = "bathtub"
    case bed = "bed"
    case chair = "chair"
    case dishwasher = "dishwasher"
    case fireplace = "fireplace"
    case oven = "oven"
    case refrigerator = "refrigerator"
    case sink = "sink"
    case sofa = "sofa"
    case stairs = "stairs"
    case stove = "stove"
    case table = "table"
    case toilet = "toilet"
    case washerDryer = "washerDryer"

    // 特殊
    case root = "Root"
    case other = "その他"

    // 絵文字アイコンを取得
    var icon: String {
        switch self {
        case .wall: return "🏠"
        case .floor: return "🟫"
        case .storage: return "🏪"
        case .television: return "📺"
        case .bathtub: return "🛁"
        case .bed: return "🛏️"
        case .chair: return "🪑"
        case .dishwasher: return "🍽️"
        case .fireplace: return "🔥"
        case .oven: return "🔥"
        case .refrigerator: return "❄️"
        case .sink: return "🚰"
        case .sofa: return "🛋️"
        case .stairs: return "🪜"
        case .stove: return "🔥"
        case .table: return "🪑"
        case .toilet: return "🚽"
        case .washerDryer: return "🧽"
        case .root: return "📁"
        case .other: return "📦"
        }
    }

    // SF Symbolsアイコン名を取得
    var systemIconName: String {
        switch self {
        case .wall: return "rectangle.split.3x1"
        case .floor: return "square.grid.3x3"
        case .storage: return "cabinet"
        case .television: return "tv"
        case .bathtub: return "bathtub"
        case .bed: return "bed.double"
        case .chair: return "chair"
        case .dishwasher: return "dishwasher"
        case .fireplace: return "flame"
        case .oven: return "oven"
        case .refrigerator: return "refrigerator"
        case .sink: return "sink"
        case .sofa: return "sofa"
        case .stairs: return "stairs"
        case .stove: return "stove"
        case .table: return "table"
        case .toilet: return "toilet"
        case .washerDryer: return "washer"
        case .root: return "folder"
        case .other: return "cube"
        }
    }

    // 日本語表示名を取得
    var displayName: String {
        switch self {
        case .wall: return "壁"
        case .floor: return "床"
        case .storage: return "収納"
        case .television: return "テレビ"
        case .bathtub: return "浴槽"
        case .bed: return "ベッド"
        case .chair: return "椅子"
        case .dishwasher: return "食洗機"
        case .fireplace: return "暖炉"
        case .oven: return "オーブン"
        case .refrigerator: return "冷蔵庫"
        case .sink: return "シンク"
        case .sofa: return "ソファ"
        case .stairs: return "階段"
        case .stove: return "コンロ"
        case .table: return "テーブル"
        case .toilet: return "トイレ"
        case .washerDryer: return "洗濯機"
        case .root: return "ルート"
        case .other: return "その他"
        }
    }
}

struct EntityInfo: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let category: EntityCategory
    let level: Int
    var entity: Entity?

    static func == (lhs: EntityInfo, rhs: EntityInfo) -> Bool {
        return lhs.id == rhs.id
    }
}
