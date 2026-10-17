import Foundation
import CoreVideo
import Metal
import SceneKit
import SpriteKit
import UIKit

// Exactly one submitted frame at a time. The texture wrapper and buffer remain
// alive until the GPU completes, including when the caller's deadline expires.
private final class MovieGPUCompletion: @unchecked Sendable {
  private let lock=NSLock()
  private var continuation:CheckedContinuation<Void,Error>?
  init(_ continuation:CheckedContinuation<Void,Error>){self.continuation=continuation}
  func finish(_ error:Error?) {
    lock.lock();let pending=continuation;continuation=nil;lock.unlock()
    if let error {pending?.resume(throwing:error)}else{pending?.resume()}
  }
}

@MainActor final class MovieFrameRenderer {
  let renderer:SCNRenderer
  private let queue:MTLCommandQueue
  private let cache:CVMetalTextureCache
  private let depth:MTLTexture
  private let width:Int,height:Int
  init(scene:SCNScene,camera:SCNNode,width:Int,height:Int,title:String,provenance:String)throws {
    guard width>0,height>0,width<=3840,height<=2160,
      let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue() else{throw HouseError.message("Metal movie rendering is unavailable.")}
    var cache:CVMetalTextureCache?
    guard CVMetalTextureCacheCreate(kCFAllocatorDefault,nil,device,nil,&cache)==kCVReturnSuccess,let cache else{throw HouseError.message("Movie texture allocation is unavailable.")}
    let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float_stencil8,width:width,height:height,mipmapped:false)
    descriptor.usage = .renderTarget;descriptor.storageMode = .private
    guard let depth=device.makeTexture(descriptor:descriptor) else{throw HouseError.message("Movie depth target exceeds available memory.")}
    self.queue=queue;self.cache=cache;self.depth=depth;self.width=width;self.height=height
    renderer=SCNRenderer(device:device,options:nil);renderer.scene=scene;renderer.pointOfView=camera
    // Rasterize only the small, unchanging caption once per shot. SpriteKit
    // composites that texture in the same GPU render pass as the 3D scene.
    let titleFont=UIFont.systemFont(ofSize:CGFloat(width)/55,weight:.medium)
    let sourceFont=UIFont.systemFont(ofSize:CGFloat(width)/70,weight:.regular)
    let titleHeight=ceil(titleFont.lineHeight),sourceHeight=ceil(sourceFont.lineHeight)
    let captionHeight=titleHeight+sourceHeight+18
    let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=false
    let caption=UIGraphicsImageRenderer(size:CGSize(width:width-28,height:Int(captionHeight)),format:format).image { context in
      UIColor.black.withAlphaComponent(0.65).setFill()
      UIBezierPath(roundedRect:CGRect(x:0,y:0,width:width-28,height:Int(captionHeight)),cornerRadius:8).fill()
      let paragraph=NSMutableParagraphStyle();paragraph.lineBreakMode = .byTruncatingTail
      (title as NSString).draw(in:CGRect(x:10,y:5,width:CGFloat(width)-48,height:titleHeight),withAttributes:[.font:titleFont,.foregroundColor:UIColor.white,.paragraphStyle:paragraph])
      (provenance as NSString).draw(in:CGRect(x:10,y:5+titleHeight+8,width:CGFloat(width)-48,height:sourceHeight),withAttributes:[.font:sourceFont,.foregroundColor:UIColor.white,.paragraphStyle:paragraph])
    }
    let overlay=SKScene(size:CGSize(width:width,height:height));overlay.scaleMode = .resizeFill;overlay.backgroundColor = .clear
    let label=SKSpriteNode(texture:SKTexture(image:caption));label.anchorPoint = .zero;label.position=CGPoint(x:14,y:19)
    overlay.addChild(label);renderer.overlaySKScene=overlay
  }
  func frame(at time:Double,pool:CVPixelBufferPool) async throws->CVPixelBuffer {
    try Task.checkCancellation()
    var buffer:CVPixelBuffer?
    let attributes=[kCVPixelBufferPoolAllocationThresholdKey as String:8] as CFDictionary
    guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault,pool,attributes,&buffer)==kCVReturnSuccess,let buffer else{throw HouseError.message("Movie frame pool is full. Completed shots are saved; export again to resume.")}
    var reference:CVMetalTexture?
    let textureAttributes=[kCVMetalTextureUsage as String:MTLTextureUsage.renderTarget.rawValue] as CFDictionary
    guard CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,cache,buffer,textureAttributes,.bgra8Unorm,width,height,0,&reference)==kCVReturnSuccess,
      let reference,let color=CVMetalTextureGetTexture(reference),let command=queue.makeCommandBuffer() else{throw HouseError.message("Movie frame could not become a Metal render target.")}
    let pass=MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture=color;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor=MTLClearColor(red:0,green:0,blue:0,alpha:1)
    pass.depthAttachment.texture=depth;pass.depthAttachment.loadAction = .clear;pass.depthAttachment.storeAction = .dontCare;pass.depthAttachment.clearDepth=renderer.usesReverseZ ? 0:1
    pass.stencilAttachment.texture=depth;pass.stencilAttachment.loadAction = .clear;pass.stencilAttachment.storeAction = .dontCare;pass.stencilAttachment.clearStencil=0
    renderer.render(atTime:time,viewport:CGRect(x:0,y:0,width:width,height:height),commandBuffer:command,passDescriptor:pass)
    try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
      let completion=MovieGPUCompletion(continuation)
      command.addCompletedHandler { [buffer,reference] finished in
        withExtendedLifetime((buffer,reference)) {
          completion.finish(finished.status == .completed ? nil:(finished.error ?? HouseError.message("Movie GPU command failed.")))
        }
      }
      DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+15) {
        completion.finish(HouseError.message("Movie GPU command timed out. Completed shots are saved; export again to resume."))
      }
      command.commit()
    }
    try Task.checkCancellation()
    return buffer
  }
}
