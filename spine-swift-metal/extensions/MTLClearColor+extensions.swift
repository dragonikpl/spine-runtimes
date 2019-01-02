//
//  MTLClearColor+extensions.swift
//  MetalTest
//
//  Created by Lukasz Domaradzki on 26/12/2018.
//  Copyright © 2018 Lukasz Domaradzki. All rights reserved.
//

import UIKit
import Metal

extension MTLClearColor {
    init(color: UIColor) {
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var alpha: CGFloat = 0.0
        
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(red: Double(red), green: Double(green), blue: Double(blue), alpha: Double(alpha))
    }
}
