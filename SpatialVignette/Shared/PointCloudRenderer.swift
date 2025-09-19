//
//  PointCloudRenderer.swift
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 9/9/25.
//

import Foundation
import UIKit
import Metal
import MetalKit
import simd
import ARKit
import RealityKit

public final class PointCloudRenderer: NSObject, MTKViewDelegate {
    // GPU Core
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var library: MTLLibrary!
    private var pipeline: MTLRenderPipelineState!
    private var depthState: MTLDepthStencilState!
    
    private weak var arView: ARView?
    //private var mode: Mode?
    private var useARCamera: Bool = true
    
    private var arOverlayView: MTKView? // overlay on top of ARView
    private var standaloneView: MTKView?
    
    // A point cloud node
    private final class CloudNode {
        let id: UUID
        let pointCount: Int
        let positions: MTLBuffer  // float3
        var colors: MTLBuffer  // uchar4
        var modelMatrix: simd_float4x4 // cameraIntrinsic in AR mode
        var visible: Bool = true
        
        init(id: UUID, pointCount: Int, positions: MTLBuffer, colors: MTLBuffer, modelMatrix: simd_float4x4) {
            self.id = id
            self.pointCount = pointCount
            self.positions = positions
            self.colors = colors
            self.modelMatrix = modelMatrix
        }
    }
    
    private var nodes: [UUID: CloudNode] = [:]
    
    // Camera
    private var viewportSize: CGSize = .zero
    public var orbitCamera: OrbitCamera = OrbitCamera() // Orbit Camera
    
    // Settings
    private var pointSizePx: Float = 2.0
    private var attenuateByDepth: Bool = true  // shrinks points with distance
    public var maxDepthMeters: Float? = nil
    
    // Uniforms layout
    private struct PCUniforms {
        var viewProj: simd_float4x4
        var model: simd_float4x4
        var basePointSize: Float
        var attenuateFlag: Float // 1.0 attenuate, 0.0 constant
        var _pad: SIMD2<Float> = .zero
    }
    
