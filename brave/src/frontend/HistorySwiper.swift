/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */


class HistorySwiper {

    var topLevelView: UIView!
    var webViewContainer: UIView!

    func setup(topLevelView topLevelView: UIView, webViewContainer: UIView) {
        self.topLevelView = topLevelView
        self.webViewContainer = webViewContainer

        goBackSwipe.edges = .Left
        goForwardSwipe.edges = .Right
    }

    lazy var goBackSwipe: UIScreenEdgePanGestureRecognizer = {
        let pan = UIScreenEdgePanGestureRecognizer(target: self, action: "screenLeftEdgeSwiped:")
        self.topLevelView.addGestureRecognizer(pan)
        return pan
    }()

    lazy var goForwardSwipe: UIScreenEdgePanGestureRecognizer = {
        let pan = UIScreenEdgePanGestureRecognizer(target: self, action: "screenRightEdgeSwiped:")
        self.topLevelView.addGestureRecognizer(pan)
        return pan
    }()

    func screenWidth() -> CGFloat {
        return topLevelView.frame.width
    }

    private func handleSwipe(recognizer: UIScreenEdgePanGestureRecognizer) {
        let p = recognizer.locationInView(recognizer.view)

        let shouldReturnToZero = (recognizer.edges == .Left) ? p.x < screenWidth() / 2.0 : p.x > screenWidth() / 2.0

        if recognizer.state == .Ended || recognizer.state == .Cancelled || recognizer.state == .Failed {
            UIView.animateWithDuration(0.25, animations: {
                if shouldReturnToZero {
                    self.webViewContainer.transform = CGAffineTransformMakeTranslation(0, self.webViewContainer.transform.ty)
                } else {
                    let x = (recognizer.edges == .Left) ? self.screenWidth() : -self.screenWidth()
                    self.webViewContainer.transform = CGAffineTransformMakeTranslation(x, self.webViewContainer.transform.ty)
                    self.webViewContainer.alpha = 0
                }
                }, completion: { (Bool) -> Void in
                    if !shouldReturnToZero {
                        if recognizer.edges == .Left {
                            getApp().browserViewController.tabManager.selectedTab?.webView?.goBack()
                        } else {
                            getApp().browserViewController.tabManager.selectedTab?.webView?.goForward()
                        }

                        self.webViewContainer.transform = CGAffineTransformMakeTranslation(0, self.webViewContainer.transform.ty)
                        UIView.animateWithDuration(0.1) {
                            self.webViewContainer.alpha = 1.0
                            getApp().browserViewController.scrollController.edgeSwipingActive = false
                        }
                    } else {
                        getApp().browserViewController.scrollController.edgeSwipingActive = false
                    }
            })
        } else {
            getApp().browserViewController.scrollController.edgeSwipingActive = true
            let tx = (recognizer.edges == .Left) ? p.x : p.x - screenWidth()
            webViewContainer.transform = CGAffineTransformMakeTranslation(tx, self.webViewContainer.transform.ty)
        }
    }

    @objc func screenRightEdgeSwiped(recognizer: UIScreenEdgePanGestureRecognizer) {
        handleSwipe(recognizer)
    }
    
    @objc func screenLeftEdgeSwiped(recognizer: UIScreenEdgePanGestureRecognizer) {
        handleSwipe(recognizer)
    }
}