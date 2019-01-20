//
//  MTLRenderPassDescriptor+extensions.swift
//  MetalTest
//
//  Created by Lukasz Domaradzki on 26/12/2018.
//  Copyright © 2018 Lukasz Domaradzki. All rights reserved.
//

import UIKit
import Metal

extension MTLRenderPassDescriptor {
    convenience init(texture: MTLTexture, sampleTex: MTLTexture, clearColor: UIColor = .clear) {
        self.init()

        colorAttachments[0].texture = sampleTex
        colorAttachments[0].resolveTexture = texture
        colorAttachments[0].loadAction = .clear
        colorAttachments[0].storeAction = .multisampleResolve
        colorAttachments[0].clearColor = MTLClearColor(color: clearColor)
    }
}
