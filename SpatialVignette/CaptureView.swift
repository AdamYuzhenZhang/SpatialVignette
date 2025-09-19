//
//  CaptureView.swift
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 9/8/25.
//

import SwiftUI
import RealityKit
import ARKit

// View for capturing
struct CaptureView: View {
    @StateObject private var model = AppModel.shared
    @State private var refreshID = UUID()
    @State private var maskThreshold: Float = 0.0
    @State private var finalMaskImage: UIImage?
    private func updateFinalMaskImage() {
        guard let vignette = model.lastVignette else { return }
        
        // Generate the new masked CGImage using the current threshold
        if let cgImage = vignette.createMaskedImage(withThreshold: maskThreshold) {
            print("[View] Successfully created final CGImage. Converting to UIImage.")
            // Convert to UIImage, rotate, and set the state
            let uiImage = UIImage(cgImage: cgImage)
            self.finalMaskImage = uiImage.rotated90Clockwise()
        } else {
            self.finalMaskImage = nil
        }
    }
    
    var body: some View {
        ZStack {
            ARViewContainer()
                .aspectRatio(3.0/4.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipped()
            VStack {
                Text("Capture").font(.title)
                Spacer()
                if let err = model.errorMessage {
                    Text(err).font(.footnote).foregroundColor(.red)
                }
                HStack {
                    Button("Capture") { model.capture() }
                    // Button("Update") { model.updateCurrentVignetteJSON() }
                    Button("SAM") {
                        Task {
                            try? await model.lastVignette?.generateSAMMask()
                        }
                    }
                    Button("Refresh UI") {
                        refreshID = UUID()
                    }
                    Button("Save Crop") {
                        Task {
                            guard let vignette = model.lastVignette else { return }
                            do {
                                // Call the new storage manager method
                                try StorageManager.shared.saveSubjectMask(for: vignette, withThreshold: maskThreshold)
                            } catch {
                                model.errorMessage = "Failed to save subject mask: \(error.localizedDescription)"
                            }
                        }
                    }
                    Button("LLM") {
                        Task {
                            await model.describeSubjectOfLastVignette()
                        }
                    }
                }
                
                if model.lastVignette?.rawMaskLogits != nil {
                    VStack {
                        Text(String(format: "Mask Threshold: %.2f", maskThreshold))
                            .foregroundColor(.white)
                        Slider(
                            value: $maskThreshold,
                            in: -20...20,
                            step: 0.1,
                            onEditingChanged: { _ in
                                updateFinalMaskImage()
                            }
                        )
                    }
                    .padding()
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(20)
                    .padding(.horizontal)
                }
                HStack {
                    if let vignette = model.lastVignette,
                       let depthImg = vignette.depthPreviewImage() {
                        Image(uiImage: depthImg)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 100)
                            .border(Color.white, width: 1)
                    }
                    if let vignette = model.lastVignette,
                       let confImg = vignette.confidencePreviewImage() {
                        Image(uiImage: confImg)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 100)
                            .border(Color.white, width: 1)
                    }
                    if let vignette = model.lastVignette,
                       let subjectMask = vignette.createMask(withThreshold: maskThreshold) {
                        
                        let maskUIImage = UIImage(cgImage: subjectMask)
                        if let rotated = maskUIImage.rotated90Clockwise() {
                            Image(uiImage: rotated)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 100)
                                .border(Color.white, width: 1)
                        }
                    }
                    if let finalImage = finalMaskImage {
                        Image(uiImage: finalImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 100)
                            .background(Color.black.opacity(0.2))
                            .border(Color.white, width: 1)
                    }
                }.id(refreshID)
            }.padding()
        }
        .onAppear {
            model.startAR()
        }
        .onDisappear {
            model.stopAR()
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> ARView {
        print("[Capture] MakeUIView")
        let view = ARView(frame: .zero)
        AppModel.shared.attachARView(view)  // sets up ar session & point cloud overlay
        return view
    }
    func updateUIView(_ uiView: ARView, context: Context) {
        print("[Capture] UpdateUIView")
        // AppModel.shared.attachARView(uiView)
    }
}


extension UIImage {
    func rotated90Clockwise() -> UIImage? {
        let size = CGSize(width: self.size.height, height: self.size.width)
        UIGraphicsBeginImageContextWithOptions(size, false, self.scale)
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
        
        // move origin to center
        ctx.translateBy(x: size.width / 2, y: size.height / 2)
        // rotate 90° clockwise
        ctx.rotate(by: .pi / 2)
        // draw the image, centered
        self.draw(in: CGRect(x: -self.size.width / 2,
                             y: -self.size.height / 2,
                             width: self.size.width,
                             height: self.size.height))
        
        let rotated = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return rotated
    }
}
