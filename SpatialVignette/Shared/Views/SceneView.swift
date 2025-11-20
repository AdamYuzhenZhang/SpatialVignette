//
//  SceneView.swift
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 11/19/25.
//

import SwiftUI

// Mock types for demonstration purposes
struct CameraItem: Identifiable {
    let id = UUID()
    let name: String
    let imageName: String
}

// Tool items for the new right sidebar
struct ToolItem: Identifiable {
    let id = UUID()
    let name: String
    let systemImage: String
}

struct SceneView: View {
    @Environment(VignetteScene.self) private var scene
    
    private let mockCameras: [CameraItem] = [
            CameraItem(name: "Vignette 1", imageName: "photo.fill"),
            CameraItem(name: "Vignette 2", imageName: "video.fill"),
            CameraItem(name: "Vignette 3", imageName: "arkit"),
            CameraItem(name: "Vignette 4", imageName: "square.stack.3d.up.fill")
        ]
        
        private let mockTools: [ToolItem] = [
            ToolItem(name: "Translate", systemImage: "arrow.up.and.down.and.arrow.left.and.right"),
            ToolItem(name: "Rotate", systemImage: "arrow.triangle.2.circlepath"),
            ToolItem(name: "Scale", systemImage: "arrow.up.left.and.arrow.down.right"),
            ToolItem(name: "Measure", systemImage: "ruler"),
            ToolItem(name: "Light", systemImage: "lightbulb.fill")
        ]
    
    var body: some View {
        VStack(spacing: 0) {
                    
                    // ⭐️ Core Composer Area: Scene Tree + Viewer + Tools
                    HStack(spacing: 0) {
                        
                        // Left: Scene Hierarchy (Scene Tree)
                        SceneTreeView(scene: scene)
                            .frame(width: 300)
                            .background(Color(.systemGray6)) // Lighter background for sidebar
                            .border(Color(.systemGray5), width: 0.5)
                        
                        // Center-Right: RealityKit Viewer and Tools Sidebar
                        HStack(spacing: 0) {
                            
                            // Center: RealityKit Composer Space
                            RealityKitViewerStub(scene: scene)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            
                            // Right: Vertical Tools Sidebar
                            ToolsSidebar(tools: mockTools)
                                .frame(width: 50)
                                .background(Color(.systemGray5)) // Darker separation
                        }
                    }
                    .frame(maxHeight: .infinity)
                    
                    // --- Divider ---
                    Rectangle().fill(Color(.systemGray4)).frame(height: 1)
                    
                    // ⭐️ Bottom: Camera Array/Vignette Picker
                    CameraArrayView(cameras: mockCameras)
                        .frame(height: 150) // Fixed height for the camera array
                        .background(Color(.systemGray6))
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(10)
                .toolbar {
                    ToolbarItemGroup(placement: .automatic) {
                        Button("Save Scene") { scene.saveScene() }
                        // Add a button to quickly jump to the Capturer tab (if applicable in a main app view)
                    }
                }
    }
}



struct SceneTreeView: View {
    @Bindable var scene: VignetteScene
    
