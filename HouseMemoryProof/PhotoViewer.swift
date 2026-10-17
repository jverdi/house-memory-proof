import SwiftUI
import ImageIO

final class EvidenceImageCache {
    static let shared=EvidenceImageCache()
    private let cache=NSCache<NSString,UIImage>()
    private init(){cache.totalCostLimit=48*1024*1024;cache.countLimit=120}
    func thumbnail(url:URL,orientation:Int)->UIImage? {
        let key=(url.lastPathComponent+"-\(orientation)") as NSString
        if let image=cache.object(forKey:key){return image}
        guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:500,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else{return nil}
        let image=UIImage(cgImage:cg,scale:1,orientation:PhotoOrientation.ui(orientation));cache.setObject(image,forKey:key,cost:cg.bytesPerRow*cg.height);return image
    }
}
struct ZoomableEvidence:UIViewRepresentable {
    var image:UIImage
    func makeUIView(context:Context)->EvidenceScrollView {EvidenceScrollView()}
    func updateUIView(_ view:EvidenceScrollView,context:Context){if view.imageView.image !== image{view.setZoomScale(1,animated:false);view.imageView.image=image;view.setNeedsLayout()}}
}
final class EvidenceScrollView:UIScrollView,UIScrollViewDelegate {
    let imageView=UIImageView()
    init(){super.init(frame:.zero);minimumZoomScale=1;maximumZoomScale=8;delegate=self;imageView.contentMode = .scaleAspectFit;addSubview(imageView);backgroundColor = .black;bouncesZoom=true;accessibilityLabel="Original photograph; pinch to zoom"}
    required init?(coder:NSCoder){fatalError("init(coder:) is not used")}
    override func layoutSubviews(){super.layoutSubviews();if zoomScale==1{imageView.frame=bounds;contentSize=bounds.size}}
    func viewForZooming(in scrollView:UIScrollView)->UIView?{imageView}
}
