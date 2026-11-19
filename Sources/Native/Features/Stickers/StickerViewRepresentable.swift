import SwiftUI

/// StickerView 的 SwiftUI 包装（3.7 (24)，纯新增）：供原生
/// SwiftUI 表面（搜索空态）挂贴纸用。
struct StickerViewRepresentable: UIViewRepresentable {
    let asset: String
    var mode: StickerView.PlayMode = .loop

    func makeUIView(context: Context) -> StickerView {
        let view = StickerView()
        view.crumbScene = "search-empty"
        view.setSticker(asset, mode: mode)
        return view
    }

    func updateUIView(_ view: StickerView, context: Context) {
        if view.assetName != asset || view.playMode != mode {
            view.setSticker(asset, mode: mode)
        }
    }
}
