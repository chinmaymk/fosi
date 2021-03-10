//
//  BrowserViewController.swift
//  
//
//  Created by Chinmay Kulkarni on 12/18/20.
//

import UIKit
import WebKit
import Toast_Swift
import SafariServices
import Promises
import Vision
import InAppSettingsKit
import NaturalLanguage
import ISHHoverBar

class BrowserViewController: UIViewController,
                             UIScrollViewDelegate,
                             UINavigationControllerDelegate,
                             UIContextMenuInteractionDelegate {
  let factory = WebviewFactory.shared
  var currentMode: WebviewMode = .normal {
    didSet {
      respawnWebview()
    }
  }
  var currentSyle: UIUserInterfaceStyle {
    get { return traitCollection.userInterfaceStyle }
  }
  lazy var webView = factory.build(mode: .normal, style: currentSyle)

  // Search Related stuff
  let searchHolder = SearchHolderView()
  var searchBar: UISearchBar {
    get { return searchHolder.searchBar }
  }
  var tableView: UITableView {
    get { return searchHolder.tableView }
  }
  let barCounter = WheelCounter<SearchHolderView.SearchBarText>(labels: [.lastQuery, .title, .url])

  // find in page
  let findInPageToolbar = ISHHoverBar()

  // track progress
  let progressView = CircularProgressView()
  var progressObservable: NSKeyValueObservation?
  let incognitoIndicator: UIImage = UIImage(
    systemName: "bolt.circle"
  )!.withTintColor(
    UIColor(red: 0.85, green: 0.12, blue: 0.09, alpha: 1.00),
    renderingMode: .alwaysOriginal
  )

  // additional actions for text
  let contextualMenus = [
    UIMenuItem(title: "Search", action: #selector(searchFromSelection)),
    UIMenuItem(title: "Find In Page", action: #selector(findInPageFromSelection))
  ]
  lazy var modeIndicator = [
    WebviewMode.desktop: UIImageView(image: UIImage(systemName: "desktopcomputer")),
    WebviewMode.incognito: UIImageView(image: incognitoIndicator),
    WebviewMode.normal: progressView,
    WebviewMode.noamp: progressView,
  ]
  var commitURL: URL?
  var webViewFrame: CGRect = .zero
  var initFrame: CGRect = .zero
  let topMask = UIView()
}

// MARK: UIKit methods
extension BrowserViewController {
  override func viewDidLoad() {
    super.viewDidLoad()
    navigationController?.delegate = self
    setupDelegates()
    setupObservables()
    setupSearchExperience()
    setupBrowsingExperience()
    setupToolBar()
    // setup contextual menus for text
    UIMenuController.shared.menuItems = contextualMenus
    searchBar.becomeFirstResponder()

    factory.blockListAdded = { list in
      self.webView.configuration.userContentController.remove(list)
      self.webView.configuration.userContentController.add(list)
    }
  }

  override func viewDidLayoutSubviews() {
    switch UIDevice.current.orientation {
    case .landscapeLeft, .landscapeRight:
      topMask.isHidden = true
      webViewFrame = CGRect(origin: .zero, size: CGSize(width: initFrame.height, height: initFrame.width))
    default:
      topMask.isHidden = false
      webViewFrame = initFrame
    }
    webView.frame = webViewFrame
    tableView.frame = webViewFrame
  }

  override func viewWillAppear(_ animated: Bool) {
    webView.frame = webViewFrame
    tableView.frame = webViewFrame
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    guard UIApplication.shared.applicationState == .inactive else { return }

    let confirmAlert = UIAlertController(
      title: "System Appearance Changed",
      message: "Fosi detected a change in display settings, Would you like to reload?",
      preferredStyle: .actionSheet
    )
    confirmAlert.addAction(
      UIAlertAction(
        title: "Confirm", style: .default,
        handler: { [self] _ in
          let url = webView.url
          let newView = factory.build(mode: currentMode, style: currentSyle)
          if let url = url {
            newView.load(URLRequest(url: url))
          }
          replaceWebview(with: newView)
        }
      )
    )
    confirmAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
    present(confirmAlert, animated: true, completion: nil)
  }
}

// MARK: setup views correctly
extension BrowserViewController {
  func setupSearchExperience() {
    searchHolder.delegate = self
    searchBar.delegate = searchHolder
    searchBar.showsCancelButton = true
    searchBar.sizeToFit()
    navigationItem.titleView = searchBar
    tableView.isHidden = true
    tableView.dataSource = searchHolder
    tableView.delegate = searchHolder

    let selectTableItem = UITapGestureRecognizer(
      target: searchHolder,
      action: #selector(searchHolder.didTapTableView(gesture:))
    )
    selectTableItem.cancelsTouchesInView = false
    tableView.addGestureRecognizer(selectTableItem)

    let flickSearchBar = UIPanGestureRecognizer(
      target: self, action: #selector(slideSearchBar)
    )
    navigationController?.navigationBar.addGestureRecognizer(flickSearchBar)
  }

  func setupDelegates() {
    webView.navigationDelegate = self
    webView.uiDelegate = self
    webView.scrollView.delegate = self
  }

  func setupBrowsingExperience() {
    // primary webview
    view.addSubview(webView)
    edgesForExtendedLayout = [.bottom, .left, .right]
    initFrame = view.frame
    webViewFrame = view.frame
    webView.frame = view.frame
    navigationController?.navigationBar.isTranslucent = false

    // setup topmask
    topMask.backgroundColor = .systemBackground
    topMask.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(topMask)
    NSLayoutConstraint.activate([
      topMask.topAnchor.constraint(equalTo: view.topAnchor),
      topMask.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      topMask.widthAnchor.constraint(equalTo: view.widthAnchor),
    ])

    // setup tableview
    tableView.isScrollEnabled = true
    tableView.bounces = false
    tableView.frame = view.frame
    view.addSubview(tableView)

    // setup find in page toolbar
    findInPageToolbar.items = [
      UIBarButtonItem(
        image: UIImage(systemName: "arrow.up"),
        style: .plain, target: self,
        action: #selector(scrollUpToMatch)
      ),
      UIBarButtonItem(
        image: UIImage(systemName: "arrow.down"),
        style: .plain, target: self,
        action: #selector(scrollDownToMatch)
      ),
      UIBarButtonItem(
        image: UIImage(systemName: "xmark"),
        style: .plain, target: self,
        action: #selector(unmark)
      )
    ]
    findInPageToolbar.orientation = .vertical
    findInPageToolbar.isHidden = true
    findInPageToolbar.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(findInPageToolbar)
    NSLayoutConstraint.activate([
      findInPageToolbar.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -20),
      findInPageToolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -100),
    ])

    // setup progress bar and mode switching
    progressView.translatesAutoresizingMaskIntoConstraints = false
    progressView.addInteraction(UIContextMenuInteraction(delegate: self))
    navigationItem.leftBarButtonItem = UIBarButtonItem(customView: progressView)
    NSLayoutConstraint.activate([
      progressView.widthAnchor.constraint(equalToConstant: 22),
      progressView.heightAnchor.constraint(equalToConstant: 22)
    ])
  }

  func setupToolBar() {
    toolbarItems = [
      // Reader mode
      UIBarButtonItem(
        image: UIImage(systemName: "text.justifyleft"),
        style: .plain, target: self,
        action: #selector(openSafariReaderMode)
      ),
      UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil),

      // Find in page
      UIBarButtonItem(
        image: UIImage(systemName: "doc.text.magnifyingglass"),
        style: .plain, target: self,
        action: #selector(findInPageFromToolbar)
      ),
      UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil),

      // Reset webview and start over
      UIBarButtonItem(
        image: UIImage(systemName: "arrow.2.squarepath"),
        style: .plain, target: self, action: #selector(redo)
      ),
      UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil),

      // Share
      UIBarButtonItem(
        barButtonSystemItem: .action, target: self, action: #selector(share)
      ),
      UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil),

      // Show settings
      UIBarButtonItem(
        image: UIImage(systemName: "gear"),
        style: .plain, target: self,
        action: #selector(showSettings)
      )
    ]

    let tabsGesture = UILongPressGestureRecognizer(
      target: self, action: #selector(showOpenTabs)
    )
    navigationController?.toolbar.addGestureRecognizer(tabsGesture)

    let newTabGesture = UIShortTapGestureRecognizer(
      target: self, action: #selector(openNewTab)
    )
    newTabGesture.numberOfTapsRequired = 2
    navigationController?.toolbar.addGestureRecognizer(newTabGesture)

    navigationController?.isToolbarHidden = false
  }

  func setupObservables() {
    progressObservable = webView.observe(
      \WKWebView.estimatedProgress, options: .new
    ) { _, change in
      self.progressView.setProgress(value: Float(change.newValue!))
    }
  }

  // https://stackoverflow.com/a/48847585
  class UIShortTapGestureRecognizer: UITapGestureRecognizer {
    let tapMaxDelay: Double = 0.3
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
      super.touchesBegan(touches, with: event)
      DispatchQueue.main.asyncAfter(deadline: .now() + tapMaxDelay) { [weak self] in
        guard let this = self else { return }
        // Enough time has passed and the gesture was not recognized -> It has failed.
        if  this.state != UIGestureRecognizer.State.ended {
          this.state = UIGestureRecognizer.State.failed
        }
      }
    }
  }
}

