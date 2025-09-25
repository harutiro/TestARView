//
//  Item.swift
//  TestARView
//
//  Created by はるちろ on R 7/09/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