    public init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let dev = device, let cq = dev.makeCommandQueue() else {
            fatalError("Metal is not available on this device/simulator.")
        }
        self.device = dev
        self.commandQueue = cq
        super.init()
        buildLibraryAndPipeline()
        buildDepthState()
    }
    
    // ARView
    public func attach(toARView arView: ARView) {
        self.useARCamera = true
        self.arView = arView
        ensureAROverlay()
    }
    
    public func ensureAROverlay() {
        guard let arView else { return }
        useARCamera = true
        let overlay: MTKView
        if let existing = arOverlayView {
            print("[Renderer] Exist AR Overlay")
            overlay = existing
        } else {
            let newOverlay = makeOverlayMTKView(frame: arView.bounds)
            print("[Renderer] Create AR Overlay")
            arOverlayView = newOverlay
            overlay = newOverlay
        }
        if overlay.superview === arView, overlay.delegate === self, overlay.isPaused == false {
            print("[Renderer] AR Overlay already running")
            return
        }
        // move to arview
        overlay.removeFromSuperview()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        arView.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: arView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: arView.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: arView.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: arView.bottomAnchor),
        ])
        configure(mtkView: overlay)
        // add delegate
        overlay.delegate = self
        overlay.isPaused = false
        overlay.preferredFramesPerSecond = 60
        viewportSize = overlay.drawableSize
        
        orbitCamera.aspect = Float(viewportSize.width / max(viewportSize.height, 1))
        /*
        DispatchQueue.main.async { [weak self, weak overlay] in
            guard let self, let overlay = overlay else { return }
            // Only record viewport if non-zero; otherwise wait for delegate callback
            let ds = overlay.drawableSize
            if ds.width > 0, ds.height > 0 {
                self.viewportSize = CGSize(width: ds.width, height: ds.height)
                self.orbitCamera.aspect = Float(ds.width / max(ds.height, 1))
                print("[Renderer] Initial drawableSize = \(Int(ds.width))x\(Int(ds.height))")
            } else {
                print("[Renderer] DrawableSize still zero; will update via delegate")
            }
        }
         */
    }
    
    // Standalone
    public func attach(toMTKView view: MTKView) {
        self.useARCamera = false
        configure(mtkView: view)
        view.delegate = self
        view.isPaused = false
        view.preferredFramesPerSecond = 60
        
        standaloneView = view
        viewportSize = view.drawableSize
        
        orbitCamera.aspect = Float(view.drawableSize.width / max(view.drawableSize.height, 1))
        orbitCamera.distance = 1.5
        orbitCamera.yaw = 0
        orbitCamera.pitch = -.pi/12
    }

    // Detach from AR overlay or standalone MTKView and clear refs
    public func detach() {
        if let overlay = arOverlayView {
            overlay.delegate = nil
            overlay.isPaused = true
            overlay.removeFromSuperview()
        }
        if let s = standaloneView {
            s.delegate = nil
            s.isPaused = true
        }
    }
    
    // update drawable size
    public func resize(to size: CGSize) {
        viewportSize = size
        if let v = arOverlayView { v.drawableSize = size }
        if let v = standaloneView { v.drawableSize = size }
        orbitCamera.aspect = Float(size.width / max(size.height, 1))
    }
    @discardableResult
    public func addVignette(_ v: SpatialVignette, id: UUID? = nil, sampleStride: Int = 1) -> UUID {
        let cloudID = id ?? v.id
        
        // 1) Generate CAMERA-RELATIVE points (Xc,Yc,Zc + RGB). No world transform here.
        let pts = v.generatePointCloud(sampleStride: sampleStride, maxDepth: maxDepthMeters)
        print("[Point Cloud] CPU points generated:", pts.count)
        
        // 2) Split into SOA arrays and create GPU buffers.
        let (posBuf, colBuf, count) = upload(points: pts)
        
        // 3) Store the per-node model matrix as the worldFromCamera at capture.
        //    When drawing in AR, model moves the cloud from camera space -> world space.
        let model = v.cameraExtrinsics
        
        nodes[cloudID] = CloudNode(id: cloudID, pointCount: count, positions: posBuf, colors: colBuf, modelMatrix: model)
        
        return cloudID
    }
    
    /// Removes an uploaded cloud (frees buffers when ARC releases them).
    public func removeVignette(id: UUID) {
        nodes[id] = nil
    }
    public func removeAllVignettes() {
        nodes.removeAll()
    }
    
    /// Toggling visibility is cheaper than removing/adding back (keeps buffers resident).
    public func setVisible(_ visible: Bool, for id: UUID) {
        nodes[id]?.visible = visible
    }
    
    /// Base point size in pixels (shader can attenuate with distance).
    public func setPointSize(_ size: Float, attenuateByDepth: Bool = true) {
        self.pointSizePx = max(1, size)
        self.attenuateByDepth = attenuateByDepth
    }
    
    // MARK: - MTKViewDelegate
    
    // Called whenever the drawable size changes (rotation, resizes, etc.)
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = size
        orbitCamera.aspect = Float(size.width / max(size.height, 1))
    }
    
    // Called every frame by the MTKView
    public func draw(in view: MTKView) {
        // Compute view/projection for whichever view is drawing
        guard let (viewMat, projMat) = currentViewAndProjection(for: view) else { return }
        guard let rpd = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let cmd = commandQueue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }
        
        // Clear/setup attachments (transparent for overlay)
        if let ca0 = rpd.colorAttachments[0] {
            // For an AR overlay we want full transparency by default
            ca0.loadAction  = .clear
            ca0.clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            ca0.storeAction = .store
        }
        if let depth = rpd.depthAttachment {
            depth.loadAction  = .clear
            depth.clearDepth  = 1.0
            depth.storeAction = .dontCare
        }
        
        enc.setRenderPipelineState(pipeline)
        enc.setDepthStencilState(depthState)
        enc.setCullMode(.none)
        enc.setViewport(MTLViewport(originX: 0,
                                    originY: 0,
                                    width: Double(view.drawableSize.width),
                                    height: Double(view.drawableSize.height),
                                    znear: 0.0, zfar: 1.0))
        
        // Matrices: viewProj transforms world -> clip
        let viewProj = projMat * viewMat
        
        /*
        // ----- DEBUG: draw a cross 30cm in front of the current camera -----
        do {
            // Put four points in *camera space* at z = -0.30m (forward)
            let d: Float = 0.30
            let s: Float = 0.05  // cross half-size (5 cm)
            var dbgPositions: [SIMD3<Float>] = [
                SIMD3<Float>(-s, 0, -d),
                SIMD3<Float>( s, 0, -d),
                SIMD3<Float>( 0,-s, -d),
                SIMD3<Float>( 0, s, -d),
            ]
            // RGBA 255
            var dbgColors: [SIMD4<UInt8>] = Array(repeating: SIMD4<UInt8>(255, 255, 255, 255), count: dbgPositions.count)

            // Model should convert *camera space -> world space* for the *current* frame.
            // Since viewMat is world->camera, its inverse is camera->world.
            let camToWorld = viewMat.inverse
            
            // Make uniforms: big point size, no attenuation
            var dbgU = PCUniforms(
                viewProj: viewProj,
                model: camToWorld,
                basePointSize: max(pointSizePx, 14),  // big & obvious
                attenuateFlag: 0.0
            )

            // Temporarily disable depth test so the cross is never occluded
            let dsDesc = MTLDepthStencilDescriptor()
            dsDesc.isDepthWriteEnabled = true
            dsDesc.depthCompareFunction = .less
            let noDepth = device.makeDepthStencilState(descriptor: dsDesc)
            enc.setDepthStencilState(noDepth)

            // Feed small arrays via setVertexBytes (fine for tiny debug geometry)
            enc.setVertexBytes(&dbgU, length: MemoryLayout<PCUniforms>.stride, index: 2)
            enc.setVertexBytes(&dbgPositions,
                               length: MemoryLayout<SIMD3<Float>>.stride * dbgPositions.count, index: 0)
            enc.setVertexBytes(&dbgColors,
                               length: MemoryLayout<SIMD4<UInt8>>.stride * dbgColors.count, index: 1)
            enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: dbgPositions.count)

            // Restore your normal depth state for real clouds
            enc.setDepthStencilState(depthState)
        }
        // ----- END DEBUG -----
        */
         
        var totalVerts = 0
        for node in nodes.values where node.visible {
            var u = PCUniforms(
                viewProj: viewProj,
                model: node.modelMatrix,
                basePointSize: pointSizePx,
                attenuateFlag: (attenuateByDepth ? 1.0 : 0.0)
            )
            enc.setVertexBytes(&u, length: MemoryLayout<PCUniforms>.stride, index: 2)
            enc.setVertexBuffer(node.positions, offset: 0, index: 0)
            enc.setVertexBuffer(node.colors, offset: 0, index: 1)
            enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: node.pointCount)
            totalVerts += node.pointCount
        }
        
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
    
    
    // MARK: - Metal setup
    
    /// Loads the default shader library and builds a tiny point-sprite pipeline.
    /// Expects the functions `pcVertex` and `pcFragment` to exist in your .metal file.
    private func buildLibraryAndPipeline() {
        guard let lib = device.makeDefaultLibrary() else {
            fatalError("Missing default Metal library. Ensure your .metal shaders are in the target.")
        }
        library = lib
        
        let vfun = library.makeFunction(name: "pcVertex")
        let ffun = library.makeFunction(name: "pcFragment")
        
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfun
        desc.fragmentFunction = ffun
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        desc.depthAttachmentPixelFormat = .depth32Float
        
        do {
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Failed to create pipeline: \(error)")
        }
    }
    
    /// Depth test config: compare LESS-EQUAL, don’t write (so we don’t disturb AR depth).
    private func buildDepthState() {
        let d = MTLDepthStencilDescriptor()
        d.depthCompareFunction = .lessEqual
        d.isDepthWriteEnabled = false
        guard let s = device.makeDepthStencilState(descriptor: d) else {
            fatalError("Failed to create depth state")
        }
        depthState = s
    }
    
    /// Shared MTKView configuration for both modes.
    private func configure(mtkView: MTKView) {
        mtkView.device = device
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.presentsWithTransaction = false
        mtkView.enableSetNeedsDisplay = false
        
        // Transparent so AR camera shows through in overlay mode.
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.isPaused = true                  // we control when to draw
        
        mtkView.framebufferOnly = true
        mtkView.isOpaque = false
        mtkView.backgroundColor = .clear
    }
    
    /// Creates the overlay MTKView for AR mode.
    private func makeOverlayMTKView(frame: CGRect) -> MTKView {
        let v = MTKView(frame: frame, device: device)
        configure(mtkView: v)
        return v
    }
    
    // MARK: - Buffer upload
    
    /// Converts `[PointXYZRGB]` into two contiguous GPU buffers (positions/colors).
    private func upload(points: [PointXYZRGB]) -> (pos: MTLBuffer, col: MTLBuffer, count: Int) {
        let count = points.count
        var pos = [SIMD3<Float>]()
        pos.reserveCapacity(count)
        var col = [SIMD4<UInt8>]()
        col.reserveCapacity(count)
        
        for p in points {
            pos.append(SIMD3<Float>(p.x, p.y, p.z))
            col.append(SIMD4<UInt8>(p.r, p.g, p.b, 255))
        }
        
        guard
            let pb = device.makeBuffer(bytes: pos,
                                       length: MemoryLayout<SIMD3<Float>>.stride * count,
                                       options: .storageModeShared),
            let cb = device.makeBuffer(bytes: col,
                                       length: MemoryLayout<SIMD4<UInt8>>.stride * count,
                                       options: .storageModeShared)
        else {
            fatalError("Failed to allocate point cloud buffers.")
        }
        return (pb, cb, count)
    }
    
    // MARK: - Camera state
    
    /// Returns the active MTKView plus the current view/projection matrices.
    /// - AR mode: pulls matrices from ARKit for the current frame & orientation.
    /// - Standalone mode: will use the orbit camera (file added next).
    private func currentViewAndProjection(for view: MTKView) -> (simd_float4x4, simd_float4x4)? {
        // If drawing into the AR overlay
        if let overlay = arOverlayView, view === overlay {
            if useARCamera, let arView, let frame = arView.session.currentFrame {
                let orientation: UIInterfaceOrientation = .portrait
                let viewMat = frame.camera.viewMatrix(for: orientation)
                let projMat = frame.camera.projectionMatrix(
                    for: orientation,
                    viewportSize: view.drawableSize,
                    zNear: 0.001, zFar: 100.0
                )
                return (viewMat, projMat)
            } else {
                // Orbit camera fallback when not using AR camera
                let viewMat = orbitCamera.viewMatrix()
                let projMat = orbitCamera.projectionMatrix()
                return (viewMat, projMat)
            }
        }

        // If drawing into a standalone MTKView (non-AR scene)
        if let standalone = standaloneView, view === standalone {
            let viewMat = orbitCamera.viewMatrix()
            let projMat = orbitCamera.projectionMatrix()
            return (viewMat, projMat)
        }

        // Unknown view — skip drawing
        return nil
    }
    
    /// Replace a node's color buffer with solid white (debug).
    public func forceColorsWhite(for id: UUID? = nil) {
        let makeWhite = { (count: Int) -> MTLBuffer? in
            var whites = Array(repeating: SIMD4<UInt8>(255, 255, 255, 255), count: count)
            return self.device.makeBuffer(bytes: &whites,
                                          length: MemoryLayout<SIMD4<UInt8>>.stride * count,
                                          options: .storageModeShared)
        }
        
        if let id, var node = nodes[id] {
            if let wb = makeWhite(node.pointCount) { node.colors = wb; nodes[id] = node }
            return
        }
        
        for (k, var node) in nodes {
            if let wb = makeWhite(node.pointCount) { node.colors = wb; nodes[k] = node }
        }
    }
}
