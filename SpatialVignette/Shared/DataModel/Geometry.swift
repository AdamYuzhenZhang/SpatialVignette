//
//  Geometry.swift
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 11/18/25.
//

import Foundation
import simd

// MARK: - The Container (The "Atom" of your Scene Tree)
struct VignetteNode: Identifiable, Codable {
    let id: UUID          // Crucial for syncing edits back to Python
    var name: String      // e.g., "Floor Plane", "Edge Contour"
    var isVisible: Bool
    
    // The Payload: specific geometry data
    let geometryType: GeometryType
    
    // Design Parameters (for future bi-directional editing)
    // e.g. ["curvature_threshold": 0.5]
    var parameters: [String: Float]?
}

// MARK: - The Geometry Enum
// This is the "Geometry-Oriented" definition you asked for.
enum GeometryType: Codable {
    
    // 1. The Raw Capture
    case pointCloud(PointData)
    
    // 2. Linear Abstractions (Edges, Flow lines)
    case polyline(PolylineData)
    
    // 3. Mathematical Primitives (Planes, Cylinders)
    // "Primitive" is better than "Mesh" here because it implies
    // it can be mathematically adjusted (radius, width) before meshing.
    case primitive(PrimitiveData)
    
    // 4. Future Proofing
    case mesh(MeshData) // For general arbitrary meshes (e.g. Poisson Recon)
    case gaussianSplat(SplatData) // For future standard splats
}

// MARK: - Detailed Data Blocks

struct PointData: Codable {
    // In real app, use Base64 encoded strings for large arrays
    let points: [SIMD3<Float>]
    let colors: [SIMD3<Float>]?
    let normals: [SIMD3<Float>]?
}

struct PolylineData: Codable {
    let points: [SIMD3<Float>]
    let isClosed: Bool
    let thickness: Float
    let type: PolylineType // .edge, .flow, .contour
}

enum PolylineType: String, Codable {
    case edge, flow, contour, sketch
}

struct PrimitiveData: Codable {
    let type: PrimitiveShape
    let transform: simd_float4x4
    let dimensions: SIMD3<Float>
    let color: SIMD3<Float>?

    enum CodingKeys: String, CodingKey {
        case type
        case transform
        case dimensions
        case color
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(type, forKey: .type)
        try container.encode(transform.flattened, forKey: .transform)
        try container.encode(dimensions.array, forKey: .dimensions)

        if let color = color {
            try container.encode(color.array, forKey: .color)
        } else {
            try container.encodeNil(forKey: .color)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        type = try container.decode(PrimitiveShape.self, forKey: .type)

        let tArray = try container.decode([Float].self, forKey: .transform)
        transform = simd_float4x4(flattened: tArray)

        let dArray = try container.decode([Float].self, forKey: .dimensions)
        dimensions = SIMD3<Float>(array: dArray)

        if let cArray = try container.decodeIfPresent([Float].self, forKey: .color) {
            color = SIMD3<Float>(array: cArray)
        } else {
            color = nil
        }
    }
}

enum PrimitiveShape: String, Codable {
    case plane, cylinder, sphere, box
}

// Placeholders
struct MeshData: Codable { /* vertices, indices, uvs */ }
struct SplatData: Codable { /* sh_coeffs, scales, etc */ }