// MARK: replace webview methods
extension BrowserViewController {
  func respawnWebview() {
    navigationItem.leftBarButtonItem = getLeftItem()
    let newView = factory.build(mode: currentMode, style: currentSyle)
    if let lastUrl = webView.url {
      newView.load(URLRequest(url: lastUrl))
    }
    replaceWebview(with: newView)
  }

  func replaceWebviewSilently(view: WKWebView) {
    navigationController?.view.makeToast(
      "Opened a tab in background, tap to switch",
      duration: 2,
      position: .top
    ) { didTap in
      if didTap { self.replaceWebview(with: view) }
    }
  }

  func replaceWebview(with newView: WKWebView) {
    webView.removeFromSuperview()
    webView = newView
    view.insertSubview(webView, at: 0)
    webView.frame = webViewFrame
    webView.alpha = 0
    UIView.animate(
      withDuration: 0.5, delay: 0,
      usingSpringWithDamping: 0.8,
      initialSpringVelocity: 0,
      options: [],
      animations: {
        self.webView.transform = .identity
        self.webView.alpha = 1
      }
    )
    setupDelegates()
    setupObservables()
    UIMenuController.shared.menuItems = contextualMenus
  }
}

extension BrowserViewController: SearchHolderDelegate {
  func textDidChange(keywords: String?) {
    guard currentMode != .incognito,
          let query = keywords else { return }
    searchHolder.showCompletions(query: query)
  }

