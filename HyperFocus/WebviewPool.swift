//
//  WebviewPool.swift
//  HyperFocus
//
//  Created by Chinmay Kulkarni on 1/1/21.
//

import Foundation
import WebKit

class WebviewPool {

  class Item {
    // Caution: this should be accessed from main thread
    private(set) var view: WKWebView
    fileprivate(set) var lastAccesed = Date()
    private(set) var snapshot: UIImage = UIImage()
    private var progressObservable: NSKeyValueObservation?
    private(set) var createdAt: Date

    init(view: WKWebView) {
      self.view = view
      createdAt = Date()
      updateSnapshot()
      progressObservable = view.observe(\WKWebView.estimatedProgress, options: .new) { _, change in
        let val = Float(change.newValue!)
        if val == 1 || val == 0 {
          self.updateSnapshot()
        }
        if let oldVal = change.oldValue, change.newValue! - oldVal > 0.3 {
          self.updateSnapshot()
        }
      }
    }

    private func updateSnapshot() {
      DispatchQueue.main.async {
        self.view.takeSnapshot(with: .none) { (image, err) in
          guard let image = image, err == nil else { return }
          self.snapshot = image
        }
      }
    }

    func stopObserving() {
      progressObservable?.invalidate()
    }
  }

  typealias Index = Int

  private var size = 20
  
  enum OrderBy {
    case lastAccessed
    case createdAt
  }
  enum SortOrder {
    case asc
    case desc
  }
  func sorted(by field: OrderBy, order: SortOrder = .desc) -> Array<(Index, Item)> {
    switch field {
    case .lastAccessed:
      return itemsMap.sorted { $0.value.lastAccesed > $1.value.lastAccesed }
    case .createdAt:
      return itemsMap.sorted { $0.value.createdAt > $1.value.createdAt }
    }
  }

  private var itemsMap = [Index: Item]()

  var count: Int  {
    get { return itemsMap.count }
  }

  init(size: Int) {
    self.size = size
  }

  func add(view: WKWebView) -> Index? {
    guard size > itemsMap.count else { return nil }

    if let item = itemsMap[view.hashValue] {
      item.lastAccesed = Date()
      print("tried to add view again", view.hashValue)
      return view.hashValue
    }
    
    itemsMap[view.hashValue] = Item(view: view)
    print("added view", view.hashValue)
    return  view.hashValue
  }

  func get(at index: Index) -> WKWebView? {
    return getItem(at: index)?.view
  }

  func getItem(at index: Index) -> Item? {
    return itemsMap[index]
  }

  func remove(at index: Index) {
    print("deleting view at \(index)")
    if let item = itemsMap.removeValue(forKey: index) {
      item.stopObserving()
      print("deleted view", item.view.hashValue)
    }
  }

  func removeAll() {
    itemsMap.values.forEach { $0.stopObserving() }
    itemsMap.removeAll()
  }
}

enum WebviewMode {
  case normal
  case incognito
  case noamp
}

class WebviewFactory {

  static let blockLists = [
    //        "blocking-content-rules.json",
    //        "blocking-content-rules-social.json",
    //        "blocking-content-rules-privacy.json",
    "easylist.json",
    "filters.json",
    "idc.json"
  ]

  static let shared = WebviewFactory()

  static let processPool = WKProcessPool()

  func addScript(webView: WKWebView, file: String, injectionTime: WKUserScriptInjectionTime) {
    let url = Bundle.main.url(forResource: file, withExtension: "")
    let source = try! String(contentsOf: url!)
    let script = WKUserScript(source: source, injectionTime: injectionTime, forMainFrameOnly: false)
    webView.configuration.userContentController.addUserScript(script)
  }

  func addBlockList(webView: WKWebView, file: String) {
    let url = Bundle.main.url(forResource: file, withExtension: "")
    let jsonString = try! String(contentsOf: url!)
    WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "nomad.HyperFocus", encodedContentRuleList: jsonString) {  (contentRuleList: WKContentRuleList?, error: Error?) in
      if error != nil {
        return
      }
      if let list = contentRuleList {
        webView.configuration.userContentController.add(list)
      }
    }
  }

  func addStaticAssets(to webView: WKWebView, for style: UIUserInterfaceStyle) {
    if style == .dark {
      addScript(webView: webView, file: "DarkReader.js", injectionTime: .atDocumentStart)
    }
    addScript(webView: webView, file: "TinyColor.js", injectionTime: .atDocumentStart)
    addScript(webView: webView, file: "mark.js", injectionTime: .atDocumentStart)
    addScript(webView: webView, file: "index.js", injectionTime: .atDocumentStart)

    for list in WebviewFactory.blockLists {
      addBlockList(webView: webView, file: list)
    }
  }

  func build(mode: WebviewMode, style: UIUserInterfaceStyle) -> WKWebView {
    let preferences = WKPreferences()
    preferences.isFraudulentWebsiteWarningEnabled = true
    let config = WKWebViewConfiguration()

    if mode == .incognito {
      config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
    }

    config.preferences = preferences
    config.allowsAirPlayForMediaPlayback = true
    config.allowsInlineMediaPlayback = true
    config.allowsPictureInPictureMediaPlayback = false
    config.selectionGranularity = .dynamic
    config.ignoresViewportScaleLimits = true
    config.processPool = WebviewFactory.processPool

    let webView = WKWebView(frame: .zero, configuration: config)

    if mode == .noamp {
      webView.customUserAgent = "Mozilla/5.0 (Android 9; Mobile; rv:65.0) Gecko/65.0 Firefox/65.0"
    }

    webView.allowsBackForwardNavigationGestures = true
    webView.allowsLinkPreview = true
    webView.translatesAutoresizingMaskIntoConstraints = false
    webView.isOpaque = false
    webView.backgroundColor = .clear

    webView.scrollView.decelerationRate = .normal
    webView.scrollView.bounces = true
    webView.scrollView.delaysContentTouches = false

    addStaticAssets(to: webView, for: style)

    return webView
  }
}
