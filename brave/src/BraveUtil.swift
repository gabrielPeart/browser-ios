/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

func delay(delay:Double, closure:()->()) {
    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            Int64(delay * Double(NSEC_PER_SEC))
        ),
        dispatch_get_main_queue(), closure)
}

func ensureMainThread(closure:()->()) {
    if NSThread.isMainThread() {
        closure()
    } else {
        dispatch_async(dispatch_get_main_queue(), closure)
    }
}


// Lookup time is O(maxDicts)
// Very basic implementation of a recent item collection class, stored as groups of items in dictionaries, oldest items are deleted as blocks of items since their entire containing dictionary is deleted.
class FifoDict {
    var fifoArrayOfDicts: [NSMutableDictionary] = []
    let maxDicts = 5
    let maxItemsPerDict = 50

    // the url key is a combination of urls, the main doc url, and the url being checked
    func addItem(key: String, value: AnyObject?) {
        if fifoArrayOfDicts.count > maxItemsPerDict {
            fifoArrayOfDicts.removeFirst()
        }

        if fifoArrayOfDicts.last == nil || fifoArrayOfDicts.last?.count > maxItemsPerDict {
            fifoArrayOfDicts.append(NSMutableDictionary())
        }

        if let lastDict = fifoArrayOfDicts.last {
            if value == nil {
                lastDict[key] = NSNull()
            } else {
                lastDict[key] = value
            }
        }
    }

    func getItem(key: String) -> AnyObject?? {
        for dict in fifoArrayOfDicts {
            if let item = dict[key] {
                return item
            }
        }
        return nil
    }
}

class InsetLabel: UILabel {
    var leftInset = CGFloat(0)
    var rightInset = CGFloat(0)
    override func drawTextInRect(rect: CGRect) {
        super.drawTextInRect(UIEdgeInsetsInsetRect(rect, UIEdgeInsets(top: 0, left: leftInset, bottom: 0, right: rightInset)))
    }
}


extension String {
    func regexReplacePattern(pattern:String,  with:String) -> String {
        let regex = try! NSRegularExpression(pattern:pattern, options: [])
        return regex.stringByReplacingMatchesInString(self, options: [], range: NSMakeRange(0, self.characters.count), withTemplate: with)
    }
}

extension NSURL {
    func hostWithGenericSubdomainPrefixRemoved() -> String? {
        return host != nil ? stripGenericSubdomainPrefixFromUrl(host!) : nil
    }
}

// Firefox has uses urls of the form  http://localhost:6571/errors/error.html?url=http%3A//news.google.ca/ to populate the browser history, and load+redirect using GCDWebServer
func stripLocalhostWebServer(url: String) -> String {
#if !TEST // TODO fix up the fact lots of code isn't available in the test suite, this is just an additional check, so for testing the rest of the code will work fine
    if !url.startsWith(WebServer.sharedInstance.base) {
        return url
    }
#endif
    // I think the ones prefixed with the following are the only ones of concern. There is also about/sessionrestore urls, not sure if we need to look at those
    let token = "errors/error.html?url="
    let range = url.rangeOfString(token)
    if let range = range {
        return url.substringFromIndex(range.endIndex)
    } else {
        return url
    }
}

func stripGenericSubdomainPrefixFromUrl(url: String) -> String {
    return url.regexReplacePattern("^(m\\.|www\\.|mobile\\.)", with:"");
}

func addSkipBackupAttributeToItemAtURL(url:NSURL) {
    let fileManager = NSFileManager.defaultManager()
    #if DEBUG
    assert(fileManager.fileExistsAtPath(url.path!))
    #endif

    do {
        try url.setResourceValue(true, forKey: NSURLIsExcludedFromBackupKey)
    } catch {
        print("Error excluding \(url.lastPathComponent) from backup \(error)")
    }
}

func printTimeElapsedWhenRunningCode(title:String, operation:()->()) {
    let startTime = CFAbsoluteTimeGetCurrent()
    operation()
    let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
    print("Time elapsed for \(title): \(timeElapsed) s")
}
