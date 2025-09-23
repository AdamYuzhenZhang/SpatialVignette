//
//  AppModel.swift
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 9/8/25.
//

import Foundation
import ARKit
import SwiftUI
import RealityKit
import MetalKit

struct LogitsPreview: Identifiable {
    let id = UUID()
    let image: CGImage
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    
    private let captureService = LiDARCaptureService()
    private let storage = StorageManager.shared
    
    @Published var lastVignette: SpatialVignette?
    var lastTappedUV: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @Published var errorMessage: String?
    
    @Published var isLoading: Bool = false
        @Published var statusMessage: String = "Ready to start."
        @Published var previewMask: LogitsPreview?
        @Published var maskThreshold: Float = 0.0 {
            // When the slider changes this value, regenerate the preview image.
            didSet {
                generatePreviewMaskFromStoredLogits()
            }
        }
    private var serverVignetteID: String?
    @Published var rawLogits: ServerAPIService.LogitsResult?
    
    // The point clouds being visualized
    @Published var pointCloudIDs: [UUID] = []
    
    let renderer = PointCloudRenderer()
    private var displayLink: CADisplayLink?
    
    private weak var arView: ARView?
    
    private init() {}
    
    func attachARView(_ arView: ARView) {
        self.arView = arView

        // Always keep capture service wired to the active ARSession
        captureService.attach(session: arView.session)

        renderer.detach()
        renderer.attach(toARView: arView)
        print("[Capture] Attached ARView")
        renderer.resize(to: arView.bounds.size)
    }
    
    /// Hosts the renderer in a standalone MTKView (NO AR session, no camera feed).
    func attachSceneMTKView(_ mtkView: MTKView) {
        // If we're already attached to this exact MTKView, just ensure size and resume.
        if (mtkView.delegate as AnyObject?) === renderer {
            renderer.resize(to: mtkView.bounds.size)
            mtkView.isPaused = false
            return
        }
        // Otherwise, detach from any previous view and attach to this one.
        renderer.detach()
        renderer.attach(toMTKView: mtkView)
        print("[Vignetted Scene] Attached MTKView")
        renderer.resize(to: mtkView.bounds.size)
    }
    
    func startAR() {
        do {
            try captureService.start()
            renderer.ensureAROverlay()
        }
        catch { self.errorMessage = "Failed to start AR: \(error.localizedDescription)" }
    }
    func stopAR() {
        captureService.stop()
    }
    
    // MARK: - Gallery helpers (non-AR visualization)
    
    /// Read all saved vignette folder IDs from disk.
    func refreshVignetteIDs() -> [UUID] { storage.listVignettes() }
    
    /// Load a vignette from disk and draw it in the non-AR scene (clears previous clouds).
    func displayVignetteInScene(id: UUID) {
        do {
            let v = try storage.loadVignette(id: id)
            self.lastVignette = v
            removeAllPointClouds()                 // clear previous
            _ = renderer.addVignette(v, sampleStride: 1)
            renderer.setPointSize(6.0, attenuateByDepth: true)
        } catch {
            self.errorMessage = "Load vignette failed: \(error.localizedDescription)"
        }
    }
    
    /// Small RGB thumbnail helper for the bottom strip (quick in-memory downscale).
    func vignetteThumbnail(id: UUID, maxWidth: CGFloat = 120) -> UIImage? {
        do {
            let v = try storage.loadVignette(id: id)
            let ui = UIImage(cgImage: v.rgbImage)
            let srcW = CGFloat(ui.cgImage?.width ?? 1)
            let scale = maxWidth / max(srcW, 1)
            if scale >= 1 { return ui }            // already small enough
            let size = CGSize(width: srcW * scale,
                              height: CGFloat(ui.cgImage?.height ?? 1) * scale)
            UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
            ui.draw(in: CGRect(origin: .zero, size: size))
            let out = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return out
        } catch {
            return nil
        }
    }
    