  func isStringLink(string: String) -> Bool {
    let types: NSTextCheckingResult.CheckingType = [.link]
    guard let detector = try? NSDataDetector(types: types.rawValue),
          string.count > 0 else { return false }
    if detector.numberOfMatches(
      in: string,
      options: NSRegularExpression.MatchingOptions(rawValue: 0),
      range: NSMakeRange(0, string.count)
    ) > 0 {
      return true
    }
    return false
  }

  func handleSearchInput(keywords: String) {
    // 1. valid url entered
    // 2. no scheme, only host entered
    // 3. random keywords
    guard var url = URL(string: keywords) else {
      return search(keywords: keywords)
    }
    var comp = URLComponents()
    if url.scheme == nil {
      comp.scheme = "https"
      comp.host = url.host
      comp.path = url.path
      url = comp.url!
    }
    if isStringLink(string: url.absoluteString) {
      webView.load(URLRequest(url: url))
    } else {
      search(keywords: keywords)
    }
  }

  func search(keywords: String) {
    let request = URLRequest(url: SearchManager.shared.provider.searchUrl(keywords: keywords))
    webView.load(request)
  }
}

// MARK: Find in page related methods
extension BrowserViewController: UITextFieldDelegate {
  @objc func scrollDownToMatch() {
    webView.evaluateJavaScript("window.hf.marker.nextMatch();")
  }

  @objc func scrollUpToMatch() {
    webView.evaluateJavaScript("window.hf.marker.prevMatch();")
  }

  func startFind() {
    self.findInPageToolbar.isHidden = false
    self.navigationController?.hidesBarsOnTap = false
  }

  func stopFind() {
    self.findInPageToolbar.isHidden = true
    self.navigationController?.hidesBarsOnTap = true
  }

  @objc func unmark() {
    self.webView.evaluateJavaScript("window.hf.marker.clear()")
    stopFind()
  }

  @objc func findInPageFromSelection() {
    webView.evaluateJavaScript(
      """
      window.hf.marker = new PageFinder();
      window.hf.marker.findInPage();
      """
    )
    startFind()
  }

