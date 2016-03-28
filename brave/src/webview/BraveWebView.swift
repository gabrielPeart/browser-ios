/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit
import Shared

func configureActiveCrashReporter(_:Bool?) {}

let kNotificationPageUnload = "kNotificationPageUnload"

func convertNavActionToWKType(type:UIWebViewNavigationType) -> WKNavigationType {
    return WKNavigationType(rawValue: type.rawValue)!
}

class ContainerWebView : WKWebView {
    weak var legacyWebView: BraveWebView?
}

var nullWebView: WKWebView = WKWebView()
var nullWKNavigation: WKNavigation = WKNavigation()

enum KVOStrings: String {
    case kvoCanGoBack = "canGoBack"
    case kvoCanGoForward = "canGoForward"
    case kvoLoading = "loading"
    case kvoURL = "URL"
    case kvoEstimatedProgress = "estimatedProgress"

    static let allValues = [kvoCanGoBack, kvoCanGoForward, kvoLoading, kvoURL, kvoEstimatedProgress]
}

class BraveWebView: UIWebView {
    let specialStopLoadUrl = "http://localhost.stop.load"
    static let kNotificationWebViewLoadCompleteOrFailed = "kNotificationWebViewLoadCompleteOrFailed"
    static let kContextMenuBlockNavigation = 8675309
    weak var navigationDelegate: WKNavigationDelegate?
    weak var UIDelegate: WKUIDelegate?
    lazy var configuration: BraveWebViewConfiguration = { return BraveWebViewConfiguration(webView: self) }()
    lazy var backForwardList: WebViewBackForwardList = { return WebViewBackForwardList(webView: self) } ()
    var progress: WebViewProgress?
    var certificateInvalidConnection:NSURLConnection?

    var estimatedProgress: Double = 0
    var title: String = "" {
        didSet {
            if let item = backForwardList.currentItem {
                item.title = title
            }
        }
    }

    var URL: NSURL?

    var uniqueId = -1

    var internalIsLoadingEndedFlag: Bool = false;
    var knownFrameContexts = Set<NSObject>()
    static var containerWebViewForCallbacks = { return ContainerWebView() }()
    // From http://stackoverflow.com/questions/14268230/has-anybody-found-a-way-to-load-https-pages-with-an-invalid-server-certificate-u
    var loadingUnvalidatedHTTPSPage: Bool = false

    // This gets set as soon as it is available from the first UIWebVew created
    static var webviewBuiltinUserAgent: String?

    // To mimic WKWebView we need this property. And, to easily overrride where Firefox code is setting it, we hack the setter,
    // so that a custom agent is set always to our kDesktopUserAgent.
    // A nil customUserAgent means to use the default which is correct.
    //TODO setting the desktop agent doesn't currently work, see note below)
    var customUserAgent:String? {
        willSet {
            if self.customUserAgent == newValue || newValue == nil {
                return
            }
            self.customUserAgent = newValue == nil ? nil : kDesktopUserAgent
            // The following doesn't work, we need to kill and restart the webview, and restore its history state
            // for this setting to take effect
            //      let defaults = NSUserDefaults(suiteName: AppInfo.sharedContainerIdentifier())!
            //      defaults.registerDefaults(["UserAgent": (self.customUserAgent ?? "")])
        }
    }

    static let idToWebview = NSMapTable(keyOptions: .StrongMemory, valueOptions: .WeakMemory)
    static var webViewCounter = 0
    // Needed to identify webview in url protocol
    func generateUniqueUserAgent() {
        BraveWebView.webViewCounter++
        if let webviewBuiltinUserAgent = BraveWebView.webviewBuiltinUserAgent {
            let userAgent = webviewBuiltinUserAgent + String(format:" _id/%06d", BraveWebView.webViewCounter)
            let defaults = NSUserDefaults(suiteName: AppInfo.sharedContainerIdentifier())!
            defaults.registerDefaults(["UserAgent": userAgent ])
            self.uniqueId = BraveWebView.webViewCounter
            BraveWebView.idToWebview.setObject(self, forKey: uniqueId)
        } else {
            if BraveWebView.webViewCounter > 1 {
                // We shouldn't get here, we allow the first webview to have no user agent, and we special-case the look up. The first webview inits the UA from its built in defaults
                // If we get to more than one, just use a hard coded user agent, to avoid major bugs
                let device = UIDevice.currentDevice().userInterfaceIdiom == .Phone ? "iPhone" : "iPad"
                BraveWebView.webviewBuiltinUserAgent = "Mozilla/5.0 (\(device)) AppleWebKit/601.1.46 (KHTML, like Gecko) Mobile/13C75"
            }
            BraveWebView.idToWebview.setObject(self, forKey: 1) // the first webview, we don't have the user agent just yet
        }
    }

