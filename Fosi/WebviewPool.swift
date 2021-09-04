//
//  WebviewPool.swift
//  Fosi
//
//  Created by Chinmay Kulkarni on 1/1/21.
//

import Foundation
import WebKit

enum WebviewMode {
  case normal
  case incognito
  case noamp
  case desktop
}

class WebviewPool {
  typealias Index = Int
  private var itemsMap = [Index: Item]()
  var count: Int  {
    get { return itemsMap.count }
  }
  private var size = 20

  init(size: Int) {
    self.size = size
  }

  @discardableResult
  func add(view: WKWebView) -> Index {
    if let item = itemsMap[view.hashValue] {
      item.lastAccesed = Date()
      NSLog("tried to add view again", view.hashValue)
      return view.hashValue
    }
    
    itemsMap[view.hashValue] = Item(view: view)
    NSLog("added view", view.hashValue)
    return view.hashValue
  }

  func get(at index: Index) -> WKWebView? {
    return getItem(at: index)?.view
  }

  func getItem(at index: Index) -> Item? {
    return itemsMap[index]
  }

  func getIndex(view: WKWebView) -> Index? {
    return add(view: view)
  }

  enum OrderBy {
    case lastAccessed
    case createdAt
  }
  enum SortOrder {
    case asc
    case desc
  }
  func sorted(by field: OrderBy, order: SortOrder = .desc) -> Array<(Index, Item)> {
    var orderBy: OrderBy {
      if count > 7 {
        return .lastAccessed
      } else {
        return field
      }
    }
    switch orderBy {
    case .lastAccessed:
      var list = itemsMap.sorted { $0.value.lastAccesed > $1.value.lastAccesed }
      let first = list.removeFirst()
      list.append(first)
      return list
    case .createdAt:
      return itemsMap.sorted { $0.value.createdAt > $1.value.createdAt }
    }
  }

  func remove(at index: Index) {
    NSLog("deleting view at", index)
    if let item = itemsMap.removeValue(forKey: index) {
      item.stopObserving()
      NSLog("deleted view", item.view.hashValue)
    }
  }

  func removeAll() {
    itemsMap.values.forEach { $0.stopObserving() }
    itemsMap.removeAll()
  }

  func updateSnapshot(view: WKWebView) {
    itemsMap[view.hashValue]?.lastAccesed = Date()
    itemsMap[view.hashValue]?.updateSnapshot()
  }

  class Item {
    // Caution: this should be accessed from main thread
    private(set) var view: WKWebView
    private(set) var snapshot: UIImage = UIImage()
    private(set) var createdAt: Date
    fileprivate(set) var lastAccesed = Date()
    private var progressObservable: NSKeyValueObservation?
    private var timer: Timer?

    init(view: WKWebView) {
      self.view = view
      createdAt = Date()
      updateSnapshot()
      progressObservable = view.observe(
        \WKWebView.estimatedProgress, options: .new
      ) { [self] (_, change) in
        timer?.invalidate()
        timer = Timer.scheduledTimer(
          withTimeInterval: 0.1, repeats: false,
          block: { _ in
          self.updateSnapshot()
        })
        timer?.fire()
      }
    }

    fileprivate func updateSnapshot() {
      DispatchQueue.main.async {
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = true
        self.view.takeSnapshot(with: config) { (image, err) in
          guard let image = image, err == nil else { return }
          self.snapshot = image
        }
      }
    }

    func stopObserving() {
      progressObservable?.invalidate()
    }

    deinit {
      stopObserving()
    }
  }
}

extension UserDefaults {
  @objc dynamic var contentBlocking: Bool {
    get { return bool(forKey: AppSettingKeys.contentBlocking) }
  }
}

class WebViewItem {
  let view: WKWebView
  let mode: WebviewMode

  init(view: WKWebView, mode: WebviewMode) {
    self.view = view
    self.mode = mode
  }
}

class WebviewFactory {
  static let packagedLists = [
    "cosmetic.json",
    "network.json",
  ]
  static let shared = WebviewFactory(pool: WebviewPool(size: Int.max))
  static let processPool = WKProcessPool()

  let pool: WebviewPool
  var blocklists: [WKContentRuleList] = []
  var blockListAdded: ((WKContentRuleList) -> Void)?

  init(pool: WebviewPool) {
    self.pool = pool
    refreshBlocklists()
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
    webView.contentMode = .scaleAspectFit

    webView.scrollView.decelerationRate = .normal
    webView.scrollView.bounces = true
    webView.scrollView.delaysContentTouches = false
    webView.scrollView.contentInsetAdjustmentBehavior = .scrollableAxes

    addStaticAssets(to: webView, for: style)
    pool.add(view: webView)
    return webView
  }

  func addStaticAssets(to webView: WKWebView, for style: UIUserInterfaceStyle) {
    if style == .dark {
      addScript(to: webView, file: "DarkReader.js", injectionTime: .atDocumentStart)
    }
    addScript(to: webView, file: "TinyColor.js", injectionTime: .atDocumentStart)
    addScript(to: webView, file: "mark.js", injectionTime: .atDocumentStart)
    addScript(to: webView, file: "index.js", injectionTime: .atDocumentStart)

    if UserDefaults.standard.contentBlocking {
      addBlockList(to: webView)
    }
  }

  func addScript(
    to webView: WKWebView,
    file: String,
    injectionTime: WKUserScriptInjectionTime
  ) {
    let url = Bundle.main.url(forResource: file, withExtension: "")
    let source = try! String(contentsOf: url!)
    let script = WKUserScript(
      source: source, injectionTime: injectionTime, forMainFrameOnly: false
    )
    webView.configuration.userContentController.addUserScript(script)
  }

  func addBlockList(to webView: WKWebView) {
    blocklists.forEach(webView.configuration.userContentController.add)
  }

  func refreshBlocklists() {
    func compile(list: String, jsonString: String) {
      WKContentRuleListStore.default().compileContentRuleList(
        forIdentifier: "fosi.Fosi.\(list)",
        encodedContentRuleList: jsonString
      ) { (list, err) in
        guard let list = list, err == nil else { return }
        self.blocklists.append(list)
        if UserDefaults.standard.contentBlocking {
          self.blockListAdded?(list)
        }
      }
    }

    WebviewFactory.packagedLists.forEach { list in
      let url = Bundle.main.url(forResource: list, withExtension: "")
      let jsonString = try! String(contentsOf: url!)
      compile(list: list, jsonString: jsonString)
    }
  }
}