  @objc func findInPageFromToolbar() {
    let alert = UIAlertController(title: "Find in Page", message: nil, preferredStyle: .alert)
    alert.addTextField { field in
      field.text = self.searchBar.text
      field.clearButtonMode = .whileEditing
      field.delegate = self
    }
    alert.addAction(
      UIAlertAction(
        title: "Mark", style: .default,
        handler: { [self] _ in
          guard let keywords = alert.textFields?.first?.text else { return }
          webView.evaluateJavaScript(
            """
            window.hf.marker = new PageFinder();
            window.hf.marker.findInPage(`\(keywords)`);
            """
          )
          startFind()
        })
    )
    alert.addAction(
      UIAlertAction(
        title: "Unmark", style: .cancel, handler: { _ in
          self.unmark()
        })
    )
    present(alert, animated: true, completion: nil)
  }

  func textFieldDidBeginEditing(_ textField: UITextField) {
    textField.selectAll(nil)
    textField.becomeFirstResponder()
  }
}

// MARK: toolbar selectors
extension BrowserViewController {
  @objc func openNewTab() {
    factory.pool.updateSnapshot(view: webView)
    replaceWebview(
      with: factory.build(mode: currentMode, style: currentSyle)
    )
    searchBar.searchTextField.unmarkText()
    searchBar.searchTextField.selectAll(nil)
    searchBar.becomeFirstResponder()
  }

  @objc func searchFromSelection() {
    webView.evaluateJavaScript(
      "window.getSelection().toString()"
    ) { [self] result, _ in
      guard let keywords = result as? String else { return }
      let view = factory.build(mode: currentMode, style: currentSyle)
      view.load(URLRequest(
        url: SearchManager.shared.provider.searchUrl(keywords: keywords)
      ))
      replaceWebviewSilently(view: view)
    }
  }

  @objc func showSettings() {
    let appSettingsViewController = IASKAppSettingsViewController()
    appSettingsViewController.showCreditsFooter = false
    appSettingsViewController.delegate = self
    appSettingsViewController.showDoneButton = false
    present(
      UINavigationController(rootViewController: appSettingsViewController),
      animated: true, completion: nil
    )
  }

  @objc func redo() {
    searchBar.searchTextField.unmarkText()
    searchBar.searchTextField.selectAll(nil)
    searchBar.becomeFirstResponder()
  }

  @objc func share() {
    guard let url = webView.url else { return }
    let activityViewController = UIActivityViewController(
      activityItems: [url], applicationActivities: nil
    )
    present(activityViewController, animated: true, completion: nil)
  }

  @objc func showOpenTabs() {
    factory.pool.updateSnapshot(view: webView)

    let collection = OpenTabsViewController()
    collection.pool = factory.pool
    collection.modalPresentationStyle = .overFullScreen
    collection.openSelectedTab = { item in
      self.replaceWebview(with: item)
    }
    collection.tabDidClose = { [self] item in
      guard item.hashValue == webView.hashValue else { return }
      if let newView = factory.pool.sorted(by: .lastAccessed).filter({
        $0.1.view.hashValue != item.hashValue
      }).first?.1.view {
        replaceWebview(with: newView)
      } else {
        let newView = factory.build(mode: currentMode, style: currentSyle)
        replaceWebview(with: newView)
      }
    }
    collection.allTabsClosed = { [self] () in
      let newView = factory.build(mode: currentMode, style: currentSyle)
      searchHolder.searchBarCancelButtonClicked(searchBar)
      replaceWebview(with: newView)
    }

    present(collection, animated: true, completion: nil)
  }

  @objc func openSafariReaderMode() {
    guard let url = webView.url else { return }

    let config = SFSafariViewController.Configuration()
    config.entersReaderIfAvailable = true
    config.barCollapsingEnabled = true

    let safari = SFSafariViewController(url: url, configuration: config)
    safari.modalPresentationCapturesStatusBarAppearance = true
    safari.dismissButtonStyle = .done
    safari.modalPresentationStyle = .overCurrentContext

    present(safari, animated: true, completion: nil)
  }

  func getLeftItem() -> UIBarButtonItem? {
    guard let view = modeIndicator[currentMode] else { return nil }
    view.addInteraction(UIContextMenuInteraction(delegate: self))
    return UIBarButtonItem(customView: view)
  }

  func displayToast(message: String, image: UIImage?) {
    DispatchQueue.main.async {
      var style = ToastStyle()
      if let size = image?.size {
        style.imageSize = size
      }
      self.navigationController?.view.clearToastQueue()
      self.navigationController?.view.makeToast(
        message, duration: 1.5, position: .top,
        image: image, style: style
      )
    }
  }

