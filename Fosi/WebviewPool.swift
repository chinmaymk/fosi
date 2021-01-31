//
//  WebviewPool.swift
//  Fosi
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
    private var timer: Timer?

    init(view: WKWebView) {
      self.view = view
      createdAt = Date()
      updateSnapshot()
      progressObservable = view.observe(\WKWebView.estimatedProgress, options: .new) { [self] (_, change) in
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false, block: { _ in
          self.updateSnapshot()
        })
        timer?.fire()
      }
    }

    fileprivate func updateSnapshot() {
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
    var sw = field
    if count > 7 {
      sw = .lastAccessed
    }

    switch sw {
    case .lastAccessed:
      var list = itemsMap.sorted { $0.value.lastAccesed > $1.value.lastAccesed }
      let first = list.removeFirst()
      list.append(first)
      return list
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

  @discardableResult 
  func add(view: WKWebView) -> Index {
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

  func updateSnapshot(view: WKWebView) {
    itemsMap[view.hashValue]?.lastAccesed = Date()
    itemsMap[view.hashValue]?.updateSnapshot()
  }

  func getItem(at index: Index) -> Item? {
    return itemsMap[index]
  }

  func getIndex(view: WKWebView) -> Index? {
    // TODO
    return add(view: view)
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
  case desktop
}

class WebviewFactory {

  static let blockLists = [
    // "blocking-content-rules.json",
    // "blocking-content-rules-social.json",
    // "blocking-content-rules-privacy.json",
    "easylist.json",
    "filters.json",
    "idc.json"
  ]

  let pool: WebviewPool

  init(pool: WebviewPool) {
    self.pool = pool
  }

  static let shared = WebviewFactory(pool: WebviewPool(size: Int.max))

  static let processPool = WKProcessPool()

  func addScript(to webView: WKWebView, file: String, injectionTime: WKUserScriptInjectionTime) {
    let url = Bundle.main.url(forResource: file, withExtension: "")
    let source = try! String(contentsOf: url!)
    let script = WKUserScript(source: source, injectionTime: injectionTime, forMainFrameOnly: false)
    webView.configuration.userContentController.addUserScript(script)
  }

  func addBlockList(to webView: WKWebView, file: String) {
    let url = Bundle.main.url(forResource: file, withExtension: "")
    let jsonString = try! String(contentsOf: url!)
    WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "nomad.Fosi", encodedContentRuleList: jsonString) {  (contentRuleList: WKContentRuleList?, error: Error?) in
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
      addScript(to: webView, file: "DarkReader.js", injectionTime: .atDocumentStart)
    }
    addScript(to: webView, file: "TinyColor.js", injectionTime: .atDocumentStart)
    addScript(to: webView, file: "mark.js", injectionTime: .atDocumentStart)
    addScript(to: webView, file: "index.js", injectionTime: .atDocumentStart)

    //    for list in WebviewFactory.blockLists {
    //      addBlockList(to: webView, file: list)
    //    }
    let lists = BlockListManager.shared.lists
    lists.forEach { (list) in
      let jsonString = list.contents()
      WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "nomad.Fosi", encodedContentRuleList: jsonString) { (contentRuleList: WKContentRuleList?, error: Error?) in
        guard let wklist = contentRuleList, error == nil else {
          print(error, list.name)
          return
        }
        webView.configuration.userContentController.add(wklist)
      }
    }
  }

  func build(mode: WebviewMode, style: UIUserInterfaceStyle) -> WKWebView {
    let preferences = WKPreferences()
    preferences.isFraudulentWebsiteWarningEnabled = true
    let config = WKWebViewConfiguration()

    if mode == .incognito {
      config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
    }

    if mode == .desktop {
      config.defaultWebpagePreferences.preferredContentMode = .desktop
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
    webView.isOpaque = true
    webView.backgroundColor = .systemBackground

    webView.scrollView.decelerationRate = .normal
    webView.scrollView.bounces = true
    webView.scrollView.delaysContentTouches = false
    webView.scrollView.contentInsetAdjustmentBehavior = .scrollableAxes

    addStaticAssets(to: webView, for: style)
    pool.add(view: webView)
    return webView
  }
}
