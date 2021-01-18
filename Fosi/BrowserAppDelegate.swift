//
//  AppDelegate.swift
//  test
//
//  Created by Chinmay Kulkarni on 12/18/20.
//

import UIKit
import AMScrollingNavbar

@UIApplicationMain
class HyperFocusApp: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?

    private lazy var browserViewController = {
        WVVC()
    }()
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        window = UIWindow()
        let nav = ScrollingNavigationController(rootViewController: browserViewController)
        nav.isToolbarHidden = true
        nav.title = "google.com"
        window?.rootViewController = nav
        window?.makeKeyAndVisible()
        
        // Override point for customization after application launch.
        return true
    }
}

