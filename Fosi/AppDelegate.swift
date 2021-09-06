//
//  AppDelegate.swift
//  
//
//  Created by Chinmay Kulkarni on 12/18/20.
//

import UIKit
import GRDB.Swift

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  private var queuedUrl: URL?

  private lazy var browserViewController: BrowserViewController = {
    return BrowserViewController()
  }()

  private lazy var navigationController: UINavigationController = {
    return UINavigationController(rootViewController: browserViewController)
  }()

  func applicationDidBecomeActive(_ application: UIApplication) {
    if let queuedUrl = queuedUrl {
      browserViewController.navigate(to: queuedUrl)
    }
  }

  func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
      guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [AnyObject],
            let urlSchemes = urlTypes.first?["CFBundleURLSchemes"] as? [String],
            let scheme = components.scheme,
            let host = url.host,
            urlSchemes.contains(scheme)
      else { return false }

      let query = getQuery(url: url)

      if host == "open-url" {
        let urlString = unescape(string: query["url"]) ?? ""
        guard let url = URL(string: urlString) else { return false }

        if app.applicationState == .active {
          browserViewController.navigate(to: url)
        } else {
          queuedUrl = url
        }
      }
      return true
  }

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    try? AppDatabase.setup()

    DispatchQueue.main.async {
      _ = DomainCompletions.shared.getCompletions(keywords: "")
    }
    navigationController.hidesBarsOnTap = true
    navigationController.hidesBarsOnSwipe = true
    window = UIWindow(frame: UIScreen.main.bounds)
    window?.backgroundColor = .systemBackground
    window?.rootViewController = navigationController
    window?.makeKeyAndVisible()

    return true
  }
}

extension AppDelegate {
  private func getQuery(url: URL) -> [String: String] {
    var results = [String: String]()
    let keyValues =  url.query?.components(separatedBy: "&")

    if keyValues?.count ?? 0 > 0 {
      for pair in keyValues! {
        let kv = pair.components(separatedBy: "=")
        if kv.count > 1 {
          results[kv[0]] = kv[1]
        }
      }
    }

    return results
  }

  private func unescape(string: String?) -> String? {
    guard let string = string else { return nil }
    return CFURLCreateStringByReplacingPercentEscapes(
      kCFAllocatorDefault,
      string as CFString,
      "" as CFString
    ) as String
  }
}

// should be kept in sync with settings.bundle/root.plist
class AppSettingKeys {
  static let searchEngine = "SearchEngine"
  static let querySuggestions = "QuerySuggestions"
  static let contentBlocking = "ContentBlocking"
  static let nativePDFView = "NativePDFControl"
  static let popInBackground = "PopInBackground"

  static let btnExportHistory = "Export History"
  static let btnDeleteHistory = "Delete History"

  static let btnCurrentWebSite = "Current Website"
  static let btnEverything = "Everything"
  static let btnPrivacyPolicy = "View Privacy Policy"

  static let privacyPolicyURL = "https://github.com/chinmaymk/fosi/blob/master/PrivacyPolicy.md"
}
