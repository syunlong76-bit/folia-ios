import UIKit
import UniformTypeIdentifiers

/// (66) 媒体缓存目录选择器：UIDocumentPicker 选文件夹
/// （DS 改判「缓存目录自选」的 UI 面）。选中后回调文件夹
/// URL，存书签/换目录由 MediaCache62.setCustomDirectory
/// 承接；取消时回调 nil。
final class MediaCacheDirPicker66: NSObject, UIDocumentPickerDelegate {

    private static var retained: MediaCacheDirPicker66?
    private var completion: ((URL?) -> Void)?

    static func present(from host: UIViewController,
                        completion: @escaping (URL?) -> Void) {
        let picker = MediaCacheDirPicker66()
        picker.completion = completion
        retained = picker
        let controller = UIDocumentPickerViewController(
            forOpeningContentTypes: [.folder], asCopy: false)
        controller.delegate = picker
        controller.allowsMultipleSelection = false
        host.present(controller, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        let url = urls.first
        Breadcrumbs.log("mediacache66 dir picked=\(url != nil ? 1 : 0)")
        completion?(url)
        Self.retained = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion?(nil)
        Self.retained = nil
    }
}
