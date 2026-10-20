//
//  Item.swift
//  Beat Meister
//
//  Created by John Aldrich on 10/20/26.
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
