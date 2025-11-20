//
//  VignetteData.swift
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 9/4/25.
//

import Foundation
import simd
import CoreLocation

// The codable data for a vignette

public struct VignetteData: Codable {
    public var id: UUID
    public var createdAt: Date

    public var paths: VignettePaths
    public var camera: CameraBlock
    public var capture: CaptureBlock
    
    public var samMaskThreshold: Float?
    
    // Abstraction results
    var abstractionResults: AbstractionBlock?
}

public struct VignettePaths: Codable {
    public var rgb: String                   // "rgb.heic"
    public var depth: String                 // "depth16.png"
    public var confidence: String?
    public var points: String?               // "points.ply"
    public var samMask: String?
    public var samSubjectCrop: String?
    // public var labels: String?               // "labels.u32"
}

public struct CameraBlock: Codable {
    public var resolution: Resolution
    public var intrinsics: [Float] // len=9, row-major
    public var extrinsics: [[Float]] // 4x4 row-major for portability
}

public struct Resolution: Codable {
    public var width: Int
    public var height: Int
}

public struct CaptureBlock: Codable {
    public var deviceModel: String
    public var gps: GPS?
    public var note: String?
}
public struct GPS: Codable {
    public var lat: Double
    public var lon: Double
    public var altitude: Double?
    public var address: String?
    public init(lat: Double, lon: Double, altitude: Double? = nil, address: String? = nil) {
        self.lat = lat
        self.lon = lon
        self.altitude = altitude
        self.address = address
    }
    
    public init(location: CLLocation, address: String? = nil) {
        self.lat = location.coordinate.latitude
        self.lon = location.coordinate.longitude
        self.altitude = location.altitude
        self.address = address
    }
    
    public func toCLLocation() -> CLLocation {
        CLLocation(latitude: lat, longitude: lon)
    }
}


struct AbstractionBlock: Codable {
    
    // 1. Server-Generated Abstractions (Planes, Cylinders, Axes)
    // This is the core output from your Python pipeline.
    var serverNodes: [VignetteNode]
    
    // 2. Client-Generated Nodes (User Sketches, Annotations)
    // These are created by the Apple Pencil on the iPad.
    var userNodes: [VignetteNode]?
    
    // Optional: Global metadata about the overall abstraction process
    var globalParameters: [String: Float]?
    
    var allNodes: [VignetteNode] {
        var nodes = serverNodes
        if let user = userNodes {
            nodes.append(contentsOf: user)
        }
        return nodes
    }
}

/*
// Optional/future
public struct StyleBlock: Codable {
    //public var decimation: Float?            // 0..1
    //public var splatSize: Float?             // px-ish
    //public var edge: Float?                  // 0..1 edge emphasis
}

public struct SemanticsBlock: Codable {
    public var title: String?
    public var tags: [String]?
    public var summary: String?
}

// Minimal stub; you’ll flesh this out later (e.g., caption, embedding path)
public struct EntityStub: Codable {
    public var id: UInt32
    public var label: String?
    public var maskPath: String?             // e.g., "entities/1/mask.png"
    public var embeddingPath: String?        // e.g., "entities/1/embedding.f32"
    public var embeddingDim: Int?
}
*/
