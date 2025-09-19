//
//  ContentView.swift
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 9/4/25.
//

import SwiftUI

struct ContentView: View {
    @State private var selection: Tab = .capture
    enum Tab { case capture, gallery }
    
    var body: some View {
        TabView(selection: $selection) {
            
            // --- Tab 1: Capture (unchanged) ---
            CaptureView()
                .tabItem {
                    Image(systemName: "camera.viewfinder")
                    Text("Capture")
                }
                .tag(Tab.capture)
            
            
            // --- Tab 2: Gallery (non-AR scene) ---
            TestView()
            VignetteSceneView()
                .tabItem {
                    Image(systemName: "cube.transparent")
                    Text("Gallery")
                }
                .tag(Tab.gallery)
        }
    }
}

struct TestView: View {
    
    var body: some View {
        VStack {
            Text("Gallery Hello!!!")
        }
    }
}
