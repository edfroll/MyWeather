//
//  Item.swift
//  MyWeather
//
//  Created by Edward on 05.09.26.
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