    static func userAgentToWebview(let ua: String?) -> BraveWebView? {
        guard let ua = ua else { return nil }
        guard let loc = ua.rangeOfString("_id/") else {
            // the first created webview doesn't have this id set (see webviewBuiltinUserAgent to explain)
            return idToWebview.objectForKey(1) as? BraveWebView
        }
        let keyString = ua.substringWithRange(Range(start: loc.endIndex, end: loc.endIndex.advancedBy(6)))
        guard let key = Int(keyString) else { return nil }
        return idToWebview.objectForKey(key) as? BraveWebView
    }

    var triggeredLocationCheckTimer = NSTimer()
    // On page load, the contentSize of the webview is updated. If the webview has not been notified of a page change (i.e. shouldStartLoadWithRequest was never called) then 'loading' will be false, and we should check the page location using JS.
    func contentSizeChangeDetected() {

        (getApp().browserViewController as! BraveBrowserViewController).historySwiper.restoreWebview()

        if triggeredLocationCheckTimer.valid || loading {
            return
        }

        // Add a time delay so that multiple calls are aggregated
        triggeredLocationCheckTimer = NSTimer.scheduledTimerWithTimeInterval(0.15, target: self, selector: kTimeoutCheckLocation, userInfo: nil, repeats: false)
    }

