//
//  ContentView.swift
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 9/4/25.
//

import SwiftUI

struct ContentView: View {
    @State private var selection: Tab = .capture
    @State private var scene = VignetteScene.loadScene()
    enum Tab { case capture, composer }
    
    var body: some View {
        TabView(selection: $selection) {
            SceneView()
                            .tabItem {
                                // This icon represents the collaged spatial vignettes (the Composer/Gallery)
                                Label("Composer", systemImage: "cube.transparent")
                            }
                            .tag(Tab.composer)
            
            // --- Tab 1: Capture (unchanged) ---
            CaptureView()
                .tabItem {
                    Image(systemName: "camera.viewfinder")
                    Text("Capture")
                }
                .tag(Tab.capture)
            
            
            // --- Tab 2: Gallery (non-AR scene) --- Now using the scene view
            /*
            TestView()
            VignetteSceneView()
                .tabItem {
                    Image(systemName: "cube.transparent")
                    Text("Gallery")
                }
                .tag(Tab.gallery)
             */
        }
        .environment(scene)
    }
}

struct TestView: View {
    
    var body: some View {
        VStack {
            Text("Gallery Hello!!!")
        }
    }
}

#Preview(traits: .landscapeLeft) {
    // Note: The SceneView already has a #Preview that initializes a mock scene.
    // For ContentView, we just need to render the view itself.
    ContentView()
}
