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

