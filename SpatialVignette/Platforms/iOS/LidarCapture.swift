//
//  LidarCapture.swift
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 9/4/25.
//
#if os(iOS)

import ARKit
import CoreImage
import simd

public enum CaptureError: Error {
    case deviceNotSupported
    case notAttachedToSession
    case noFrameYet
    case noDepth
    case buildFailed
}
extension CaptureError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .deviceNotSupported:
            return "This device does not support LiDAR scene depth."
        case .notAttachedToSession:
            return "LiDARCaptureService is not attached to any ARSession."
        case .noFrameYet:
            return "No ARFrame is available yet. Wait for the session to produce frames."
        case .noDepth:
            return "The current frame has no depth data (sceneDepth is nil)."
        case .buildFailed:
            return "Failed to build a SpatialVignette from the frame."
        }
    }
}

// MARK: - LiDAR capture service -> Live Vignette

public final class LiDARCaptureService: NSObject, ARSessionDelegate {
    private weak var session: ARSession?
    private var latestFrame: ARFrame?

    // support metric depth aligned to RGB
    public var isSupported: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }
    
    public func attach(session: ARSession) {
        self.session = session
        session.delegate = self
    }

    public func start() throws {
        guard isSupported else { throw CaptureError.deviceNotSupported }
        guard let session else { throw CaptureError.notAttachedToSession }
        let cfg = ARWorldTrackingConfiguration()
        cfg.environmentTexturing = .automatic
        cfg.frameSemantics.insert(.sceneDepth)

        session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
    }

    public func stop() {
        session?.pause()
    }

    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        latestFrame = frame
    }
    
    public func capture() throws -> SpatialVignette {
        guard isSupported else { throw CaptureError.deviceNotSupported }
        guard let frame = latestFrame else { throw CaptureError.noFrameYet }
        guard frame.sceneDepth != nil else { throw CaptureError.noDepth }
        guard let vignette = SpatialVignette(frame: frame) else {
            throw CaptureError.buildFailed
        }
        return vignette
    }

}

#endif