    func capture() {
        do {
            let vignette = try captureService.capture()
            self.lastVignette = vignette
            
            // visualize vignette point cloud
            let id = renderer.addVignette(vignette, sampleStride: 1)
            pointCloudIDs.append(id)
            renderer.setPointSize(10.0, attenuateByDepth: false) // settings
            
            // renderer.forceColorsWhite()
            // Save vignette
            let _ = try storage.save(vignette: vignette)
        } catch {
            print("Capture failed: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
        }
    }
    func updateCurrentVignetteJSON() {
        guard let lastVignette else { return }
        do {
            let _ = try storage.updateJSON(for: lastVignette)
        } catch {
            self.errorMessage = "Update JSON failed: \(error.localizedDescription)"
        }
    }
    
    func allVignetteIDs() -> [UUID] {
        storage.listVignettes()
    }
    
    func delete(id: UUID) {
        do {
            try storage.deleteVignette(id: id)
        } catch {
            self.errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }
    
    /*
     // MARK: - Manual frame loop for the Metal renderer
     
     // Called every display vsync — drives the point cloud drawing
     @objc private func tick() {
     renderer.draw()
     }
     
     // Start the CADisplayLink if not already running
     private func startDisplayLink() {
     guard displayLink == nil else { return }
     let link = CADisplayLink(target: self, selector: #selector(tick))
     link.add(to: .main, forMode: .default)
     displayLink = link
     }
     
     // Stop the CADisplayLink if running
     private func stopDisplayLink() {
     displayLink?.invalidate()
     displayLink = nil
     }
     */
    
    // MARK: - convenience helpers for clouds
    
    // Remove all uploaded clouds from the renderer and clear the list
    func removeAllPointClouds() {
        for id in pointCloudIDs { renderer.removeVignette(id: id) }
        pointCloudIDs.removeAll()
    }
    
    
    @MainActor
    func describeSubjectOfLastVignette() async {
        /*
        guard let vignette = lastVignette,
              // Assuming you have the final masked image stored somewhere
              let subjectCGImage = vignette.createFinalMaskedImage(withThreshold: 0.0) else { // Or use a saved threshold
            return
        }

        let fullImage = vignette.rgbImage
        
        // Call the new, specific method on the LLMManager
        if let description = await LLMManager.shared.identifyAndDescribe(subjectImage: subjectCGImage, originalImage: fullImage) {
            // You can now display this description in your UI
            print("AI Description: \(description)")
            // e.g., self.subjectDescription = description
        } else {
            print("Failed to get a description from the AI.")
        }
         */
    }
    
    // MARK: - Segmentation with SAM
    func startSegmentationProcess() {
        guard let vignette = lastVignette else {
            statusMessage = "Error: No vignette captured."
            return
        }
        
        self.isLoading = true
        self.statusMessage = "Uploading vignette..."
        self.previewMask = nil
        self.rawLogits = nil
        
        Task {
            do {
                // Step 1: Upload
                let vignetteID = try await ServerAPIService.shared.uploadVignette(vignette, uv: lastTappedUV)
                self.serverVignetteID = vignetteID
                
                // Step 2: Get Logits
                self.statusMessage = "Vignette uploaded! Getting segmentation data..."
                let logitsResult = try await ServerAPIService.shared.getLogits(for: vignetteID)
                self.rawLogits = logitsResult
                
                // Step 3: Generate the first preview
                generatePreviewMaskFromStoredLogits()
                self.statusMessage = "Ready! Adjust the threshold with the slider."
                
            } catch {
                self.statusMessage = "Error: \(error.localizedDescription)"
            }
            self.isLoading = false
        }
    }
    
    func finalizeMaskOnServer() {
        guard let vignetteID = serverVignetteID else {
            statusMessage = "Error: No vignette has been uploaded yet."
            return
        }
        
        self.isLoading = true
        self.statusMessage = "Finalizing mask on server..."
        
        Task {
            do {
                try await ServerAPIService.shared.getMask(for: vignetteID, threshold: self.maskThreshold)
                self.statusMessage = "Success! Mask saved on server with threshold \(String(format: "%.2f", maskThreshold))."
            } catch {
                self.statusMessage = "Error: \(error.localizedDescription)"
            }
            self.isLoading = false
        }
    }
    
    private func generatePreviewMaskFromStoredLogits() {
        guard let logits = rawLogits else { return }
        
        // This is a client-side operation, so it's very fast.
        // It uses a helper to convert the raw data into a displayable image.
        if let cgImage = ImageUtils.createMaskImage(
            from: logits.data,
            width: logits.width,
            height: logits.height,
            threshold: self.maskThreshold
        ) {
            self.previewMask = LogitsPreview(image: cgImage)
        }
    }
}
