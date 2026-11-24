import SwiftUI
import UIKit
import ImageIO

/// Immagine remota con cache in memoria + disco, riduzione e nuovi tentativi.
@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private let mem = NSCache<NSURL, UIImage>()
    private let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("covers")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: c)
    }()

    private func file(_ url: URL) -> URL {
        dir.appendingPathComponent(String(url.absoluteString.hashValue, radix: 36) + ".img")
    }

    func image(for url: URL, maxPixel: CGFloat = 240) async -> UIImage? {
        if let i = mem.object(forKey: url as NSURL) { return i }
        if let d = try? Data(contentsOf: file(url)), let i = Self.downsample(d, maxPixel) {
            mem.setObject(i, forKey: url as NSURL); return i
        }
        for attempt in 0..<3 {
            var req = URLRequest(url: url)
            req.setValue("image/webp,image/png,image/jpeg,image/*", forHTTPHeaderField: "Accept")
            req.setValue("https://makerworld.com/", forHTTPHeaderField: "Referer")
            if let (d, r) = try? await session.data(for: req),
               (r as? HTTPURLResponse)?.statusCode == 200,
               let i = Self.downsample(d, maxPixel) {
                mem.setObject(i, forKey: url as NSURL)
                if let small = i.jpegData(compressionQuality: 0.85) { try? small.write(to: file(url)) }
                return i
            }
            try? await Task.sleep(for: .milliseconds(400 * (attempt + 1)))
        }
        return nil
    }

    nonisolated static func downsample(_ data: Data, _ maxPixel: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return UIImage(data: data) }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel * 2
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return UIImage(data: data) }
        return UIImage(cgImage: cg)
    }
}

struct RemoteImage: View {
    let url: URL?
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.gray.opacity(0.2)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed {
                Image(systemName: "cube").foregroundStyle(.secondary)
            }
        }
        .clipped()
        .task(id: url) {
            guard let url else { failed = true; return }
            image = await ImageCache.shared.image(for: url)
            failed = image == nil
        }
    }
}
