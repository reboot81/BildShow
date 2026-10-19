import MetalKit
import SwiftUI

private let shaderSource = """
#include <metal_stdlib>
using namespace metal;
struct V { float4 position [[position]]; float2 uv; };
struct Uniforms { float4 rectA, rectB, edgesA, edgesB, background, timing, viewport; };
vertex V vertex_main(uint id [[vertex_id]]) {
    float2 points[4] = {float2(-1,1), float2(1,1), float2(-1,-1), float2(1,-1)};
    float2 uvs[4] = {float2(0,0), float2(1,0), float2(0,1), float2(1,1)};
    return {float4(points[id],0,1),uvs[id]};
}
float4 picture(texture2d<float> texture, float2 uv, float4 rect, float4 edges, float feather, float4 bg, float2 viewport) {
    float2 local = (uv - rect.xy) / max(rect.zw, float2(0.000001));
    if (any(local < 0) || any(local > 1)) return bg;
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 c = texture.sample(s, local);
    float alpha = c.a;
    if (feather > 0) {
        float4 distances = float4(local.x * rect.z * viewport.x, local.y * rect.w * viewport.y, (1-local.x)*rect.z*viewport.x, (1-local.y)*rect.w*viewport.y);
        float4 fades = smoothstep(float4(0),float4(feather),distances);
        float4 factors = mix(float4(1), fades, edges);
        alpha *= factors.x * factors.y * factors.z * factors.w;
    }
    return float4(mix(bg.rgb, c.rgb / max(c.a, 0.000001), alpha),1);
}
fragment float4 fragment_main(V in [[stage_in]], texture2d<float> a [[texture(0)]], texture2d<float> b [[texture(1)]], constant Uniforms& u [[buffer(0)]]) {
    float4 first = picture(a,in.uv,u.rectA,u.edgesA,u.timing.z,u.background,u.viewport.xy);
    float4 second = picture(b,in.uv,u.rectB,u.edgesB,u.timing.w,u.background,u.viewport.xy);
    float t = smoothstep(0.0,1.0,u.timing.x);
    if (u.timing.y > 0.5) return t < 0.5 ? mix(first,u.background,t*2) : mix(u.background,second,(t-0.5)*2);
    return mix(first,second,t);
}
"""

private struct FrameUniforms {
    var rectA, rectB, edgesA, edgesB, background, timing, viewport: SIMD4<Float>
}

final class MetalRenderer: NSObject, MTKViewDelegate {
    let view: MTKView
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var first: PreparedFrame?
    private var second: PreparedFrame?
    private var started = 0.0
    private var duration = 0.0
    private var mode = "crossfade"
    private var background: SIMD4<Float> = [0, 0, 0, 1]
    init(preparing: Bool = true) throws {
        let device = ImagePipeline.shared.device
        view = MTKView(frame: .zero, device: device)
        view.colorPixelFormat = .bgra8Unorm; view.framebufferOnly = false; view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.wantsLayer = true; view.layer?.borderWidth = 0
        view.enableSetNeedsDisplay = true; view.isPaused = true; view.preferredFramesPerSecond = 60
        queue = device.makeCommandQueue()!
        let library = try device.makeLibrary(source: shaderSource, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        super.init(); view.delegate = self
    }
    func show(_ frame: PreparedFrame, duration: Double, mode: String, background: String) {
        first = second ?? frame; second = frame
        self.duration = duration; self.mode = mode; started = CACurrentMediaTime()
        switch background { case "white": self.background = [1,1,1,1]; case "gray": self.background = [0.075,0.075,0.075,1]; default: self.background = [0,0,0,1] }
        view.isPaused = duration <= 0; view.needsDisplay = true
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let first, let second, let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        let progress = duration <= 0 ? 1 : min(1, (CACurrentMediaTime() - started) / duration)
        var uniforms = FrameUniforms(rectA: first.rect, rectB: second.rect, edgesA: first.edges, edgesB: second.edges,
                                     background: background, timing: SIMD4(Float(progress), mode == "fade" ? 1 : 0, first.feather, second.feather),
                                     viewport: SIMD4(Float(view.drawableSize.width), Float(view.drawableSize.height), 0, 0))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(first.texture, index: 0); encoder.setFragmentTexture(second.texture, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding(); command.present(drawable); command.commit()
        if progress >= 1 { self.first = second; view.isPaused = true }
    }
}
