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

  private lazy var navigationController: UINavigationController = {
    let browserViewController = BrowserViewController()
    return UINavigationController(rootViewController: browserViewController)
  }()

  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

    try? AppDatabase.setup(app: application)

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

// should be kept in sync with settings.bundle/root.plist
class AppSettingKeys {
  static let searchEngine = "SearchEngine"
  static let querySuggestions = "QuerySuggestions"
  static let contentBlocking = "ContentBlocking"
  static let nativePDFView = "NativePDFControl"
  static let popInBackground = "PopInBackground"

  static let btnExportHistory = "Export History"
  static let btnDeleteHistory = "Delete History"

  static let btnCurrentWebSite = "Current website"
  static let btnEverything = "All"
  static let btnPrivacyPolicy = "View Privacy Policy"

  static let privacyPolicyURL = "https://github.com/chinmaymk/fosi/blob/master/PrivacyPolicy.md"
}
