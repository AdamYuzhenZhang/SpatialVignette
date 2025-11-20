//
//  GeometryParser.swift
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 11/18/25.
//

import RealityKit
import Foundation

class VignetteParser {
    
    func generateEntity(from node: VignetteNode) -> Entity {
        let rootEntity = Entity()
        rootEntity.name = node.name
        
        // Store the Python ID on the entity for interaction later
        rootEntity.components.set(VignetteIDComponent(id: node.id))
        
        switch node.geometryType {
            
        case .pointCloud(let data):
            // Call your point cloud shader logic here
            //let cloud = createPointCloud(points: data.points, colors: data.colors)
            //rootEntity.addChild(cloud)
            break
            
        case .polyline(let data):
            // Create a MeshResource from points
            //let mesh = MeshResource.generatePath(data.points, radius: data.thickness)
            //let mat = UnlitMaterial(color: .white)
            //rootEntity.addChild(ModelEntity(mesh: mesh, materials: [mat]))
            break
            
        case .primitive(let data):
            let primitiveEnt = createPrimitive(data)
            rootEntity.addChild(primitiveEnt)
            
        case .mesh(let data):
            break // Implement standard mesh loading
            
        case .gaussianSplat(let data):
            break // Future implementation
        }
        
        rootEntity.isEnabled = node.isVisible
        return rootEntity
    }
    
    // Example of the Primitive Logic
    private func createPrimitive(_ data: PrimitiveData) -> ModelEntity {
        let mesh: MeshResource
        
        switch data.type {
        case .plane:
            // Mapping "Dimensions" to Plane geometry
            mesh = MeshResource.generatePlane(width: data.dimensions.x, depth: data.dimensions.y)
        case .cylinder:
            mesh = MeshResource.generateBox(size: data.dimensions) // Placeholder
        case .sphere:
            mesh = MeshResource.generateSphere(radius: data.dimensions.x)
        case .box:
            mesh = MeshResource.generateBox(size: data.dimensions)
        }
        
        // Create semi-transparent abstract material
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .cyan.withAlphaComponent(0.5))
        material.blending = .transparent(opacity: 0.5)
        material.roughness = 0.0
        
        let entity = ModelEntity(mesh: mesh, materials: [material])
        
        // Apply the Transform Matrix directly (Easy!)
        entity.transform.matrix = data.transform
        
        return entity
    }
}

// Helper Component to identify entities in the 3D scene
struct VignetteIDComponent: Component {
    var id: UUID
}
