//
//  Float+Extensions.swift
//  Asteroids
//
//  Created by Miguel Angel Lozano Ortega on 19/01/2020.
//  Copyright © 2020 Miguel Angel Lozano Ortega. All rights reserved.
//

import Foundation

public extension Float {
    
    static func getRandom(
        from min: Float = -1.0,
        to max: Float = 1.0
    ) -> Float {
        return Float.random(in: min...max)
    }
}