  func showToast(_ message: String) {
    DispatchQueue.main.async {
      self.navigationController?.view.clearToastQueue()
      self.navigationController?.view.makeToast(message, duration: 1.5, position: .top)
    }
  }

  func getCurrentValue(for text: SearchHolderView.SearchBarText) -> String? {
    switch text {
    case .url:
      return webView.url?.absoluteString
    case .lastQuery:
      return searchHolder.lastQuery
    case .title:
      return webView.title
    }
  }

  @objc func slideSearchBar(gesture: UIPanGestureRecognizer) {
    guard gesture.state == .ended else { return }

    let velocity = gesture.velocity(in: view)
    let slideFactor = 0.1 * (
      sqrt(velocity.x * velocity.x + velocity.y * velocity.y) / 200
    )
    UIView.animate(
      withDuration: Double(slideFactor * 2), delay: 0,
      usingSpringWithDamping: 0.7,
      initialSpringVelocity: velocity.x / 100,
      options: .curveEaseIn,
      animations: { [self] in
        searchBar.searchTextField.text = getCurrentValue(for: barCounter.down())
      },
      completion: nil
    )
  }

  func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    configurationForMenuAtLocation location: CGPoint
  ) -> UIContextMenuConfiguration? {
    return UIContextMenuConfiguration(
      identifier: nil,
      previewProvider: nil,
      actionProvider: { suggestedActions in
        let normal = UIAction(
          title: "Normal", image: UIImage(systemName: "circle")) { _ in
          self.currentMode = .normal
        }
        let incognito = UIAction(
          title: "Incognito", image: self.incognitoIndicator) { _ in
          self.currentMode = .incognito
        }
        let desktop = UIAction(
          title: "Desktop", image: UIImage(systemName: "desktopcomputer")) { _ in
          self.currentMode = .desktop
        }
        let reader = UIAction(
          title: "Reader", image: UIImage(systemName: "doc.plaintext")) { _ in
          self.openSafariReaderMode()
        }
        return UIMenu(children: [normal, incognito, desktop, reader])
      })
  }
}

// MARK: In app settings methods
extension BrowserViewController: IASKSettingsDelegate {
  func settingsViewControllerDidEnd(_ settingsViewController: IASKAppSettingsViewController) {}

  func settingsViewController(
    _ settingsViewController: IASKAppSettingsViewController,
    buttonTappedFor specifier: IASKSpecifier
  ) {
    switch specifier.title {
    case AppSettingKeys.btnCurrentWebSite:
      guard let host = webView.url?.host else { return }
      deleteCurrentWebsite()
      settingsViewController.view.makeToast(
        "Data for \(host) deleted", duration: 1.5, position: .top
      )

    case AppSettingKeys.btnEverything:
      deleteAll()
      settingsViewController.view.makeToast(
        "All Website data deleted", duration: 1.5, position: .top
      )

    case AppSettingKeys.btnPrivacyPolicy:
      settingsViewController.dismiss(animated: true, completion: nil)
      openNewTab()
      searchHolder.searchBarCancelButtonClicked(searchBar)
      handleSearchInput(keywords: AppSettingKeys.privacyPolicyURL)

    case AppSettingKeys.btnExportHistory:
      let activityViewController = UIActivityViewController(
        activityItems: [AppDatabase.databaseUrl()], applicationActivities: nil
      )
      settingsViewController.present(activityViewController, animated: true, completion: nil)

    case AppSettingKeys.btnDeleteHistory:
      HistoryManager.shared.delete().then { result in
        settingsViewController.view.makeToast("History deleted", duration: 1.5, position: .top)
      }

    default:
      return
    }
  }

  func deleteAll() {
    let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
    let dataStore = WKWebsiteDataStore.default()
    dataStore.fetchDataRecords(ofTypes: allTypes) { records in
      dataStore.removeData(
        ofTypes: allTypes, for: records,
        completionHandler: {
          self.showToast("Deleted everything")
        })
    }
  }

  func deleteCurrentWebsite() {
    guard let host = webView.url?.host  else { return }
    let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
    let dataStore = WKWebsiteDataStore.default()

    dataStore.fetchDataRecords(ofTypes: allTypes) { records in
      dataStore.removeData(
        ofTypes: allTypes,
        for: records.filter { d in
          d.displayName.contains(host)
        },
        completionHandler: {
          self.showToast("Deleted for \(host)")
      })
    }
  }
}

extension UserDefaults {
  @objc dynamic var nativePDFView: Bool {
    get { return bool(forKey: AppSettingKeys.nativePDFView) }
  }

