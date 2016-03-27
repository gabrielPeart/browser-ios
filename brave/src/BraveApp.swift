/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
#if !NO_FABRIC
import Fabric
import Crashlytics
#endif

#if !DEBUG
func print(items: Any..., separator: String = " ", terminator: String = "\n") {}
#endif

private let _singleton = BraveApp()

let kAppBootingIncompleteFlag = "kAppBootingIncompleteFlag"
let kDesktopUserAgent = "Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_5_8; it-it) AppleWebKit/533.16 (KHTML, like Gecko) Version/5.0 Safari/533.16"

#if !TEST
    func getApp() -> AppDelegate {
        return UIApplication.sharedApplication().delegate as! AppDelegate
    }
#endif

// Any app-level hooks we need from Firefox, just add a call to here
class BraveApp {
    static var isSafeToRestoreTabs = true
    // If app runs for this long, clear the saved pref that indicates it is safe to restore tabs
    static let kDelayBeforeDecidingAppHasBootedOk = (Int64(NSEC_PER_SEC) * 10) // 10 sec

    static var isBraveButtonBypassingFilters = false

    class var singleton: BraveApp {
        return _singleton
    }

    class func isAllBraveShieldPrefsOff() -> Bool {
        let abOn = BraveApp.getPref(AdBlocker.prefKeyAdBlockOn) as? Bool ?? true
        let tpOn = BraveApp.getPref(TrackingProtection.prefKeyTrackingProtectionOn) as? Bool ?? true
        let httpseOn = BraveApp.getPref(HttpsEverywhere.prefKeyHttpsEverywhereOn) as? Bool ?? true
        return !abOn && !tpOn && !httpseOn
    }

#if !TEST
    class func getCurrentWebView() -> BraveWebView? {
        return getApp().browserViewController.tabManager.selectedTab?.webView
    }
#endif

    private init() {
    }

    class func isIPhoneLandscape() -> Bool {
        return UIDevice.currentDevice().userInterfaceIdiom == .Phone &&
            UIInterfaceOrientationIsLandscape(UIApplication.sharedApplication().statusBarOrientation)
    }

    class func isIPhonePortrait() -> Bool {
        return UIDevice.currentDevice().userInterfaceIdiom == .Phone &&
            UIInterfaceOrientationIsPortrait(UIApplication.sharedApplication().statusBarOrientation)
    }

    class func setupCacheDefaults() {
        NSURLCache.sharedURLCache().memoryCapacity = 6 * 1024 * 1024; // 6 MB
        NSURLCache.sharedURLCache().diskCapacity = 40 * 1024 * 1024;
    }

    // Be aware: the Prefs object has not been created yet
    class func willFinishLaunching_begin() {
#if !NO_FABRIC
        Fabric.with([Crashlytics.self])
#endif
        BraveApp.setupCacheDefaults()
        NSURLProtocol.registerClass(URLProtocol);

        NSNotificationCenter.defaultCenter().addObserver(BraveApp.singleton,
            selector: "didEnterBackground:", name: UIApplicationDidEnterBackgroundNotification, object: nil)

        NSNotificationCenter.defaultCenter().addObserver(BraveApp.singleton,
            selector: "willEnterForeground:", name: UIApplicationWillEnterForegroundNotification, object: nil)

        NSNotificationCenter.defaultCenter().addObserver(BraveApp.singleton,
            selector: "memoryWarning:", name: UIApplicationDidReceiveMemoryWarningNotification, object: nil)

        #if !TEST
        //  these quiet the logging from the core of fx ios
       // GCDWebServer.setLogLevel(5)
        Logger.syncLogger.setup(.None)
        Logger.browserLogger.setup(.None)
        #endif

        #if DEBUG
            #if !TEST
                if BraveUX.DebugShowBorders {
                    UIView.bordersOn()
                }
            #endif
            // desktop UA for testing
            //      let defaults = NSUserDefaults(suiteName: AppInfo.sharedContainerIdentifier())!
            //      defaults.registerDefaults(["UserAgent": kDesktopUserAgent])

        #endif
    }

    // Prefs are created at this point
    class func willFinishLaunching_end() {
        if AppConstants.IsRunningTest {
            print("In test mode, bypass automatic vault registration.")
        } else {
            // TODO hookup VaultManager.userProfileInit()
        }

        BraveApp.isSafeToRestoreTabs = BraveApp.getPref(kAppBootingIncompleteFlag) == nil
        BraveApp.setPref("remove me when booted", forKey: kAppBootingIncompleteFlag)
        BraveApp.getPrefs()?.synchronize()
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, BraveApp.kDelayBeforeDecidingAppHasBootedOk),
            dispatch_get_main_queue(), {
                BraveApp.removePref(kAppBootingIncompleteFlag)
        })

        AdBlocker.singleton.networkFileLoader.loadData()
        TrackingProtection.singleton.networkFileLoader.loadData()
        HttpsEverywhere.singleton.networkFileLoader.loadData()

        #if !TEST
            BraveScrollController.hideShowToolbarEnabled = BraveApp.getPref(BraveUX.PrefKeyIsToolbarHidingEnabled) as? Bool ?? true
            PrivateBrowsing.singleton.startupCheckIfKilledWhileInPBMode()
            CookieSetting.setup()
        #endif
    }

    // This can only be checked ONCE, the flag is cleared after this.
    // This is because BrowserViewController asks this question after the startup phase,
    // when tabs are being created by user actions. So without more refactoring of the
    // Firefox logic, this is the simplest solution.
    class func shouldRestoreTabs() -> Bool {
        let ok = BraveApp.isSafeToRestoreTabs
        BraveApp.isSafeToRestoreTabs = true
        return ok
    }

    @objc func memoryWarning(_: NSNotification) {
        NSURLCache.sharedURLCache().memoryCapacity = 0
        BraveApp.setupCacheDefaults()
        getApp().tabManager.memoryWarning()
    }

    @objc func didEnterBackground(_: NSNotification) {
    }

    @objc func willEnterForeground(_ : NSNotification) {
    }

    class func shouldHandleOpenURL(components: NSURLComponents) -> Bool {
        // TODO look at what x-callback is for
        return components.scheme == "brave" || components.scheme == "brave-x-callback"
    }

    class func getPrefs() -> NSUserDefaults? {
        #if !TEST
            // The prefs are namespaced with 'profile.', find a better way to expose this from fx
            assert(NSUserDefaultsPrefs.prefixWithDotForBrave.characters.count > 0)
        #endif
        return NSUserDefaults(suiteName: AppInfo.sharedContainerIdentifier())
    }

    class func getPref(var pref: String) -> AnyObject? {
        #if !TEST
            pref = NSUserDefaultsPrefs.prefixWithDotForBrave + pref
        #endif

        return getPrefs()?.objectForKey(pref)
    }

    class func setPref(val: AnyObject, var forKey: String) {
        #if !TEST
            forKey = NSUserDefaultsPrefs.prefixWithDotForBrave + forKey
        #endif
        getPrefs()?.setObject(val, forKey: forKey)
    }

    class func removePref(var pref: String) {
        #if !TEST
            pref = NSUserDefaultsPrefs.prefixWithDotForBrave + pref
        #endif
        getPrefs()?.removeObjectForKey(pref)
    }

    static func showErrorAlert(title title: String,  error: String) {
        ensureMainThread() {
            UIAlertView(title: title, message: error, delegate: nil, cancelButtonTitle: "Close").show()
        }
    }

    static func statusBarHeight() -> CGFloat {
        if UIScreen.mainScreen().traitCollection.verticalSizeClass == .Compact {
            return 0
        }
        return 20
    }
}