    let kTimeoutCheckLocation = Selector("timeoutCheckLocation")
    @objc func timeoutCheckLocation() {
        if loading {
            return
        }
        // Pushstate navigation can cause this case (see brianbondy.com), as well as sites for which simple pushstate detection doesn't work:
        // youtube and yahoo news are examples of this (http://stackoverflow.com/questions/24297929/javascript-to-listen-for-url-changes-in-youtube-html5-player)
        guard let location = self.stringByEvaluatingJavaScriptFromString("window.location.href"), currentUrl = URL?.absoluteString else { return }
        if location == currentUrl || location.contains("about:") || location.contains("//localhost") {
            return
        }
        URL = NSURL(string: location)
        title = stringByEvaluatingJavaScriptFromString("document.title") ?? ""
        internalIsLoadingEndedFlag = false // need to set this to bypass loadingCompleted() precondition
        loadingCompleted()
        kvoBroadcast()
        #if DEBUG
            print("Page change detected by content size change triggered timer: \(location)")
        #endif
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    private func commonInit() {
        print("webview init ")
        generateUniqueUserAgent()

        progress = WebViewProgress(parent: self)

        delegate = self
        scalesPageToFit = true

        scrollView.showsHorizontalScrollIndicator = false

        #if !TEST
            // if (BraveUX.IsHighLoadAnimationAllowed && !BraveUX.IsOverrideScrollingSpeedAndMakeSlower) {
            let rate = UIScrollViewDecelerationRateFast + (UIScrollViewDecelerationRateNormal - UIScrollViewDecelerationRateFast) * 0.5;
            scrollView.setValue(NSValue(CGSize: CGSizeMake(rate, rate)), forKey: "_decelerationFactor")
            //    } else {
            //      scrollView.decelerationRate = UIScrollViewDecelerationRateFast
            //    }
        #endif

    }

    func internalProgressNotification(notification: NSNotification) {
        //print("\(notification.userInfo?["WebProgressEstimatedProgressKey"])")
        if (notification.userInfo?["WebProgressEstimatedProgressKey"] as? Double ?? 0 > 0.99) {
            delegate?.webViewDidFinishLoad?(self)
        }
    }

    override var loading: Bool {
        get {
            if internalIsLoadingEndedFlag {
                // we detected load complete internally –UIWebView sometimes stays in a loading state (i.e. bbc.com)
                return false
            }
            return super.loading
        }
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    func destroy() {
        NSNotificationCenter.defaultCenter().removeObserver(self)
        progress = nil
    }

    deinit {
        print("webview deinit \(title) ")
    }

    let internalProgressStartedNotification = "WebProgressStartedNotification"
    let internalProgressChangedNotification = "WebProgressEstimateChangedNotification"
    let internalProgressFinishedNotification = "WebProgressFinishedNotification" // Not usable

    override func loadRequest(request: NSURLRequest) {
        guard let internalWebView = valueForKeyPath("documentView.webView") else { return }
        NSNotificationCenter.defaultCenter().removeObserver(self, name: internalProgressChangedNotification, object: internalWebView)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "internalProgressNotification:", name: internalProgressChangedNotification, object: internalWebView)

        if let url = request.URL where !url.absoluteString.contains(specialStopLoadUrl) {
            URL = request.URL
        }
        super.loadRequest(request)
    }

    func loadingCompleted() {
        if internalIsLoadingEndedFlag {
            return
        }
        internalIsLoadingEndedFlag = true

        if let nd = navigationDelegate {
            BraveWebView.containerWebViewForCallbacks.legacyWebView = self
            nd.webView?(BraveWebView.containerWebViewForCallbacks, didFinishNavigation: nullWKNavigation)
        }

        configuration.userContentController.injectJsIntoPage()
        NSNotificationCenter.defaultCenter().postNotificationName(BraveWebView.kNotificationWebViewLoadCompleteOrFailed, object: nil)
        LegacyUserContentController.injectJsIntoAllFrames(self, script: "document.body.style.webkitTouchCallout='none'")

        print("Getting favicons")
        stringByEvaluatingJavaScriptFromString("__firefox__.favicons.getFavicons()")

        #if !TEST
            replaceAdImages(self)
        #endif
    }

    func kvoBroadcast(kvos: [KVOStrings]? = nil) {
        if let _kvos = kvos {
            for item in _kvos {
                willChangeValueForKey(item.rawValue)
                didChangeValueForKey(item.rawValue)
            }
        } else {
            // send all
            kvoBroadcast(KVOStrings.allValues)
        }
    }

    func setScalesPageToFit(setPages: Bool!) {
        self.scalesPageToFit = setPages
    }

    func canNavigateBackward() -> Bool {
        return self.canGoBack
    }

    func canNavigateForward() -> Bool {
        return self.canGoForward
    }

    func reloadFromOrigin() {
        progress?.setProgress(0.3)
        self.reload()
    }

    override func stopLoading() {
        super.stopLoading()
        loadRequest(NSURLRequest(URL: NSURL(string: specialStopLoadUrl)!))
        self.progress?.reset()
    }

    private func convertStringToDictionary(text: String?) -> [String:AnyObject]? {
        if let data = text?.dataUsingEncoding(NSUTF8StringEncoding) where text?.characters.count > 0 {
            do {
                let json = try NSJSONSerialization.JSONObjectWithData(data, options: .MutableContainers) as? [String:AnyObject]
                return json
            } catch {
                print("Something went wrong")
            }
        }
        return nil
    }

    func evaluateJavaScript(javaScriptString: String, completionHandler: ((AnyObject?, NSError?) -> Void)?) {
        let wrapped = "var result = \(javaScriptString); JSON.stringify(result)"
        let string = stringByEvaluatingJavaScriptFromString(wrapped)
        let dict = convertStringToDictionary(string)
        completionHandler?(dict, NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotOpenFile, userInfo: nil))
    }