  @objc dynamic var popInBackground: Bool {
    get { return bool(forKey: AppSettingKeys.popInBackground) }
  }
}

// MARK: Webkit related methods
extension BrowserViewController: WKNavigationDelegate,
                                 WKUIDelegate {
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard let title = webView.title,
          let url = webView.url,
          var domain = url.host,
          let keywords = searchBar.searchTextField.text,
          currentMode != .incognito
    else { return }

    webView.evaluateJavaScript("new TextExtractor().parse()") { (result, err) in
      guard let result = result as? String, err == nil else { return }
      let toFilter: Set = ["Adjective", "Noun", "Verb", "Adverb"]
      var tokenSet: Set<String> = []

      let tagger = NLTagger(tagSchemes: [.lexicalClass])
      tagger.string = result
      tagger.enumerateTags(
        in: result.startIndex..<result.endIndex,
        unit: .word, scheme: .lexicalClass,
        options: [
          .omitPunctuation, .omitWhitespace, .omitOther,
          .joinNames, .joinContractions
        ]
      ) { (tag, range) -> Bool in
        if let tag = tag, toFilter.contains(tag.rawValue) {
          tokenSet.insert(String(result[range]))
        }
        return true
      }

      var item = HistoryRecord(
        title: title, url: url,
        domain: self.searchHolder.stripWww(string: &domain),
        content: tokenSet.joined(separator: "[FOSISEP]"),
        keywords: keywords,
        timestamp: Date()
      )
      HistoryManager.shared.insert(record: &item).then { record in
        debugPrint("inserted", record.id)
      }
    }
  }

  func showPDFController(_ url: URL) {
    let pdf = PDFViewController()
    pdf.url = url
    present(pdf, animated: true)
  }

  func webView(_ webView: WKWebView,
               decidePolicyFor navigationResponse: WKNavigationResponse,
               decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    if navigationResponse.response.mimeType == "application/pdf", UserDefaults.standard.nativePDFView,
       let url = navigationResponse.response.url {
      showPDFController(url)
      decisionHandler(.cancel)
    } else {
      decisionHandler(.allow)
    }
  }

  func webView(_ webView: WKWebView,
               decidePolicyFor navigationAction: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    // open new tabs in same view
    if navigationAction.targetFrame == nil {
      webView.load(navigationAction.request)
      decisionHandler(.cancel)
    } else {
      // https://stackoverflow.com/a/44942814
      decisionHandler(
        WKNavigationActionPolicy(
          rawValue: WKNavigationActionPolicy.allow.rawValue + 2
        )!
      )
    }
  }

  func webView(_ webView: WKWebView,
               didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
    urlDidStartLoading(for: webView)
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    urlDidStartLoading(for: webView)
  }

  func urlDidStartLoading(for webView: WKWebView) {
    guard let url = webView.url, var host = url.host else { return }
    var lock: UIImage? {
      if url.scheme?.lowercased() == "https" {
        return UIImage(
          systemName: "lock",
          withConfiguration: UIImage.SymbolConfiguration(textStyle: .body)
        )?.withTintColor(.systemGreen, renderingMode: .alwaysOriginal)
      } else {
        return nil
      }
    }
    displayToast(message: searchHolder.stripWww(string: &host), image: lock)
  }

  func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool { true }

  func webView(
    _ webView: WKWebView,
    contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
    completionHandler: @escaping (UIContextMenuConfiguration?) -> Void
  ) {
    completionHandler(
      UIContextMenuConfiguration(
        identifier: nil,
        previewProvider: {
          return SFSafariViewController(url: elementInfo.linkURL!)
        },
        actionProvider: { _ in
          self.commitURL = elementInfo.linkURL
          let contextMenuTitle = elementInfo.linkURL?.lastPathComponent
          return UIMenu(title: contextMenuTitle!, image: nil,
                        identifier: nil, options: [], children: [])
        }
      )
    )
  }

  func webView(
    _ webView: WKWebView,
    contextMenuForElement elementInfo: WKContextMenuElementInfo,
    willCommitWithAnimator animator: UIContextMenuInteractionCommitAnimating
  ) {
    guard let url = commitURL else { return }
    let view = factory.build(mode: currentMode, style: currentSyle)
    view.load(URLRequest(url: url))
    if UserDefaults.standard.popInBackground {
      replaceWebviewSilently(view: view)
    } else {
      replaceWebview(with: view)
    }
  }
}
