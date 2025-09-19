//
//  VignetteSceneView.swift
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 9/15/25.
//

// MARK: - Non-AR RealityKit scene with gallery
import SwiftUI
import RealityKit
import MetalKit
import ARKit

// NOTE: This gallery uses MTKView (not ARView) so there is never any AR camera feed here.
// When switching away (tab swap), `dismantleUIView` detaches the renderer to avoid leaks.

/// A screen that shows a non-AR RealityKit scene and a horizontal strip of saved vignettes.
/// Tapping a thumbnail loads that vignette's point cloud into the scene.
struct VignetteSceneView: View {
    @StateObject private var model = AppModel.shared
    @State private var ids: [UUID] = []

    var body: some View {
        ZStack(alignment: .bottom) {
            // 3D scene host (no AR session started)
            SceneMTKViewContainer()
                .onAppear {
                    // Load all saved vignette IDs from disk when we enter the view
                    ids = model.refreshVignetteIDs()
                }
                .ignoresSafeArea()

            // Bottom gallery strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ids, id: \.self) { id in
                        Button {
                            // Load the selected vignette and draw it in the scene
                            
                            // model.clearRenderer()
                            
                            
                            model.displayVignetteInScene(id: id)
                        } label: {
                            // Quick RGB thumbnail if we can make one; fallback to ID text
                            if let thumb = model.vignetteThumbnail(id: id) {
                                Image(uiImage: thumb)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 90)
                                    .clipped()
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.8), lineWidth: 1)
                                    )
                            } else {
                                ZStack {
                                    Color.gray.opacity(0.2)
                                    Text(id.uuidString.prefix(6))
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                                .frame(width: 120, height: 90)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial) // nice glassy bar
            }
        }
        .onDisappear {
            model.renderer.detach()
        }
        .overlay(alignment: .topLeading) {
            if let err = model.errorMessage {
                Text(err).font(.footnote).foregroundColor(.red).padding()
            }
        }
    }
}



/// Hosts a MetalKit MTKView that the renderer uses in non-AR (orbit camera) mode.
struct SceneMTKViewContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView {
        let v = MTKView(frame: .zero)
        // Make sure we are not attached anywhere else, then attach to this MTKView
        AppModel.shared.attachSceneMTKView(v)
        return v
    }
    func updateUIView(_ uiView: MTKView, context: Context) {
        // SwiftUI may reuse the MTKView without calling makeUIView again.
        // Reattach (idempotently) so the renderer resumes drawing.
        // AppModel.shared.attachSceneMTKView(uiView)
    }

    static func dismantleUIView(_ uiView: MTKView, coordinator: ()) {
        // Cleanly detach when this view leaves the hierarchy (e.g., switching tabs)
        AppModel.shared.renderer.detach()
    }
}