    var body: some View {
        List {
            Text("Scene Hierarchy").font(.title3.bold()).listRowSeparator(.hidden)
            ForEach($scene.vignettes) { $vignette in
                Section {
                    VignetteRow(vignette: $vignette, scene: scene)
                    if !vignette.isCollapsed {
                        Group {
                            // Raw Data
                            if !vignette.rawNodes.isEmpty {
                                Text("Source Data").font(.caption).foregroundColor(.secondary)
                                ForEach(vignette.rawNodes) { node in
                                    NodeRow(vignetteID: vignette.id, node: node, scene: scene)
                                }
                            }
                            
                            // Abstractions
                            if !vignette.abstractionNodes.isEmpty {
                                Text("Abstractions").font(.caption).foregroundColor(.secondary).padding(.top, 4)
                                ForEach(vignette.abstractionNodes) { node in
                                    NodeRow(vignetteID: vignette.id, node: node, scene: scene)
                                }
                            }
                        }
                        .padding(.leading, 15)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        /*
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
                Button("+ Add Vignette") { print("Import Vignette from Server") }
            }
        }
         */
    }
}

struct VignetteRow: View {
    @Binding var vignette: Vignette
    @Bindable var scene: VignetteScene
    
    var body: some View {
        HStack {
            Image(systemName: "square.stack.3d.down.right.fill").foregroundColor(.indigo)
            Text(vignette.name).font(.headline)
            Spacer()
            Button { scene.selectedVignetteID = vignette.id } label: {
                Image(systemName: scene.selectedVignetteID == vignette.id ? "circle.inset.filled" : "circle")
            }
            .buttonStyle(.plain)
            Button { vignette.isCollapsed.toggle() } label: {
                Image(systemName: "chevron.right").rotationEffect(.degrees(vignette.isCollapsed ? 0 : 90))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { vignette.isCollapsed.toggle() }
    }
}

struct NodeRow: View {
    let vignetteID: UUID
    let node: VignetteNode
    @Bindable var scene: VignetteScene
    
    private func iconFor(type: GeometryType) -> String {
        switch type {
        case .pointCloud: return "cube.fill"
        case .primitive: return "box.fill"
        case .polyline: return "scribble"
        case .mesh: return "arkit"
        case .gaussianSplat: return "smoke.fill"
        }
    }
    
    var body: some View {
        HStack {
            Image(systemName: iconFor(type: node.geometryType))
                .foregroundColor(.gray)
                .opacity(node.isVisible ? 1.0 : 0.5)
            
            Text(node.name)
            Spacer()
            
            Button {
                scene.toggleNodeVisibility(vignetteID: vignetteID, nodeID: node.id)
            } label: {
                Image(systemName: node.isVisible ? "eye.fill" : "eye.slash.fill")
                    .foregroundColor(node.isVisible ? .accentColor : .gray)
            }
            .buttonStyle(.plain)
        }
    }
}


struct RealityKitViewerStub: View {
    @Bindable var scene: VignetteScene
    
    var body: some View {
        ZStack {
            Color.black
            VStack {
                Text("RealityKit / 3D Composition Space").font(.title.bold()).foregroundColor(.white)
                Text("Scene Root ID: \(scene.sceneID.uuidString.prefix(8))...").foregroundColor(.gray)
                Text("Rendering \(scene.vignettes.count) Vignettes").padding(.top, 10)
                
                if let selectedID = scene.selectedVignetteID,
                   let selectedVignette = scene.vignettes.first(where: { $0.id == selectedID }) {
                    Text("Selected: \(selectedVignette.name)").foregroundColor(.indigo)
                    Text("Capture Path: \(selectedVignette.data.paths.rgb)").font(.caption).foregroundColor(.orange)
                    Text("Transform (T/R/S): \(String(format: "%.1f", selectedVignette.transform.columns.3.x)), \(String(format: "%.1f", selectedVignette.transform.columns.3.y)), \(String(format: "%.1f", selectedVignette.transform.columns.3.z))").font(.caption).foregroundColor(.cyan)
                }
            }
        }
    }
}


struct CameraArrayView: View {
    let cameras: [CameraItem]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Vignette Library").font(.headline).padding([.top, .leading], 10)
            
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 15) {
                    ForEach(cameras) { camera in
                        VStack {
                            Image(systemName: camera.imageName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 60, height: 60)
                                .padding(10)
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                                .shadow(radius: 3)
                            Text(camera.name)
                                .font(.caption)
                        }
                        .onTapGesture {
                            print("Adding \(camera.name) to scene...")
                            // Placeholder action
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 5) // Space for scroll indicator
            }
        }
    }
}

struct ToolsSidebar: View {
    let tools: [ToolItem]
    @State private var selectedTool: ToolItem.ID?
    
    var body: some View {
        VStack(spacing: 15) {
            ForEach(tools) { tool in
                Button {
                    selectedTool = tool.id
                    print("Selected Tool: \(tool.name)")
                } label: {
                    Image(systemName: tool.systemImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 25, height: 25)
                        .foregroundColor(selectedTool == tool.id ? .indigo : .primary)
                        .padding(8)
                        .background(selectedTool == tool.id ? Color.indigo.opacity(0.2) : Color.clear)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help(tool.name) // Tooltip for macOS/iPadOS
            }
            Spacer()
        }
        .padding(.vertical)
    }
}
#Preview(traits: .landscapeLeft) {
    // Create an instance of the mock Scene data for the preview
    // Using a simple instance of Scene() automatically loads MOCK_SCENE_DATA
    let mockScene = VignetteScene()
    
    return SceneView()
        .environment(mockScene)
}
