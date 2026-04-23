//
//  SCNVector3+Extensions.swift
//  Asteroids
//
//  Created by Miguel Angel Lozano Ortega on 19/01/2020.
//  Copyright © 2020 Miguel Angel Lozano Ortega. All rights reserved.
//

import SceneKit

public extension SCNVector3 {
    
    static func getRandom(
        from min: SCNVector3 = SCNVector3(-1, -1, -1),
        to max: SCNVector3 = SCNVector3(1, 1, 1)
    ) -> SCNVector3 {
        return SCNVector3(
            Float.getRandom(from: min.x, to: max.x),
            Float.getRandom(from: min.y, to: max.y),
            Float.getRandom(from: min.z, to: max.z)
        )
    }
    
    static func + (left: SCNVector3, right: SCNVector3) -> SCNVector3 {
        return SCNVector3(
            left.x + right.x,
            left.y + right.y,
            left.z + right.z
        )
    }
    
    static func - (left: SCNVector3, right: SCNVector3) -> SCNVector3 {
        return SCNVector3(
            left.x - right.x,
            left.y - right.y,
            left.z - right.z
        )
    }
    
    static prefix func - (vector: SCNVector3) -> SCNVector3 {
        return SCNVector3(
            -vector.x,
            -vector.y,
            -vector.z
        )
    }
}
