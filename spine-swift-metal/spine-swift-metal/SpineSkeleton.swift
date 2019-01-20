//
//  SpineSkeleton.swift
//  SpineSwiftMetal
//
//  Created by Lukasz Domaradzki on 03/01/2019.
//

import SpineC
import simd

class SpineSkeleton {
    let renderSize: CGSize
    var atlas: UnsafeMutablePointer<spAtlas>
    var skeleton: UnsafeMutablePointer<spSkeleton>?
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
    
    init(filePath: String, atlasPath: String, scale: Float, renderSize: CGSize) {
        self.renderSize = renderSize
        
        let atlasPathPointer = UnsafePointer<Int8>(strdup(atlasPath))
        let filePathPointer = UnsafePointer<Int8>(strdup(filePath))
        
        atlas = spAtlas_createFromFile(atlasPathPointer, UnsafeMutableRawPointer(bitPattern: 0))
        let data = skeletonData(filePathPointer: filePathPointer, scale: scale)
        skeleton = spSkeleton_create(data)
        
        let animationStateData = spAnimationStateData_create(skeleton?.pointee.data)
        animationState = spAnimationState_create(animationStateData)
    }
    
    private func skeletonData(filePathPointer: UnsafePointer<Int8>?, scale: Float) -> UnsafeMutablePointer<spSkeletonData>? {
        let json = spSkeletonJson_create(atlas)
        json?.pointee.scale = scale
        let data = spSkeletonJson_readSkeletonDataFile(json, filePathPointer)
        spSkeletonJson_dispose(json)
        return data
    }
    
    deinit {
        spSkeletonData_dispose(skeleton?.pointee.data)
        spAtlas_dispose(atlas)
        spSkeleton_dispose(skeleton)
    }

    func texturePath(at index: Int) -> String? {
        let path = atlas.pointee.pages[index].rendererObject
        guard let cstring = UnsafePointer<CChar>(OpaquePointer(path)) else {
            return nil
        }
    
        return String(cString: cstring)
    }
    
    func setSkin(name: String?) {
        spSkeleton_setSkinByName(skeleton, UnsafePointer<Int8>(strdup(name)))
    }
    
    func setAnimation(name: String, track: Int, loop: Bool) {
        let animation = spSkeletonData_findAnimation(skeleton?.pointee.data, UnsafePointer<Int8>(strdup(name)))
        spAnimationState_setAnimation(animationState, Int32(track), animation, Int32(loop ? 1 : 0))
    }
    
    func setPosition(position: CGPoint) {
        skeleton?.pointee.x = Float(position.x)
        skeleton?.pointee.y = Float(position.y)
    }
    
    func update(delta: Float) {
        spSkeleton_update(skeleton, delta)
        spAnimationState_update(animationState, delta)
        spAnimationState_apply(animationState, skeleton)
        spSkeleton_updateWorldTransform(skeleton)
    }
    
    func draw(vertexData: inout [SpineVertex], indexData: inout [UInt16]) {
        var uvs: [Float] = []
        let vertices: UnsafeMutablePointer<Float> = UnsafeMutablePointer<Float>.allocate(capacity: 1000)
        var verticesCount: Int32 = 0
        var triangles: UnsafeMutablePointer<UInt16>?
        var trianglesCount: Int32 = 0
        var r: Float = 1
        var g: Float = 1
        var b: Float = 1
        var a: Float = 1
        var srcBlend: MTLBlendFactor
        var dstBlend: MTLBlendFactor
        var trianglesCountOffset: UInt16 = 0
        
        let slotsCount = Int(skeleton?.pointee.slotsCount ?? 0)
        for i in 0...(slotsCount-1) {
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
                    let position = float4(vertices[i * 2] / Float(renderSize.width), vertices[i * 2 + 1] / Float(renderSize.height), 0, 1)
                    let color = float4(r, g, b, a)
                    let textCoord = float2(uvs[i * 2], 1 - uvs[i * 2 + 1])
                    let vertex = SpineVertex(position: position, color: color, texCoord: textCoord)
                    newVertexData.append(vertex)
                }
                vertexData.append(contentsOf: newVertexData)
                
                for j in 0...Int(trianglesCount) where j*3 < Int(trianglesCount) {
                    let newIndexData = [triangles?[j*3], triangles?[j*3+1], triangles?[j*3+2]]
                        .map { $0?.addingReportingOverflow(trianglesCountOffset).partialValue }
                        .compactMap { $0 }
                    indexData.append(contentsOf: newIndexData)
                }
            }
            
            trianglesCountOffset += UInt16(newVertexData.count)
        }
    }
}
