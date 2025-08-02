//
//  Item.swift
//  Team Airavata Hub
//
//  Created by Shivam on 28/07/25.
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
