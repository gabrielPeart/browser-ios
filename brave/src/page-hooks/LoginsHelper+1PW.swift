import Foundation

import OnePasswordExtension
import Shared
import Storage
import Deferred

var iPadOffscreenView = UIView(frame: CGRectMake(3000,0,1,1))
let tagFor1PwSnackbar = 8675309
var noPopupOnSites: [String] = []

let kPrefName3rdPartyPasswordShortcutEnabled = "thirdPartyPasswordShortcutEnabled"

extension LoginsHelper {
    func thirdPartyPasswordRegisterPageListeners() {
        guard let wv = browser?.webView else { return }
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "hideOnPageChange:", name: kNotificationPageUnload, object: wv)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "checkOnPageLoaded:", name: BraveWebView.kNotificationWebViewLoadCompleteOrFailed, object: wv)
    }

    func thirdPartyPasswordSnackbar() {
        let isEnabled = BraveApp.getPrefs()?.boolForKey(kPrefName3rdPartyPasswordShortcutEnabled) ?? true
        if !BraveApp.is3rdPartyPasswordManagerInstalled(refreshLookup: false) || !isEnabled {
            return
        }

        guard let url = browser?.webView?.URL else { return }
        isInNoShowList(url).upon {
            [weak self]
            result in
            if result {
                return
            }

            ensureMainThread {
                [weak self] in
                guard let safeSelf = self else { return }
                if let snackBar = safeSelf.snackBar {
                    if safeSelf.browser?.bars.map({ $0.tag }).indexOf(tagFor1PwSnackbar) != nil {
                        return // already have a 1PW snackbar active for this tab
                    }

                    safeSelf.browser?.removeSnackbar(snackBar)
                }

                safeSelf.snackBar = SnackBar(attrText: NSAttributedString(string: "Sign in with your Password Manager"), img: UIImage(named: "onepassword-button"), buttons: [])
                safeSelf.snackBar!.tag = tagFor1PwSnackbar
                let button = UIButton()
                button.autoresizingMask = [.FlexibleWidth, .FlexibleHeight]
                safeSelf.snackBar!.addSubview(button)
                button.addTarget(self, action: "onExecuteTapped", forControlEvents: .TouchUpInside)

                let close = UIButton(frame: CGRectMake(safeSelf.snackBar!.frame.width - 40, 0, 40, 40))
                close.setImage(UIImage(named: "stop")!, forState: .Normal)
                close.addTarget(self, action: "onCloseTapped", forControlEvents: .TouchUpInside)
                close.tintColor = UIColor.blackColor()
                close.autoresizingMask = [.FlexibleLeftMargin]
                safeSelf.snackBar!.addSubview(close)

                safeSelf.browser?.addSnackbar(safeSelf.snackBar!)
            }
        }

    }

    @objc func onCloseTapped() {
        if let s = snackBar {
            self.browser?.removeSnackbar(s)

            guard let host = browser?.webView?.URL?.hostWithGenericSubdomainPrefixRemoved() else { return }
            noPopupOnSites.append(host)
            #if PW_DB
                getApp().profile!.db.write("INSERT INTO \(TableOnePasswordNoPopup) (domain) VALUES (?)", withArgs: [host])
            #endif
        }
    }

    @objc func checkOnPageLoaded(notification: NSNotification) {
        if notification.object !== browser?.webView {
            return
        }
        delay(0.1) {
            [weak self] in
            let result = self?.browser?.webView?.stringByEvaluatingJavaScriptFromString("document.querySelectorAll(\"input[type='password']\").length !== 0")
            if let ok = result where ok == "true" {
                self?.thirdPartyPasswordSnackbar()
            }
        }
    }

    @objc func hideOnPageChange(notification: NSNotification) {
        if let snackBar = snackBar where snackBar.tag == tagFor1PwSnackbar {
            browser?.removeSnackbar(snackBar)
        }
    }

    @objc func onExecuteTapped() {
        let isIPad = UIDevice.currentDevice().userInterfaceIdiom == .Pad

        if !isIPad {
            browser?.removeSnackbar(snackBar!)
            UIAlertController.hackyHideOn(true)
        }

        let sender:UIView =  snackBar!

        if isIPad && iPadOffscreenView.superview == nil {
            getApp().browserViewController.view.addSubview(iPadOffscreenView)
        }

        OnePasswordExtension.sharedExtension().fillItemIntoWebView(browser!.webView!, forViewController: getApp().browserViewController, sender: sender, showOnlyLogins: true) { (success, error) -> Void in
            if isIPad {
                iPadOffscreenView.removeFromSuperview()
            } else {
                UIAlertController.hackyHideOn(false)
            }

            if success == false {
                print("Failed to fill into webview: <\(error)>")
            }
            self.browser?.removeSnackbar(self.snackBar!)
        }

        var found = false

        // recurse through items until the 1pw share item is found
        func selectShareItem(view: UIView, shareItemName: String) {
            if found {
                return
            }

            for subview in view.subviews {
                if subview.description.contains("UICollectionViewControllerWrapperView") && subview.subviews.first?.subviews.count > 1 {
                    let wrapperCell = subview.subviews.first?.subviews[1] as? UICollectionViewCell
                    if let collectionView = wrapperCell?.subviews.first?.subviews.first?.subviews.first as? UICollectionView {

                        // As a safe upper bound, just look at 10 items max
                        for i in 0..<10 {
                            let indexPath = NSIndexPath(forItem: i, inSection: 0)
                            let suspectCell = collectionView.cellForItemAtIndexPath(indexPath)
                            if suspectCell == nil {
                                break;
                            }
                            if suspectCell?.subviews.first?.subviews.last?.description.contains(shareItemName) ?? false {
                                collectionView.delegate?.collectionView?(collectionView, didSelectItemAtIndexPath:indexPath)
                                found = true
                            }
                        }

                        return
                    }
                }
                selectShareItem(subview, shareItemName: shareItemName)
            }
        }

        delay(0.2) {
            // The event loop needs to run for the share screen to reliably be showing, a delay of zero also works.
            selectShareItem(getApp().window!, shareItemName: "1Password")

            if !found {
                if UIDevice.currentDevice().userInterfaceIdiom == .Pad {
                    UIActivityViewController.hackyDismissal()
                    iPadOffscreenView.removeFromSuperview()
                    BraveApp.getPrefs()?.setBool(false, forKey: kPrefName3rdPartyPasswordShortcutEnabled)
                    BraveApp.showErrorAlert(title: "Password shortcut error", error: "Disabling due to internal error. Please report this problem to support@brave.com.")
                } else {
                    // Just show the regular share screen, this isn't a fatal problem on iPhone
                    UIAlertController.hackyHideOn(false)
                }
            }
        }
    }

    // Using a DB-backed storage for this is under consideration.
    // Use a similar Deferred-style so switching to the DB method is seamless
    func isInNoShowList(url: NSURL)  -> Deferred<Bool>  {
        let deferred = Deferred<Bool>()
        delay(0) {
            var result = false
            if let host = url.hostWithGenericSubdomainPrefixRemoved() {
                result = noPopupOnSites.contains(host)
            }
            deferred.fill(result)
        }
        return deferred
    }
}