    func goToBackForwardListItem(item: LegacyBackForwardListItem) {
        if let index = backForwardList.backList.indexOf(item) {
            let backCount = backForwardList.backList.count - index
            for _ in 0..<backCount {
                goBack()
            }
        } else if let index = backForwardList.forwardList.indexOf(item) {
            for _ in 0..<(index + 1) {
                goForward()
            }
        }
    }

    override func goBack() {
        // stop scrolling so the web view will respond faster
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
        NSNotificationCenter.defaultCenter().postNotificationName(kNotificationPageUnload, object: self)
        super.goBack()
    }

    override func goForward() {
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
        NSNotificationCenter.defaultCenter().postNotificationName(kNotificationPageUnload, object: self)
        super.goForward()
    }

    class func isTopFrameRequest(request:NSURLRequest) -> Bool {
        return request.URL == request.mainDocumentURL
    }

    // Long press context menu text selection overriding
    override func canPerformAction(action: Selector, withSender sender: AnyObject?) -> Bool {
        return super.canPerformAction(action, withSender: sender)
    }

    func injectCSS(css: String) {
        var js = "var script = document.createElement('style');"
        js += "script.type = 'text/css';"
        js += "script.innerHTML = '\(css)';"
        js += "document.head.appendChild(script);"
        LegacyUserContentController.injectJsIntoAllFrames(self, script: js)
    }
}

extension BraveWebView: UIWebViewDelegate {

    class LegacyNavigationAction : WKNavigationAction {
        var writableRequest: NSURLRequest
        var writableType: WKNavigationType

        init(type: WKNavigationType, request: NSURLRequest) {
            writableType = type
            writableRequest = request
            super.init()
        }

        override var request: NSURLRequest { get { return writableRequest} }
        override var navigationType: WKNavigationType { get { return writableType } }
        override var sourceFrame: WKFrameInfo {
            get { return WKFrameInfo() }
        }
    }


    func webView(webView: UIWebView,shouldStartLoadWithRequest request: NSURLRequest, navigationType: UIWebViewNavigationType ) -> Bool {
        if BraveWebView.webviewBuiltinUserAgent == nil {
            BraveWebView.webviewBuiltinUserAgent = request.valueForHTTPHeaderField("User-Agent")
            assert(BraveWebView.webviewBuiltinUserAgent != nil)
        }

        #if DEBUG
            if var printedUrl = request.URL?.absoluteString {
                let maxLen = 100
                if printedUrl.characters.count > maxLen {
                    printedUrl =  printedUrl.substringToIndex(printedUrl.startIndex.advancedBy(maxLen)) + "..."
                }
               // print("webview load: " + printedUrl)
            }
        #endif

        if AboutUtils.isAboutHomeURL(request.URL) {
            URL = request.URL
            progress?.completeProgress()
            return true
        }

        if let url = request.URL where url.absoluteString.contains(specialStopLoadUrl) {
            progress?.completeProgress()
            return false
        }

        if let contextMenu = window?.rootViewController?.presentedViewController
            where contextMenu.view.tag == BraveWebView.kContextMenuBlockNavigation {
                // When showing a context menu, the webview will often still navigate (ex. news.google.com)
                // We need to block navigation using this tag.
                return false
        }

        if loadingUnvalidatedHTTPSPage {
            certificateInvalidConnection = NSURLConnection(request: request, delegate: self)
            certificateInvalidConnection?.start()
            return false
        }

        if let progressCheck = progress?.shouldStartLoadWithRequest(request, navigationType: navigationType) where !progressCheck {
            return false
        }

        var result = true
        if let nd = navigationDelegate {
            let action:LegacyNavigationAction =
            LegacyNavigationAction(type: convertNavActionToWKType(navigationType), request: request)

            nd.webView?(nullWebView, decidePolicyForNavigationAction: action,
                decisionHandler: { (policy:WKNavigationActionPolicy) -> Void in
                    result = policy == .Allow
            })
        }

        let locationChanged = BraveWebView.isTopFrameRequest(request) && request.URL?.absoluteString != URL?.absoluteString
        if locationChanged {
            // TODO Maybe separate page unload from link clicked.
            NSNotificationCenter.defaultCenter().postNotificationName(kNotificationPageUnload, object: self)
            URL = request.URL
            #if DEBUG
            print("Page changed by shouldStartLoad: \(URL?.absoluteString)")
            #endif
        }

        kvoBroadcast()

        return result
    }


