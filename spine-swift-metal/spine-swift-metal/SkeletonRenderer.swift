//
//  SkeletonRenderer.swift
//
//  Created by Lukasz Domaradzki on 12/11/2018.
//  Copyright © 2018 Lukasz Domaradzki. All rights reserved.
//

import SpineC
import Metal
import MetalKit

final public class SkeletonRenderer {
    struct SpineVertex {
        let position: float4
        let color: float4
        let texCoord: float2
    }
    
    public lazy var metalLayer: CAMetalLayer = {
        let metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.backgroundColor = UIColor.clear.cgColor
        metalLayer.contentsScale = UIScreen.main.scale
        return metalLayer
    }()
    
    // metal
    var device: MTLDevice = MTLCreateSystemDefaultDevice()!
    var texture: MTLTexture?
    var sampleTex: MTLTexture?
    var textureDescriptor = MTLTextureDescriptor()
    let pipelineStateDescriptor = MTLRenderPipelineDescriptor(vertex: .basicVertex, fragment: .basicFragment)
    lazy var pipelineState: MTLRenderPipelineState? = { try? device.makeRenderPipelineState(descriptor: pipelineStateDescriptor) }()
    lazy var commandQueue: MTLCommandQueue? = { device.makeCommandQueue() }()
    
    var vertexData: [SpineVertex] = []
    var vertexBuffer: MTLBuffer!
    var indexData: [UInt16] = []
    var indexBuffer: MTLBuffer!
    lazy var timer: CADisplayLink = { CADisplayLink(target: self, selector: #selector(draw)) }()
    
    // spine
    var skeleton: UnsafeMutablePointer<spSkeleton>?
    var rootBone: UnsafeMutablePointer<spBone>?
    var atlas: UnsafeMutablePointer<spAtlas>
    var animationState: UnsafeMutablePointer<spAnimationState>?
    var quadTriangles: UnsafeMutablePointer<UInt16> = {
        let triangles = UnsafeMutablePointer<UInt16>.allocate(capacity: 6)
        triangles[0] = 0
        triangles[1] = 1
        triangles[2] = 2
        triangles[3] = 2
        triangles[4] = 3
        triangles[5] = 0
        return triangles
    }()
    
    public init?(filePath: String, atlasPath: String, scale: Float) {
        let atlasPathPointer = UnsafePointer<Int8>(strdup(atlasPath))
        let filePathPointer = UnsafePointer<Int8>(strdup(filePath))
        
        texture = try? MTKTextureLoader(device: device).newTexture(URL: URL(fileURLWithPath: atlasPath.replacingOccurrences(of: "atlas", with: "png")), options: [.origin: MTKTextureLoader.Origin.bottomLeft])
        textureDescriptor.textureType = .type2DMultisample
        
        textureDescriptor.sampleCount = 4
        textureDescriptor.pixelFormat = .bgra8Unorm
        textureDescriptor.usage = .renderTarget
        textureDescriptor.storageMode = .private
        
        
        atlas = spAtlas_createFromFile(atlasPathPointer, UnsafeMutableRawPointer(bitPattern: 0))
        let json = spSkeletonJson_create(atlas)
        json?.pointee.scale = scale
        let skeletonData = spSkeletonJson_readSkeletonDataFile(json, filePathPointer)
        spSkeletonJson_dispose(json)
        guard let data = skeletonData else {
            return nil
        }
        
        initialize(data: data)
        timer.add(to: .main, forMode: .default)
    }
    
    private func initialize(data: UnsafeMutablePointer<spSkeletonData>) {
        skeleton = spSkeleton_create(data)
        let bb = boundingBox()
        let width = Int(bb.width)//Int(data.pointee.width)
        let height = Int(bb.height)//Int(data.pointee.height)
        metalLayer.frame = CGRect(x: 50.0, y: 100.0, width: Double(width), height: Double(height))
        metalLayer.drawableSize = CGSize(width: Double(width) * 2.0, height: Double(height) * 2.0)
        textureDescriptor.width = width * 2
        textureDescriptor.height = height * 2
        sampleTex = device.makeTexture(descriptor: textureDescriptor)
        let animationStateData = spAnimationStateData_create(skeleton?.pointee.data)
        animationState = spAnimationState_create(animationStateData)
        spSkeleton_setSkinByName(skeleton, UnsafePointer<Int8>(strdup("goblin")))
        let animation = spSkeletonData_findAnimation(skeleton?.pointee.data, UnsafePointer<Int8>(strdup("walk")))
        spAnimationState_setAnimation(animationState, 0, animation, 1)
    }
    
    @objc private func draw() {
        spSkeleton_update(skeleton, 0.01)
        spAnimationState_update(animationState, 0.01)
        spAnimationState_apply(animationState, skeleton)
        spSkeleton_updateWorldTransform(skeleton)
        calculate()
        
        guard let drawable = metalLayer.nextDrawable(),
            let pipelineState = pipelineState else { return }
        
        let renderPassDescriptor = MTLRenderPassDescriptor(texture: drawable.texture, sampleTex: sampleTex!)
        let commandBuffer = commandQueue?.makeCommandBuffer()!
        
        let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        renderEncoder?.setRenderPipelineState(pipelineState)
        renderEncoder?.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder?.setFragmentTexture(texture, index: 0)
        renderEncoder?.drawIndexedPrimitives(type: .triangle, indexCount: indexBuffer.length / MemoryLayout.size(ofValue: indexData[0]), indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)
        renderEncoder?.endEncoding()
        
        commandBuffer?.present(drawable)
        commandBuffer?.commit()
    }
    
    private func calculate() {
        vertexData = []
        indexData = []
        var uvs: [Float] = []
        var vertices: UnsafeMutablePointer<Float> = UnsafeMutablePointer<Float>.allocate(capacity: 1000)
        var verticesCount: Int32 = 0
        var triangles: UnsafeMutablePointer<UInt16> = UnsafeMutablePointer<UInt16>.allocate(capacity: 0)
        var trianglesCount: Int32 = 0
        var r: Float = 0
        var g: Float = 1
        var b: Float = 1
        var a: Float = 1
        var srcBlend: MTLBlendFactor
        var dstBlend: MTLBlendFactor
        var trianglesCountOffset: UInt16 = 0
        
        let slotsCount = Int(skeleton?.pointee.slotsCount ?? 0)
        for i in 0...slotsCount {
            var name: String? = nil
            if let attName = skeleton?.pointee.drawOrder[i]?.pointee.data.pointee.attachmentName {
                name = String(cString: attName)
            }
            
            guard let slot = skeleton?.pointee.drawOrder[i],
                let attachment = slot.pointee.attachment else {
                continue
            }
            
            switch attachment.pointee.type {
            case SP_ATTACHMENT_REGION:
                let regionAttachment: UnsafeMutablePointer<spRegionAttachment> = UnsafeMutablePointer<spRegionAttachment>(OpaquePointer(attachment))
                spRegionAttachment_computeWorldVertices(regionAttachment, slot.pointee.bone, vertices, 0, 2)
                uvs = {
                    let uvTuple = regionAttachment.pointee.uvs
                    return [uvTuple.0, uvTuple.1, uvTuple.2, uvTuple.3, uvTuple.4, uvTuple.5, uvTuple.6, uvTuple.7]
                }()
                verticesCount = 8
                triangles = quadTriangles
                trianglesCount = 6
                r = regionAttachment.pointee.color.r
                g = regionAttachment.pointee.color.g
                b = regionAttachment.pointee.color.b
                a = regionAttachment.pointee.color.a
                break
            case SP_ATTACHMENT_MESH:
                let meshAttachment: UnsafeMutablePointer<spMeshAttachment> = UnsafeMutablePointer<spMeshAttachment>(OpaquePointer(attachment))
                spVertexAttachment_computeWorldVertices(&meshAttachment.pointee.super, slot, 0, meshAttachment.pointee.super.worldVerticesLength, vertices, 0, 2)
                verticesCount = meshAttachment.pointee.super.worldVerticesLength
                uvs = Array(UnsafeBufferPointer(start: meshAttachment.pointee.uvs, count: Int(verticesCount)))
                triangles = meshAttachment.pointee.triangles
                trianglesCount = meshAttachment.pointee.trianglesCount
                r = meshAttachment.pointee.color.r
                g = meshAttachment.pointee.color.g
                b = meshAttachment.pointee.color.b
                a = meshAttachment.pointee.color.a
                
                break
            case SP_ATTACHMENT_CLIPPING:
                continue
            default:
                continue
            }

            switch slot.pointee.data.pointee.blendMode {
            case SP_BLEND_MODE_ADDITIVE:
                srcBlend = .one
                dstBlend = .one
            case SP_BLEND_MODE_MULTIPLY:
                srcBlend = .destinationColor
                dstBlend = .oneMinusSourceAlpha
            case SP_BLEND_MODE_SCREEN:
                srcBlend = .one
                dstBlend = .oneMinusSourceColor
            default:
                srcBlend = .one
                dstBlend = .oneMinusSourceAlpha
            }
            
            var newVertexData: [SpineVertex] = []
            if trianglesCount > 0 {
                for i in 0...Int(verticesCount) where i*2 < Int(verticesCount) {
                    let position = float4(vertices[i * 2]/Float(metalLayer.frame.width), vertices[i * 2 + 1]/Float(metalLayer.frame.height) - 1, 0, 1)
                    let color = float4(r, g, b, a)
                    let textCoord = float2(uvs[i * 2], 1 - uvs[i * 2 + 1])
                    let vertex = SpineVertex(position: position, color: color, texCoord: textCoord)
                    newVertexData.append(vertex)
                }
                vertexData.append(contentsOf: newVertexData)
                
                for j in 0...Int(trianglesCount) where j*3 < Int(trianglesCount) {
                    let newIndexData = [triangles[j*3], triangles[j*3+1], triangles[j*3+2]].map { $0.addingReportingOverflow(trianglesCountOffset).partialValue  }
                    indexData.append(contentsOf: newIndexData)
                }
            }
            
            trianglesCountOffset += UInt16(newVertexData.count)
        }
        
        let dataSize = vertexData.count * MemoryLayout.stride(ofValue: vertexData[0])
        vertexBuffer = device.makeBuffer(bytes: vertexData, length: dataSize, options: [])
        
        let indexSize = indexData.count * MemoryLayout.stride(ofValue: indexData[0])
        indexBuffer = device.makeBuffer(bytes: indexData, length: indexSize, options: [])
    }
    
    func boundingBox() -> CGRect {
        var minX = Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude
        var maxX = Float.leastNormalMagnitude
        var maxY = Float.leastNormalMagnitude
        var scaleX = Float(UIScreen.main.scale)
        var scaleY = Float(UIScreen.main.scale)
        var vertices: UnsafeMutablePointer<Float> = UnsafeMutablePointer<Float>.allocate(capacity: 1000)
        
        for i in 0...Int(skeleton?.pointee.slotsCount ?? 0) {
            guard let slot = skeleton?.pointee.slots[i],
                let attachment = slot.pointee.attachment else {
                continue
            }
            
            var verticesCount: Int
            switch attachment.pointee.type {
            case SP_ATTACHMENT_REGION:
                let regionAttachment: UnsafeMutablePointer<spRegionAttachment> = UnsafeMutablePointer<spRegionAttachment>(OpaquePointer(attachment))
                spRegionAttachment_computeWorldVertices(regionAttachment, slot.pointee.bone, vertices, 0, 2)
                verticesCount = 8
            case SP_ATTACHMENT_MESH:
                let meshAttachment: UnsafeMutablePointer<spMeshAttachment> = UnsafeMutablePointer<spMeshAttachment>(OpaquePointer(attachment))
                spVertexAttachment_computeWorldVertices(&meshAttachment.pointee.super, slot, 0, meshAttachment.pointee.super.worldVerticesLength, vertices, 0, 2)
                verticesCount = Int(meshAttachment.pointee.super.worldVerticesLength)
            default:
                continue
            }
            
            for ii in 0...verticesCount where (ii % 2) == 0 {
                let x = vertices[ii]// * scaleX
                let y = vertices[ii+1]// * scaleY
                minX = fminf(minX, x)
                minY = fminf(minY, y)
                maxX = fmaxf(maxX, x)
                maxY = fmaxf(maxY, y)
            }
        }
        
        return CGRect(x: Double(minX), y: Double(minY), width: Double(maxX - minX), height: Double(maxY - minY))
    }
    
//    - (CGRect) boundingBox {
//    float minX = FLT_MAX, minY = FLT_MAX, maxX = FLT_MIN, maxY = FLT_MIN;
//    float scaleX = self.scaleX, scaleY = self.scaleY;
//    for (int i = 0; i < _skeleton->slotsCount; ++i) {
//    spSlot* slot = _skeleton->slots[i];
//    if (!slot->attachment) continue;
//    int verticesCount;
//    if (slot->attachment->type == SP_ATTACHMENT_REGION) {
//    spRegionAttachment* attachment = (spRegionAttachment*)slot->attachment;
//    spRegionAttachment_computeWorldVertices(attachment, slot->bone, _worldVertices, 0, 2);
//    verticesCount = 8;
//    } else if (slot->attachment->type == SP_ATTACHMENT_MESH) {
//    spMeshAttachment* mesh = (spMeshAttachment*)slot->attachment;
//    spVertexAttachment_computeWorldVertices(SUPER(mesh), slot, 0, mesh->super.worldVerticesLength, _worldVertices, 0, 2);
//
//    verticesCount = mesh->super.worldVerticesLength;
//    } else
//    continue;
//    for (int ii = 0; ii < verticesCount; ii += 2) {
//    float x = _worldVertices[ii] * scaleX, y = _worldVertices[ii + 1] * scaleY;
//    minX = fmin(minX, x);
//    minY = fmin(minY, y);
//    maxX = fmax(maxX, x);
//    maxY = fmax(maxY, y);
//    }
//    }
//    minX = self.position.x + minX;
//    minY = self.position.y + minY;
//    maxX = self.position.x + maxX;
//    maxY = self.position.y + maxY;
//    return CGRectMake(minX, minY, maxX - minX, maxY - minY);
//    }
}
