//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by Chinmay Kulkarni on 9/5/21.
//

import UIKit
import Social
import MobileCoreServices
import CoreServices

class ShareViewController: SLComposeServiceViewController {
  override func isContentValid() -> Bool {
    // Do validation of contentText and/or NSExtensionContext attachments here
    return true
  }

  override func didSelectPost() {
    // This is called after the user selects Post. Do the upload of contentText and/or NSExtensionContext attachments.

    // Inform the host that we're done, so it un-blocks its UI. Note: Alternatively you could call super's -didSelectPost, which will similarly complete the extension context.
    self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
  }

  override func configurationItems() -> [Any]! {
    // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
    let inputItems: [NSExtensionItem] = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
    var urlProvider: NSItemProvider?

    // Look for the first URL the host application is sharing.
    // If there isn't a URL grab the first text item
    for item: NSExtensionItem in inputItems {
      let attachments: [NSItemProvider] = (item.attachments) ?? []
      for attachment in attachments {
        if urlProvider == nil && attachment.isUrl {
          urlProvider = attachment
        }
      }
    }

    // If a URL is found, process it. Otherwise we will try to convert
    // the text item to a URL falling back to sending just the text.
    if let urlProvider = urlProvider {
      urlProvider.processUrl { (urlItem, error) in
        guard
          let focusUrl = (urlItem as? NSURL)?.encodedUrl.flatMap(self.fosiUrl)
        else { self.cancel(); return }
        self.handleUrl(focusUrl)
      }
    } else {
      // If no item was processed. Cancel the share action to prevent the
      // extension from locking the host application due to the hidden
      // ViewController
      self.cancel()
    }

    return []
  }

  func fosiUrl(url: String) -> NSURL? {
    return NSURL(string: "fosi://open-url?url=\(url)")
  }

  private func handleUrl(_ url: NSURL) {
    // http://stackoverflow.com/questions/24297273/openurl-not-work-in-action-extension
    var responder = self as UIResponder?
    let selectorOpenURL = sel_registerName("openURL:")
    while responder != nil {
      if responder!.responds(to: selectorOpenURL) {
        responder!.callSelector(selector: selectorOpenURL, object: url, delay: 0)
      }
      responder = responder!.next
    }

    DispatchQueue.main.asyncAfter(
      deadline: DispatchTime(uptimeNanoseconds: UInt64(0.1 * Double(NSEC_PER_SEC)))
    ) {
      self.cancel()
    }
  }
}

extension NSObject {
  func callSelector(selector: Selector, object: AnyObject?, delay: TimeInterval) {
    let delay = delay * Double(NSEC_PER_SEC)
    let time = DispatchTime(uptimeNanoseconds: UInt64(delay))
    DispatchQueue.main.asyncAfter(deadline: time) {
      Thread.detachNewThreadSelector(selector, toTarget: self, with: object)
    }
  }
}

extension NSURL {
  var encodedUrl: String? {
    return absoluteString?.addingPercentEncoding(
      withAllowedCharacters: NSCharacterSet.alphanumerics
    )
  }
}

extension NSItemProvider {
  var isUrl: Bool { return hasItemConformingToTypeIdentifier(String(kUTTypeURL)) }

  func processUrl(completion: CompletionHandler?) {
    loadItem(forTypeIdentifier: String(kUTTypeURL), options: nil, completionHandler: completion)
  }
}
