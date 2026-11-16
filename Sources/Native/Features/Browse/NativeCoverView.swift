import SwiftUI
import ImageIO

/// 原生图片加载（3.3）：内存缓存 + 后台下载 + ImageIO 降采样解码。
/// 浏览面全原生后，封面一律走这里，禁止整表原图全量解码（3.0/3.1 网页歌单
/// 被 jetsam 杀掉的原生对应防线）。同一 URL 全局只解一份。
final class NativeImageCache {
    static let shared = NativeImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 300
    }

    func image(for url: URL, targetPixels: Int) async -> UIImage? {
        let key = "\(url.absoluteString)#\(targetPixels)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let image = await Task.detached(priority: .utility) {
                Self.downsample(data: data, targetPixels: targetPixels)
            }.value
            if let image { cache.setObject(image, forKey: key) }
            return image
        } catch {
            return nil
        }
    }

    private static func downsample(data: Data, targetPixels: Int) -> UIImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return nil
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: targetPixels
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

/// 封面视图：占位 + 异步降采样加载。网易云图片走 CDN 的 param 缩放，
/// 请求时就只要小图（列表 150 / 卡片 300 / 头图 500）。
struct NativeCoverView: View {
    let url: URL?
    var targetPixels: Int = 300

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.15)
                    Image(systemName: "music.note")
                        .foregroundColor(.secondary)
                }
            }
        }
        .clipped()
        .task(id: url?.absoluteString) {
            image = nil
            guard let url else { return }
            image = await NativeImageCache.shared.image(
                for: Self.resized(url, pixels: targetPixels), targetPixels: targetPixels)
        }
    }

    /// music.126.net 支持 ?param=WxH 服务端缩放；已有查询串或外站图原样返回。
    static func resized(_ url: URL, pixels: Int) -> URL {
        guard url.host?.contains("music.126.net") == true,
              url.query == nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.queryItems = [URLQueryItem(name: "param", value: "\(pixels)y\(pixels)")]
        return components.url ?? url
    }
}
