//
//  Scene.swift
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 11/18/25.
//

import Observation
import Foundation
import simd

struct Vignette: Identifiable, Codable {
    // Composition State
    let id: UUID // Uses data.id
    var name: String // User-defined name for the scene (e.g., "Tree Bark Study")
    var isCollapsed: Bool = false
    var transform: simd_float4x4 = matrix_identity_float4x4
    
    // Embedded Capture/Processing Data
    var data: VignetteData
    
    
    
    // Convenience Initializer
    init(name: String, data: VignetteData) {
        self.id = data.id
        self.name = name
        self.data = data
    }
    
    // Convenience Accessors for the Scene Tree
    var rawNodes: [VignetteNode] {
        data.abstractionResults?.allNodes.filter {
            if case .pointCloud = $0.geometryType { return true } else { return false }
        } ?? []
    }
    var abstractionNodes: [VignetteNode] {
        data.abstractionResults?.allNodes.filter {
            if case .pointCloud = $0.geometryType { return false } else { return true }
        } ?? []
    }
}

@Observable
class VignetteScene: Codable {
    
    var sceneID: UUID = UUID()
    var vignettes: [Vignette] = []
    var selectedVignetteID: UUID?
    
    // Standard Observable/Codable implementation
    init() { }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sceneID = try container.decode(UUID.self, forKey: .sceneID)
        vignettes = try container.decode([Vignette].self, forKey: .vignettes)
        selectedVignetteID = try container.decodeIfPresent(UUID.self, forKey: .selectedVignetteID)
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sceneID, forKey: .sceneID)
        try container.encode(vignettes, forKey: .vignettes)
        try container.encodeIfPresent(selectedVignetteID, forKey: .selectedVignetteID)
    }
    private enum CodingKeys: String, CodingKey {
        case sceneID, vignettes, selectedVignetteID
    }
    
    // Logic to toggle node visibility
    func toggleNodeVisibility(vignetteID: UUID, nodeID: UUID) {
        guard let vignetteIndex = vignettes.firstIndex(where: { $0.id == vignetteID }),
              let abstractionBlock = vignettes[vignetteIndex].data.abstractionResults else {
            print("Error: Vignette or AbstractionBlock not found.")
            return
        }
        
        // Find the node in the serverNodes array
        if let serverIndex = abstractionBlock.serverNodes.firstIndex(where: { $0.id == nodeID }) {
            vignettes[vignetteIndex].data.abstractionResults!.serverNodes[serverIndex].isVisible.toggle()
            print("Toggling Server Node: \(vignettes[vignetteIndex].data.abstractionResults!.serverNodes[serverIndex].name)")
            return
        }
        
        // Find the node in the userNodes array
        if let userNodes = abstractionBlock.userNodes,
           let userIndex = userNodes.firstIndex(where: { $0.id == nodeID }) {
            vignettes[vignetteIndex].data.abstractionResults!.userNodes![userIndex].isVisible.toggle()
            print("Toggling User Node: \(vignettes[vignetteIndex].data.abstractionResults!.userNodes![userIndex].name)")
            return
        }
    }
    
    // MARK: - Persistence Methods (Stubs)
    func saveScene() {
        do {
            let data = try JSONEncoder().encode(self)
            print("Scene saved successfully. Data size: \(data.count) bytes.")
        } catch {
            print("Error saving scene: \(error)")
        }
    }
    static func loadScene() -> VignetteScene {
        print("Loading scene from storage... (Using mock data)")
        return VignetteScene()
    }
}
