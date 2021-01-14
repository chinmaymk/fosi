//
//  HyperFocusApp.swift
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

  func setupDatabase() throws {
    let databaseURL = try FileManager.default
      .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent("hyperfocus.sqlite")
    let dbQueue = try DatabaseQueue(path: databaseURL.path)

    let database = try AppDatabase(dbQueue)
    AppDatabase.shared = database
  }

  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

    DispatchQueue.main.async {
      try! self.setupDatabase()
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

