
import UIKit
import Social
import MobileCoreServices

class ShareViewController: SLComposeServiceViewController {

    override func isContentValid() -> Bool {
        return true
    }

    override func didSelectPost() {
        return
    }

    override func configurationItems() -> [AnyObject]! {
        let item: NSExtensionItem = extensionContext!.inputItems[0] as! NSExtensionItem
        let itemProvider: NSItemProvider = item.attachments![0] as! NSItemProvider
        var url: NSString = ""
        let type = kUTTypeURL as String
        if itemProvider.hasItemConformingToTypeIdentifier(type) {
            itemProvider.loadItemForTypeIdentifier(type, options: nil, completionHandler: {
                (urlItem, error) in
                url = (urlItem as! NSURL).absoluteString.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.alphanumericCharacterSet())!
                UIApplication.sharedApplication().openURL(NSURL(string: "brave://open-url?url=\(url)")!)
                self.cancel()
            })
        }

        return []
    }

    override func willMoveToParentViewController(parent: UIViewController?) {
        view.alpha = 0
    }

    override func didMoveToParentViewController(parent: UIViewController?) {
        view.alpha = 1
    }
}
