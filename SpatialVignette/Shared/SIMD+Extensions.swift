//
//  SIMD+Extensions.swift
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 11/18/25.
//

import simd

extension simd_float4x4 {
    /// Column-major 16-element array
    var flattened: [Float] {
        let c0 = columns.0
        let c1 = columns.1
        let c2 = columns.2
        let c3 = columns.3
        return [
            c0.x, c0.y, c0.z, c0.w,
            c1.x, c1.y, c1.z, c1.w,
            c2.x, c2.y, c2.z, c2.w,
            c3.x, c3.y, c3.z, c3.w
        ]
    }

    init(flattened values: [Float]) {
        precondition(values.count == 16)
        self.init(
            SIMD4(values[0],  values[1],  values[2],  values[3]),
            SIMD4(values[4],  values[5],  values[6],  values[7]),
            SIMD4(values[8],  values[9],  values[10], values[11]),
            SIMD4(values[12], values[13], values[14], values[15])
        )
    }
}

extension SIMD3 where Scalar == Float {
    var array: [Float] { [x, y, z] }

    init(array: [Float]) {
        precondition(array.count == 3)
        self.init(array[0], array[1], array[2])
    }
}

extension simd_float4x4: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var m = matrix_identity_float4x4
        
        for row in 0..<4 {
            for col in 0..<4 {
                m[row][col] = try container.decode(Float.self)
            }
        }
        
        self = m
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        
        for row in 0..<4 {
            for col in 0..<4 {
                try container.encode(self[row][col])
            }
        }
    }
}
