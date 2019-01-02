//
//  ProgramFunction.swift
//  MetalTest
//
//  Created by Lukasz Domaradzki on 26/12/2018.
//  Copyright © 2018 Lukasz Domaradzki. All rights reserved.
//

import Metal

enum ProgramFunction: String {
    case basicFragment
    case basicVertex
    
    func shaderFunction(device: MTLDevice) -> MTLFunction? {
        return device.makeDefaultLibrary()?.makeFunction(name: self.rawValue)
    
//        return device.makeLibrary(source: <#T##String#>, options: <#T##MTLCompileOptions?#>).makeFunction(name: self.rawValue)
    }
}
