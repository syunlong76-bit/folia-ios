// RangeStreamResourceLoader.swift
//
// M1 播放内核：Range 流代理（native-arch.md §6）。
// - 只为不支持 Range 206 的网关服务：把 200 全量流切成 AVPlayer 要的字节片。
// - 死代码已删：从未 resume 的 completion-handler 版 dataTask 不存在，只留 delegate 流式一条。
// - contentType 按响应 mimeType 或 URL 后缀推导（UTType），禁硬编码 mp3。
// - 流式 session 完成即 finishTasksAndInvalidate；探测 session 同理（见 EdgeOneAPIClient）。
// - 补 requestedLength == -1（未知长度）分支：按开区间 bytes=<offset>- 请求。
// - 302 跟随策略：默认跟随（m801.music.126.net 实测直连通，无需特殊 header/cookie；
//   平台流地址若以 302 分发到 CDN，拒绝跟随会被误判，不盲抄拒绝跟随）。

import AVFoundation
import Foundation
import UniformTypeIdentifiers

final class RangeStreamResourceLoader: NSObject, AVAssetResourceLoaderDelegate {

    static let customScheme = "folia-stream"
    static let shared = RangeStreamResourceLoader()

    private let loaderQueue = DispatchQueue(label: "com.folia.stream.loader")
    private var activeTasks: [ObjectIdentifier: URLSessionDataTask] = [:]
    private var activeSessions: [ObjectIdentifier: URLSession] = [:]

    private override init() { super.init() }

    /// 生成绑定代理的 AVURLAsset，供 PlaybackEngine 使用。
    /// 只有 folia-stream scheme 的 URL 才挂 delegate；直连 https URL 不经过本代理。
    static func makeAsset(for url: URL) -> AVURLAsset {
        let asset = AVURLAsset(url: url)
        if url.scheme == Self.customScheme {
            asset.resourceLoader.setDelegate(shared, queue: shared.loaderQueue)
        }
        return asset
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let customURL = loadingRequest.request.url,
              var comps = URLComponents(url: customURL, resolvingAgainstBaseURL: false) else {
            return false
        }
        comps.scheme = "https"
        guard let realURL = comps.url else { return false }

        var request = URLRequest(url: realURL)
        var requestedStart: Int64 = 0

        if let dataReq = loadingRequest.dataRequest {
            requestedStart = dataReq.requestedOffset
            if dataReq.requestsAllDataToEndOfResource || dataReq.requestedLength == -1 {
                // 未知长度 / 全量到尾：开区间请求，长度由响应头定。
                request.setValue("bytes=\(requestedStart)-", forHTTPHeaderField: "Range")
            } else {
                let end = requestedStart + Int64(dataReq.requestedLength) - 1
                request.setValue("bytes=\(requestedStart)-\(end)", forHTTPHeaderField: "Range")
            }
        } else {
            // 只有 contentInformationRequest：取首字节探长度与类型。
            request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        }

        let taskId = ObjectIdentifier(loadingRequest)

        // 跟踪累计收到的字节，用于兼容网关忽略 Range 直接返回 200 全量流的极端情况。
        var bytesSkipped: Int64 = 0
        var serverReturnedFull200 = false

        let delegateProxy = StreamTaskDelegate(
            onResponse: { [weak self] response in
                self?.loaderQueue.async {
                    guard let httpResp = response as? HTTPURLResponse else { return }
                    serverReturnedFull200 = (httpResp.statusCode == 200 && requestedStart > 0)

                    if let infoReq = loadingRequest.contentInformationRequest {
                        // contentType 按响应 mime 或 URL 后缀推导，禁硬编码 mp3
                        //（QQ/酷狗流可能是 m4a/flac）。
                        if let contentType = Self.contentType(for: httpResp, url: realURL) {
                            infoReq.contentType = contentType
                        }
                        infoReq.isByteRangeAccessSupported =
                            httpResp.statusCode == 206
                            || httpResp.value(forHTTPHeaderField: "Accept-Ranges") == "bytes"

                        if let contentRange = httpResp.value(forHTTPHeaderField: "Content-Range"),
                           let totalStr = contentRange.split(separator: "/").last,
                           let totalLen = Int64(totalStr) {
                            infoReq.contentLength = totalLen
                        } else if httpResp.expectedContentLength > 0 {
                            infoReq.contentLength = httpResp.expectedContentLength
                        }
                    }
                }
            },
            onData: { [weak self] chunk in
                self?.loaderQueue.async {
                    guard let dataReq = loadingRequest.dataRequest else { return }

                    if serverReturnedFull200 && bytesSkipped < requestedStart {
                        let remainingSkip = requestedStart - bytesSkipped
                        if Int64(chunk.count) <= remainingSkip {
                            bytesSkipped += Int64(chunk.count)
                            return
                        } else {
                            let validSlice = chunk.dropFirst(Int(remainingSkip))
                            bytesSkipped = requestedStart
                            dataReq.respond(with: Data(validSlice))
                            return
                        }
                    }

                    dataReq.respond(with: chunk)
                }
            },
            onComplete: { [weak self] error in
                self?.loaderQueue.async {
                    self?.activeTasks.removeValue(forKey: taskId)
                    // 流式 session 完成即 invalidate，防一次拖动多次 range 请求累积 session。
                    if let session = self?.activeSessions.removeValue(forKey: taskId) {
                        session.finishTasksAndInvalidate()
                    }
                    if let error {
                        loadingRequest.finishLoading(with: error)
                    } else {
                        loadingRequest.finishLoading()
                    }
                }
            }
        )

        let streamingSession = URLSession(configuration: .default, delegate: delegateProxy, delegateQueue: nil)
        let streamingTask = streamingSession.dataTask(with: request)
        activeTasks[taskId] = streamingTask
        activeSessions[taskId] = streamingSession
        streamingTask.resume()

        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        let taskId = ObjectIdentifier(loadingRequest)
        activeTasks[taskId]?.cancel()
        activeTasks.removeValue(forKey: taskId)
        if let session = activeSessions.removeValue(forKey: taskId) {
            session.finishTasksAndInvalidate()
        }
    }

    // MARK: - contentType 推导

    /// 先看响应 mimeType，再看 URL 后缀；都推不出来返回 nil（不硬编码 mp3）。
    private static func contentType(for response: HTTPURLResponse, url: URL) -> String? {
        if let mime = response.mimeType, let type = UTType(mimeType: mime) {
            return type.identifier
        }
        let ext = url.pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext) {
            return type.identifier
        }
        return nil
    }
}

// MARK: - 流式 delegate（只做转发，回调内禁锁/禁分配以外的重活）

private final class StreamTaskDelegate: NSObject, URLSessionDataDelegate {
    let onResponse: (URLResponse) -> Void
    let onData: (Data) -> Void
    let onComplete: (Error?) -> Void

    init(onResponse: @escaping (URLResponse) -> Void,
         onData: @escaping (Data) -> Void,
         onComplete: @escaping (Error?) -> Void) {
        self.onResponse = onResponse
        self.onData = onData
        self.onComplete = onComplete
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        onResponse(response)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        onData(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onComplete(error)
    }
}
