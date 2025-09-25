//
//  EntityInfo.swift
//  TestARView
//
//  Created by Assistant on R 7/09/26.
//

import Foundation
import RealityKit

struct EntityInfo: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let category: String
    let level: Int
    var entity: Entity?  // weakを削除
    
    static func == (lhs: EntityInfo, rhs: EntityInfo) -> Bool {
        return lhs.id == rhs.id
    }
}