//
//  SpatialVignetteApp.swift
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 9/4/25.
//

import SwiftUI
#if os(visionOS)
import RealityKit
import RealityKitContent
#endif

@main
struct SpatialVignetteApp: App {
    var body: some Scene {
        #if os(visionOS)
        VisionScenes()
        #elseif os(iOS)
        IOSScenes()
        #else
        MacScenes()
        #endif
    }
}

struct IOSScenes: Scene {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct MacScenes: Scene {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

#if os(visionOS)
struct VisionScenes: Scene {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        ImmersiveSpace(id: "Immersive") {
            ImmersiveView()
        }
    }
}

struct ImmersiveView: View {
    var body: some View {
        RealityView { content in
            
        }
    }
}
#endif
