import Foundation
import UIKit

/// (66) 文件夹前台监视（假生效「文件夹监视键」的部分做
/// 真）：iOS 没有常驻后台文件夹监视——本面在 App 处于前
/// 台期间，对 LocalLibrary62 已导入文件夹挂 DispatchSource
/// 目录事件源，内容变化去抖 1.5 秒后触发 rescanFolders()
/// 自动收新文件；App 进后台即撤源、回前台重挂。开关
/// folderWatchEnabled62 关时不挂源（手动重扫仍可用）。
/// 设置行文案按此前台口径如实标注，不冒充常驻监视。
final class FolderWatch62 {

    static let shared = FolderWatch62()

    private var sources: [DispatchSourceFileSystemObject] = []
    private var accessed: [URL] = []
    private var debounce: DispatchWorkItem?
    private var lifecycleInstalled = false

    private init() {}

    /// WC62Bootstrap 启动时调一次：装生命周期观察并按当前
    /// 状态刷新监视源。
    func startIfEnabled() {
        if !lifecycleInstalled {
            lifecycleInstalled = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(appDidBecomeActive),
                name: UIApplication.didBecomeActiveNotification, object: nil)
            NotificationCenter.default.addObserver(
                self, selector: #selector(appWillResignActive),
                name: UIApplication.willResignActiveNotification, object: nil)
        }
        refresh()
    }

    @objc private func appDidBecomeActive() { refresh() }

    @objc private func appWillResignActive() { teardown() }

    /// 按开关与文件夹清单重建监视源（设置开关切换时调用）。
    func refresh() {
        teardown()
        guard SettingsStore.folderWatchEnabled62,
              UIApplication.shared.applicationState == .active else { return }
        for folder in LocalLibrary62.shared.folders {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: folder.bookmark,
                                     options: [], relativeTo: nil,
                                     bookmarkDataIsStale: &stale), !stale else { continue }
            let scoped = url.startAccessingSecurityScopedResource()
            let fd = open(url.path, O_EVTONLY)
            guard fd >= 0 else {
                if scoped { url.stopAccessingSecurityScopedResource() }
                continue
            }
            if scoped { accessed.append(url) }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .extend, .rename, .delete],
                queue: .main)
            source.setEventHandler { [weak self] in self?.scheduleRescan() }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }
        if !sources.isEmpty {
            Breadcrumbs.log("folderwatch66 active count=\(sources.count)")
        }
    }

    private func scheduleRescan() {
        debounce?.cancel()
        let work = DispatchWorkItem {
            Breadcrumbs.log("folderwatch66 change rescan=1")
            LocalLibrary62.shared.rescanFolders()
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func teardown() {
        debounce?.cancel()
        debounce = nil
        sources.forEach { $0.cancel() }
        sources = []
        accessed.forEach { $0.stopAccessingSecurityScopedResource() }
        accessed = []
    }
}