    func webViewDidStartLoad(webView: UIWebView) {
        backForwardList.update()

        if let nd = navigationDelegate {
            // this triggers the network activity spinner
            nd.webView?(nullWebView, didStartProvisionalNavigation: nullWKNavigation)
        }
        progress?.webViewDidStartLoad()
        kvoBroadcast([KVOStrings.kvoLoading])

        #if !TEST
            HideEmptyImages.runJsInWebView(self)
        #endif
    }

    func webViewDidFinishLoad(webView: UIWebView) {
        assert(NSThread.isMainThread())
        backForwardList.update()

        let readyState = stringByEvaluatingJavaScriptFromString("document.readyState")?.lowercaseString

        //print("readyState:\(readyState)")

        title = webView.stringByEvaluatingJavaScriptFromString("document.title") ?? ""
        progress?.webViewDidFinishLoad(documentReadyState: readyState)

        kvoBroadcast()
    }

    func webView(webView: UIWebView, didFailLoadWithError error: NSError?) {
        if (error?.code == NSURLErrorCancelled) {
            return
        }

        if (error?.domain == NSURLErrorDomain) {
            if (error?.code == NSURLErrorServerCertificateHasBadDate      ||
                error?.code == NSURLErrorServerCertificateUntrusted         ||
                error?.code == NSURLErrorServerCertificateHasUnknownRoot    ||
                error?.code == NSURLErrorServerCertificateNotYetValid)
            {
                let errorUrl = error?.userInfo["NSErrorFailingURLKey"] as? String ?? ""
                if errorUrl.characters.count < 1 {
                    BraveApp.showErrorAlert(title: "Certificate Error", error: "Unable to load site due to invalid certificate")
                    return
                }

                let alert = UIAlertController(title: "Certificate Error", message: "The identity of \(errorUrl) can't be verified", preferredStyle: UIAlertControllerStyle.Alert)
                alert.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.Default) {
                    handler in
                    self.stopLoading()
                    // The current displayed url is wrong, so easiest hack is:
                    if (self.canGoBack) { // I don't think the !canGoBack case needs handling
                        self.goBack()
                        self.goForward()
                    }
                })
                alert.addAction(UIAlertAction(title: "Continue", style: UIAlertActionStyle.Default) {
                    handler in
                    self.loadingUnvalidatedHTTPSPage = true;
                    if let url = NSURL(string: errorUrl) {
                        self.loadRequest(NSURLRequest(URL: url))
                    }
                })

                #if !TEST
                    window?.rootViewController?.presentViewController(alert, animated: true, completion: nil)
                #endif
                return
            }
        }
        
        NSNotificationCenter.defaultCenter()
            .postNotificationName(BraveWebView.kNotificationWebViewLoadCompleteOrFailed, object: nil)
        if let nd = navigationDelegate {
            nd.webView?(nullWebView, didFailNavigation: nullWKNavigation,
                withError: error ?? NSError.init(domain: "", code: 0, userInfo: nil))
        }
        print("didFailLoadWithError: \(error)")
        progress?.didFailLoadWithError()
        kvoBroadcast()
    }
}

extension BraveWebView : NSURLConnectionDelegate, NSURLConnectionDataDelegate {
    func connection(connection: NSURLConnection, willSendRequestForAuthenticationChallenge challenge: NSURLAuthenticationChallenge) {
        guard let trust = challenge.protectionSpace.serverTrust else { return }
        let cred = NSURLCredential(forTrust: trust)
        challenge.sender?.useCredential(cred, forAuthenticationChallenge: challenge)
    }
    
    func connection(connection: NSURLConnection, didReceiveResponse response: NSURLResponse) {
        guard let url = URL else { return }
        loadingUnvalidatedHTTPSPage = false
        loadRequest(NSURLRequest(URL: url))
        certificateInvalidConnection?.cancel()
    }    
}
