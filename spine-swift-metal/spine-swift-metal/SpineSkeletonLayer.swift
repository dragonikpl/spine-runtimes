//
//  SpineSkeletonLayer.swift
//  SpineSwiftMetal
//
//  Created by Lukasz Domaradzki on 03/01/2019.
//

import Foundation
import Metal
import MetalKit

public final class SpineSkeletonLayer: CAMetalLayer {
    public var skeleton: SpineSkeleton
    
    private var texture: MTLTexture?
    private lazy var sampleTex: MTLTexture? = {
       return device?.makeTexture(descriptor: textureDescriptor)
    }()
   private lazy  var textureDescriptor: MTLTextureDescriptor = {
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.textureType = .type2DMultisample
        textureDescriptor.sampleCount = 4
        textureDescriptor.pixelFormat = .bgra8Unorm
        textureDescriptor.usage = .renderTarget
        textureDescriptor.storageMode = .private
        textureDescriptor.width = Int(frame.width * UIScreen.main.scale)
        textureDescriptor.height = Int(frame.height * UIScreen.main.scale)
    
        return textureDescriptor
    }()
    private let pipelineStateDescriptor = MTLRenderPipelineDescriptor(vertex: .basicVertex, fragment: .basicFragment)
    private lazy var pipelineState: MTLRenderPipelineState? = {
        guard let device = device else { return nil }
        return try? device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
    }()
    private lazy var commandQueue: MTLCommandQueue? = { device?.makeCommandQueue() }()
    
    private var vertexBuffer: MTLBuffer!
    private var indexBuffer: MTLBuffer!
    private var dataSize: Int = 0
    private var indexSize: Int = 0
    private lazy var timer: CADisplayLink = { CADisplayLink(target: self, selector: #selector(drawMetal)) }()
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public init(skeletonFilePath: URL, atlasFilePath: URL, scale: Float, frame: CGRect) {
        skeleton = SpineSkeleton(filePath: skeletonFilePath.path, atlasPath: atlasFilePath.path, scale: scale, renderSize: frame.size)
        
        
        skeleton.setPosition(position: CGPoint(x: 0, y: -frame.size.height))
        
        super.init()
        self.frame = frame
        self.drawableSize = CGSize(width: frame.width * UIScreen.main.scale, height: frame.height * UIScreen.main.scale)
        pixelFormat = .bgra8Unorm
        backgroundColor = UIColor.clear.cgColor
        contentsScale = UIScreen.main.scale
        
        if let texturePath = skeleton.texturePath(at: 0),
            let device = device {
            texture = try? MTKTextureLoader(device: device).newTexture(URL: URL(fileURLWithPath: texturePath), options: [.origin: MTKTextureLoader.Origin.bottomLeft])
        }
        
        timer.preferredFramesPerSecond = 60
        timer.add(to: .main, forMode: .default)
    }
    
    // MARK: - Calculations
    
    func calculateSkeleton() -> Int {
        let framerate: Float = 1.0/60.0
        skeleton.update(delta: framerate)
        let (vertexData, indexData) = skeleton.draw(lastVertexCount: dataSize, lastIndexCount: indexSize)
        dataSize = vertexData.count * MemoryLayout.stride(ofValue: vertexData[0])
        if vertexBuffer == nil || vertexBuffer.length != dataSize {
            vertexBuffer = device?.makeBuffer(length: dataSize, options: [.cpuCacheModeWriteCombined])
        }
        memcpy(vertexBuffer.contents(), vertexData, dataSize)
        
        indexSize = indexData.count * MemoryLayout.stride(ofValue: indexData[0])
        if indexBuffer == nil || indexBuffer.length != indexSize {
            indexBuffer = device?.makeBuffer(length: indexSize, options: [.cpuCacheModeWriteCombined])
        }
        memcpy(indexBuffer.contents(), indexData, indexSize)

        return indexBuffer.length / MemoryLayout.size(ofValue: indexData[0])
    }
    
    @objc func drawMetal() {
        let indexCount = calculateSkeleton()
        
        guard let drawable = nextDrawable(),
            let pipelineState = pipelineState,
            let sampleTex = sampleTex,
            let commandBuffer = commandQueue?.makeCommandBuffer() else { return }
        
        let renderPassDescriptor = MTLRenderPassDescriptor(texture: drawable.texture, sampleTex: sampleTex, clearColor: .clear)
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        renderEncoder?.setRenderPipelineState(pipelineState)
        renderEncoder?.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder?.setFragmentTexture(texture, index: 0)
        renderEncoder?.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)
        renderEncoder?.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
