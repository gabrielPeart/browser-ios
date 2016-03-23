/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared

class BraveBrowserViewController : BrowserViewController {
    override func applyTheme(themeName: String) {
        super.applyTheme(themeName)

        toolbar?.accessibilityLabel = "toolbar thing"
        headerBackdrop.accessibilityLabel = "headerBackdrop"
        webViewContainerBackdrop.accessibilityLabel = "webViewContainerBackdrop"
        webViewContainer.accessibilityLabel = "webViewContainer"
        statusBarOverlay.accessibilityLabel = "statusBarOverlay"
        urlBar.accessibilityLabel = "BraveUrlBar"

        // TODO sorry, I am in a rush, but this needs to be removed from the view heirarchy properly
        headerBackdrop.backgroundColor = UIColor.clearColor()
        headerBackdrop.alpha = 0
        headerBackdrop.hidden = true

        header.blurStyle = .Dark
        footerBackground?.blurStyle = .Dark

        toolbar?.applyTheme(themeName)
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)

        self.updateToolbarStateForTraitCollection(self.traitCollection)
        setupConstraints()
        if BraveApp.shouldRestoreTabs() {
            tabManager.restoreTabs()
        } else {
            tabManager.addTabAndSelect();
        }

        updateTabCountUsingTabManager(tabManager, animated: false)

        footer.accessibilityLabel = "footer"
        footerBackdrop.accessibilityLabel = "footerBackdrop"

        // With this color, it matches to default semi-transparent state of the toolbar
        // The value is hand-picked to match the effect on the url bar, we don't have a color constant for this elsewhere
        statusBarOverlay.backgroundColor = DeviceInfo.isBlurSupported() ? UIColor(white: 0.255, alpha: 1.0) : UIColor.blackColor()

        goBackSwipe.edges = .Left
        goForwardSwipe.edges = .Right
    }

    lazy var goBackSwipe: UIScreenEdgePanGestureRecognizer = {
        let pan = UIScreenEdgePanGestureRecognizer(target: self, action: "screenLeftEdgeSwiped:")
        self.view.addGestureRecognizer(pan)
        return pan
    }()

    lazy var goForwardSwipe: UIScreenEdgePanGestureRecognizer = {
        let pan = UIScreenEdgePanGestureRecognizer(target: self, action: "screenRightEdgeSwiped:")
        self.view.addGestureRecognizer(pan)
        return pan
    }()

    private func handleSwipe(recognizer: UIScreenEdgePanGestureRecognizer) {
        let p = recognizer.locationInView(recognizer.view)

        let shouldReturnToZero = (recognizer.edges == .Left) ? p.x < self.view.frame.width / 2.0 : p.x > self.view.frame.width / 2.0

        if recognizer.state == .Ended || recognizer.state == .Cancelled || recognizer.state == .Failed {
            UIView.animateWithDuration(0.25, animations: {
                if shouldReturnToZero {
                    self.webViewContainer.transform = CGAffineTransformMakeTranslation(0, self.webViewContainer.transform.ty)
                } else {
                    let x = (recognizer.edges == .Left) ? self.view.frame.width : -self.view.frame.width
                    self.webViewContainer.transform = CGAffineTransformMakeTranslation(x, self.webViewContainer.transform.ty)
                    self.webViewContainer.alpha = 0
                }
            }, completion: { (Bool) -> Void in
                if !shouldReturnToZero {
                    if recognizer.edges == .Left {
                        self.tabManager.selectedTab?.webView?.goBack()
                    } else {
                        self.tabManager.selectedTab?.webView?.goForward()
                    }
                }

                self.webViewContainer.transform = CGAffineTransformMakeTranslation(0, self.webViewContainer.transform.ty)
                UIView.animateWithDuration(0.1) {
                    self.webViewContainer.alpha = 1.0
                    self.scrollController.edgeSwipingActive = false
                }
            })
        } else {
            self.scrollController.edgeSwipingActive = true
            let tx = (recognizer.edges == .Left) ? p.x : p.x - view.frame.width
            webViewContainer.transform = CGAffineTransformMakeTranslation(tx, self.webViewContainer.transform.ty)
        }
    }

    @objc func screenRightEdgeSwiped(recognizer: UIScreenEdgePanGestureRecognizer) {
        handleSwipe(recognizer)
    }

    @objc func screenLeftEdgeSwiped(recognizer: UIScreenEdgePanGestureRecognizer) {
        handleSwipe(recognizer)
    }

    override func SELtappedTopArea() {
     //   scrollController.showToolbars(animated: true)
    }

    func braveWebContainerConstraintSetup() {
        webViewContainer.snp_remakeConstraints { make in
            make.left.right.equalTo(self.view)
            make.top.equalTo(self.statusBarOverlay.snp_bottom).offset(UIConstants.ToolbarHeight)
            make.height.equalTo(self.view.snp_height).offset(-BraveApp.statusBarHeight())
        }
    }

    override func setupConstraints() {
        super.setupConstraints()
        braveWebContainerConstraintSetup()
    }

    override func updateViewConstraints() {
        super.updateViewConstraints()

        // Setup the bottom toolbar
        toolbar?.snp_remakeConstraints { make in
            make.edges.equalTo(self.footerBackground!)
        }

        braveWebContainerConstraintSetup()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let h = BraveApp.isIPhoneLandscape() ? 0 : 20
        statusBarOverlay.snp_remakeConstraints { make in
            make.top.left.right.equalTo(self.view)
            make.height.equalTo(h)
        }
    }
    
    override func updateToolbarStateForTraitCollection(newCollection: UITraitCollection) {
        super.updateToolbarStateForTraitCollection(newCollection)
        braveWebContainerConstraintSetup()
    }
}
