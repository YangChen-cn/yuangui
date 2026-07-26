import AppKit

final class DiaryTextView: NSTextView {
    var onPasteImage: (() -> Bool)?

    override func paste(_ sender: Any?) {
        if onPasteImage?() == true {
            return
        }
        super.paste(sender)
    }
}
