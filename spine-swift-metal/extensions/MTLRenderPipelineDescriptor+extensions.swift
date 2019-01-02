//
//  MTLRenderPipelineDescriptor+extensions.swift
//  MetalTest
//
//  Created by Lukasz Domaradzki on 26/12/2018.
//  Copyright © 2018 Lukasz Domaradzki. All rights reserved.
//

import Metal

extension MTLRenderPipelineDescriptor {
    convenience init(vertex: ProgramFunction, fragment: ProgramFunction) {
        self.init()
        
        guard let device: MTLDevice = MTLCreateSystemDefaultDevice() else {
            return
        }
        
        vertexFunction = vertex.shaderFunction(device: device)
        fragmentFunction = fragment.shaderFunction(device: device)
        sampleCount = 4
        colorAttachments[0].pixelFormat = .bgra8Unorm
        colorAttachments[0].isBlendingEnabled = true
        colorAttachments[0].rgbBlendOperation = .add
        colorAttachments[0].alphaBlendOperation = .add
        colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
    }
}
