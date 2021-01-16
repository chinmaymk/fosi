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

class BrowserViewController: UIViewController,
                             UIScrollViewDelegate,
                             UINavigationControllerDelegate,
                             UIContextMenuInteractionDelegate {

  let factory = WebviewFactory.shared
  lazy var webView = factory.build(mode: .normal, style: currentSyle)
  var commitURL: URL?
  var currentMode: WebviewMode = .normal {
    didSet {
      navigationItem.leftBarButtonItem = getLeftItem()
      let newView = factory.build(mode: currentMode, style: currentSyle)
      if let lastUrl = webView.url {
        newView.load(URLRequest(url: lastUrl))
      }
      replaceWebview(with: newView)
    }
  }
  var currentSyle: UIUserInterfaceStyle {
    get { return traitCollection.userInterfaceStyle }
  }
  lazy var incognitoIndicator: UIImage = {
    let hfRED = UIColor(red: 0.85, green: 0.12, blue: 0.09, alpha: 1.00)
    return UIImage(systemName: "bolt.circle")!
      .withTintColor(hfRED, renderingMode: .alwaysOriginal)
  }()

  // Search Related stuff
  var lastQuery: String?
  var currentSearchState: SearchState = .editing

  var googleResults = [String]()
  var topdomains = [String]()
  var historyRecords = [HistoryRecord]()
  enum SearchState {
    case editing
    case submitted
    case cancelled
  }
  let searchBar: UISearchBar = {
    let view = UISearchBar()
    view.autocapitalizationType = .none
    view.autocorrectionType = .no
    view.placeholder = "What do you want to know?"
    return view
  }()
  let tableView: UITableView = UITableView()
  enum TableSections: String {
    case google = "Google Suggestions"
    case domains = "Top domains"
    case history = "History"
  }
  let sections: [TableSections] = [.history, .google, .domains]
  enum SearchBarText {
    case lastQuery
    case url
    case title
  }
  let counter = WheelCounter<SearchBarText>(labels: [.lastQuery, .title, .url])

  // track progress
  let progressView = CircularProgressView()
  var progressObservable: NSKeyValueObservation?

  // additional actions for text
  let contextualMenus = [
    UIMenuItem(title: "Google", action: #selector(searchGoogleFromSelection)),
    UIMenuItem(title: "In Page", action: #selector(findInPageFromSelection))
  ]
  lazy var modeIndicator = [
    WebviewMode.desktop: UIImageView(image: UIImage(systemName: "desktopcomputer")),
    WebviewMode.incognito: UIImageView(image: incognitoIndicator),
    WebviewMode.normal: progressView,
    WebviewMode.noamp: progressView,
  ]

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
  }

  override func viewDidLayoutSubviews() {
    webView.frame = webViewFrame
  }

  override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
    super.viewWillTransition(to: size, with: coordinator)

    switch UIDevice.current.orientation {
    case .landscapeLeft, .landscapeRight:
      topMask.isHidden = true
    default:
      topMask.isHidden = false
    }

    webViewFrame = CGRect(origin: .zero, size: size)
    webView.frame = webViewFrame
    tableView.frame = webViewFrame
  }

  override func viewWillAppear(_ animated: Bool) {
    webView.frame = webViewFrame
    tableView.frame = webViewFrame
  }

  func replaceWebview(with newView: WKWebView) {
    webView.removeFromSuperview()
    webView = newView
    view.insertSubview(webView, at: 0)
    webView.frame = webViewFrame
    webView.alpha = 0
    UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: [], animations: {
      self.webView.transform = .identity
      self.webView.alpha = 1
    })
    setupDelegates()
    setupObservables()
    UIMenuController.shared.menuItems = contextualMenus
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    guard UIApplication.shared.applicationState == .inactive else { return }

    let confirmAlert = UIAlertController(
      title: "System Appearance Changed",
      message: "HyperFocus detected a change in display settings, Would you like to reload?",
      preferredStyle: .actionSheet
    )

    confirmAlert.addAction(UIAlertAction(title: "Confirm", style: .default, handler: { [self] (action: UIAlertAction!) in
      let url = webView.url
      let newView = factory.build(mode: currentMode, style: currentSyle)
      if let url = url {
        newView.load(URLRequest(url: url))
      }
      replaceWebview(with: newView)
    }))

    confirmAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
    present(confirmAlert, animated: true, completion: nil)
  }

  func setupSearchExperience() {
    searchBar.delegate = self
    searchBar.showsCancelButton = true
    searchBar.sizeToFit()
    navigationItem.titleView = searchBar

    tableView.isHidden = true
    tableView.dataSource = self
    tableView.delegate = self
    let gesture = UITapGestureRecognizer(target: self, action: #selector(didTapTableView(gesture:)))
    gesture.cancelsTouchesInView = false
    tableView.addGestureRecognizer(gesture)

    guard let bar = navigationController?.navigationBar else { return }
    let down = UIPanGestureRecognizer(target: self, action: #selector(self.slideSearchBar))
    bar.addGestureRecognizer(down)
  }

  func setupDelegates() {
    webView.navigationDelegate = self
    webView.uiDelegate = self
    webView.scrollView.delegate = self
  }

  var webViewFrame: CGRect = .zero
  let topMask = UIView()

  func setupBrowsingExperience() {
    view.addSubview(webView)
    self.edgesForExtendedLayout = [.bottom, .left, .right]
    webView.frame = view.frame
    webViewFrame = view.frame
    print("layout frame", view.frame)

    topMask.backgroundColor = .systemBackground
    topMask.translatesAutoresizingMaskIntoConstraints = false
    navigationController?.navigationBar.isTranslucent = false
    view.addSubview(topMask)
    NSLayoutConstraint.activate([
      topMask.topAnchor.constraint(equalTo: view.topAnchor),
      topMask.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      topMask.widthAnchor.constraint(equalTo: view.widthAnchor),
    ])

    view.addSubview(tableView)
    tableView.isScrollEnabled = true
    tableView.bounces = false
    tableView.frame = view.frame

    progressView.translatesAutoresizingMaskIntoConstraints = false
    let interaction = UIContextMenuInteraction(delegate: self)
    progressView.addInteraction(interaction)

    navigationItem.leftBarButtonItem = UIBarButtonItem(customView: progressView)

    NSLayoutConstraint.activate([
      progressView.widthAnchor.constraint(equalToConstant: 22),
      progressView.heightAnchor.constraint(equalToConstant: 22)
    ])
  }

  @objc func openNewTab() {
    factory.pool.updateSnapshot(view: webView)
    let newView = factory.build(mode: currentMode, style: currentSyle)
    replaceWebview(with: newView)
    searchBar.searchTextField.unmarkText()
    searchBar.searchTextField.selectAll(nil)
    searchBar.becomeFirstResponder()
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

  func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
    return UIContextMenuConfiguration(
      identifier: nil,
      previewProvider: nil,
      actionProvider: { suggestedActions in
        let normal = UIAction(title: "Normal", image: UIImage(systemName: "circle")) { action in
          self.currentMode = .normal
        }

        let incognito = UIAction(title: "Incognito", image: self.incognitoIndicator) { action in
          self.currentMode = .incognito
        }

        let desktop = UIAction(title: "Desktop", image: UIImage(systemName: "desktopcomputer")) { action in
          self.currentMode = .desktop
        }

        let reader = UIAction(title: "Reader", image: UIImage(systemName: "doc.plaintext")) { action in
          self.openSafariReaderMode()
        }

        return UIMenu(children: [normal,incognito, desktop, reader])
      })
  }

  func setupToolBar() {
    let toolBarItems = [
      // Reader mode
      UIBarButtonItem(image: UIImage(systemName: "text.justifyleft"), style: .plain, target: self, action: #selector(openSafariReaderMode)),
      UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil),

      // Find in page
      UIBarButtonItem(image: UIImage(systemName: "doc.text.magnifyingglass"), style: .plain, target: self, action: #selector(findInPageFromToolbar)),
      UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil),

      // Reset webview and start over
      UIBarButtonItem(image: UIImage(systemName: "arrow.2.squarepath"), style: .plain, target: self, action: #selector(redo)),
      UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil),

      // Share
      UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(share)),
      UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil),

      // delete history
      UIBarButtonItem(image: UIImage(systemName: "gear"), style: .plain, target: self, action: #selector(deleteHistory))
    ]

    let longGesture = UILongPressGestureRecognizer(target: self, action: #selector(showOpenTabsVC))
    let openTab = UIShortTapGestureRecognizer(target: self, action: #selector(openNewTab))
    openTab.numberOfTapsRequired = 2

    navigationController?.toolbar.addGestureRecognizer(longGesture)
    navigationController?.toolbar.addGestureRecognizer(openTab)

    toolbarItems = toolBarItems
    navigationController?.isToolbarHidden = false
  }

  func isStringLink(string: String) -> Bool {
    let types: NSTextCheckingResult.CheckingType = [.link]
    let detector = try? NSDataDetector(types: types.rawValue)
    guard (detector != nil && string.count > 0) else { return false }
    if detector!.numberOfMatches(in: string, options: NSRegularExpression.MatchingOptions(rawValue: 0), range: NSMakeRange(0, string.count)) > 0 {
      return true
    }
    return false
  }

  func handleSearchInput(keywords: String) {
    // 1. valid url entered
    // 2. no scheme, only host entered
    // 3. random keywords
    if var url = URL(string: keywords) {
      var comp = URLComponents()
      if url.scheme == nil {
        comp.scheme = "https"
        comp.host = url.host
        comp.path = url.path
        url = comp.url!
      }
      if isStringLink(string: url.absoluteString) {
        webView.load(URLRequest(url: url))
        return
      }
    }
    searchGoogle(keywords: keywords)
  }

  func searchGoogle(keywords: String) {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "google.com"
    components.path = "/search"
    components.queryItems = [
      URLQueryItem(name: "q", value: keywords)
    ]
    let request = URLRequest(url: components.url!)
    webView.load(request)
  }

  func setupObservables() {
    progressObservable = webView.observe(\WKWebView.estimatedProgress, options: .new) { _, change in
      let val = Float(change.newValue!)
      self.progressView.setProgress(value: val)
    }
    webView.configuration.userContentController.removeScriptMessageHandler(forName: "readerMode")
    webView.configuration.userContentController.add(self, name: "readerMode")
  }
}

// MARK: selectors
extension BrowserViewController: UITextFieldDelegate {

  @objc func searchGoogleFromSelection() {
    webView.evaluateJavaScript("window.getSelection().toString()") { [self] (result, _) in
      let view = factory.build(mode: currentMode, style: currentSyle)
      var components = URLComponents()
      components.scheme = "https"
      components.host = "google.com"
      components.path = "/search"
      components.queryItems = [
        URLQueryItem(name: "q", value: result as? String)
      ]
      view.load(URLRequest(url: components.url!))
      self.navigationController?.view.makeToast("Opened a tab in background, tap to switch", duration: 2, position: .top) { didTap in
        if (didTap) { self.replaceWebview(with: view) }
      }

    }
  }

  @objc func findInPageFromSelection() {
    webView.evaluateJavaScript("window.hf.marker = new PageFinder(); window.hf.marker.findInPage();")
  }

  @objc func findInPageFromToolbar() {
    let alert = UIAlertController(title: "Find in Page", message: "", preferredStyle: .alert)

    alert.addTextField { (textField) in
      textField.text = self.searchBar.text
      textField.clearButtonMode = .whileEditing
      textField.delegate = self
    }

    alert.addAction(UIAlertAction(title: "Mark", style: .default, handler: { [weak alert] (_) in
      let textField = alert?.textFields![0] // Force unwrapping because we know it exists.
      if let keywords =  textField?.text {
        self.webView.evaluateJavaScript("window.hf.marker = new PageFinder(); window.hf.marker.findInPage(`\(keywords)`);")
      }
    }))

    alert.addAction(UIAlertAction(title: "Unmark", style: .cancel, handler: { (_) in
      self.webView.evaluateJavaScript("window.hf.marker.clear()")
    }))

    // alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
    present(alert, animated: true, completion: nil)
  }

  func textFieldDidBeginEditing(_ textField: UITextField) {
    textField.selectAll(nil)
    textField.becomeFirstResponder()
  }

  private func findInPage(keywords: String?) {

  }

  @objc func deleteHistory() {
    let confirmAlert = UIAlertController(title: "Delete Website Data", message: "This operation is irrersible.", preferredStyle: .actionSheet)

    let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
    let dataStore = WKWebsiteDataStore.default()

    confirmAlert.addAction(UIAlertAction(title: "All", style: .destructive, handler: { _ in
      let p = HistoryManager.shared.delete(domain: nil)
      dataStore.fetchDataRecords(ofTypes: allTypes) { records in
        dataStore.removeData(ofTypes: allTypes, for: records, completionHandler: {
          p.then { result in
            self.showToast("Deleted everything")
          }
        })
      }
    }))

    confirmAlert.addAction(UIAlertAction(title: "Current website", style: .destructive, handler: { _ in
      guard let host = self.webView.url?.host  else { return }
      let p = HistoryManager.shared.delete(domain: host)
      dataStore.fetchDataRecords(ofTypes: allTypes) { records in
        let filtered = records.filter { d in
          d.displayName.contains(host)
        }
        dataStore.removeData(ofTypes: allTypes, for: filtered, completionHandler: {
          p.then { result in
            self.showToast("Deleted for \(host)")
          }
        })
      }
    }))

    confirmAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
    present(confirmAlert, animated: true, completion: nil)
  }

  @objc func redo() {
    searchBar.searchTextField.unmarkText()
    searchBar.searchTextField.selectAll(nil)
    searchBar.becomeFirstResponder()
  }

  @objc func share() {
    guard let url = webView.url else { return }

    let activityViewController = UIActivityViewController(activityItems: [url],
                                                          applicationActivities: nil)
    // so that iPads won't crash
    activityViewController.popoverPresentationController?.sourceView = view

    // present the view controller
    present(activityViewController, animated: true, completion: nil)
  }

  @objc func refresh() {
    webView.reload()
  }

  @objc func openSafariReaderMode() {
    guard let url = webView.url else { return }
    let config = SFSafariViewController.Configuration()
    config.entersReaderIfAvailable = true
    let safariVC = SFSafariViewController(url: url, configuration: config)
    safariVC.modalPresentationCapturesStatusBarAppearance = true
    safariVC.dismissButtonStyle = .done
    config.barCollapsingEnabled = true
    safariVC.modalPresentationStyle = .overCurrentContext
    present(safariVC, animated: true, completion: nil)
  }

  func getLeftItem() -> UIBarButtonItem? {
    if let view = modeIndicator[currentMode] {
      let interaction = UIContextMenuInteraction(delegate: self)
      view.addInteraction(interaction)
      return UIBarButtonItem(customView: view)
    }
    return nil
  }

  func displayToast(message: String, image: UIImage?) {
    if (message.isEmpty) {
      return
    }

    DispatchQueue.main.async {
      var style = ToastStyle()
      if let size = image?.size {
        style.imageSize = size
      }
      self.navigationController?.view.makeToast(message, duration: 1.5, position: .top, image: image, style: style)
    }
  }

  func showToast(_ message: String) {
    if (message.isEmpty) {
      return
    }

    DispatchQueue.main.async {
      self.navigationController?.view.makeToast(message, duration: 1.5, position: .top)
    }
  }

  func getCurrentValue(for text: SearchBarText) -> String? {
    switch text {
    case .url:
      return webView.url?.absoluteString
    case .lastQuery:
      return lastQuery
    case .title:
      return webView.title
    }
  }

  @objc func slideSearchBar(gesture: UIPanGestureRecognizer) {
    guard gesture.state == .ended else {
      return
    }

    let velocity = gesture.velocity(in: view)
    let magnitude = sqrt((velocity.x * velocity.x) + (velocity.y * velocity.y))
    let slideMultiplier = magnitude / 200
    let slideFactor = 0.1 * slideMultiplier

    UIView.animate(withDuration: Double(slideFactor * 2), delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: velocity.x / 100, options: .curveEaseIn, animations: {
      self.searchBar.searchTextField.text = self.getCurrentValue(for: self.counter.down())
    }, completion: nil)
  }
}

// MARK: Webkit related methods
extension BrowserViewController: WKNavigationDelegate,
                                 WKScriptMessageHandler,
                                 WKUIDelegate {

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    if message.name == "readerMode", let dict = message.body as? NSDictionary {
      print(dict)
    }
  }

  func evaluateScript(file: String) {
    let url = Bundle.main.url(forResource: file, withExtension: "")
    let source = try! String(contentsOf: url!)
    return webView.evaluateJavaScript(source)
  }

  func urlDidStartLoading() {
    guard let url = webView.url, var host = url.host else { return }

    if (url.path.hasSuffix(".pdf")) {
      showToast("Loading PDF \(url.path)")
      webView.stopLoading()
      let pdf = PDFViewController()
      pdf.modalPresentationStyle = .pageSheet
      pdf.setURL(url: url)
      present(pdf, animated: true)
    } else {
      var lock: UIImage?
      if (url.scheme?.lowercased() == "https") {
        lock = UIImage(
          systemName: "lock",
          withConfiguration: UIImage.SymbolConfiguration(textStyle: .body))?
          .withTintColor(.systemGreen, renderingMode: .alwaysOriginal)
      }
      self.displayToast(message: self.removePrefix(string: &host, prefix: "www."), image: lock)
    }
  }

  @objc func showOpenTabsVC() {
    factory.pool.updateSnapshot(view: webView)
    let collection = OpenTabsViewController()
    collection.pool = factory.pool
    collection.modalPresentationStyle = .overFullScreen
    collection.openNewTab = { item in
      self.replaceWebview(with: item)
    }
    collection.tabDidClose = { item in
      guard item.hashValue == self.webView.hashValue else { return }

      if let newView = self.factory.pool.sorted(by: .lastAccessed).filter({
        $0.1.view.hashValue != item.hashValue
      }).first?.1.view {
        self.replaceWebview(with: newView)
      } else {
        let newView = self.factory.build(mode: self.currentMode, style: self.currentSyle)
        self.replaceWebview(with: newView)
      }
    }
    collection.allTabsClosed = {
      let newView = self.factory.build(mode: self.currentMode, style: self.currentSyle)
      self.searchBarCancelButtonClicked(self.searchBar)
      self.replaceWebview(with: newView)
    }

    present(collection, animated: true, completion: nil)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard let title = webView.title,
          let url = webView.url,
          let domain = url.host,
          let keywords = searchBar.searchTextField.text,
          currentMode != .incognito
    else { return }

    var item = HistoryRecord(title: title,
                             url: url,
                             domain: domain,
                             keywords: keywords,
                             timestamp: Date())

    let promise = HistoryManager.shared.insert(record: &item)
    promise.then { (record)  in
      print("record inserted \(record.id!)")
    }
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

    if navigationAction.targetFrame == nil {
      openNewTab()
      webView.load(navigationAction.request)
      decisionHandler(.cancel)
    } else {
      // https://stackoverflow.com/a/44942814
      decisionHandler(WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2)!)
    }
  }

  func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
    urlDidStartLoading()
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    urlDidStartLoading()
  }

  func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
    true
  }

  func webView(_ webView: WKWebView, contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo, completionHandler: @escaping (UIContextMenuConfiguration?) -> Void) {
    let configuration =
      UIContextMenuConfiguration(
        identifier: nil,
        previewProvider: {
          return SFSafariViewController(url: elementInfo.linkURL!)
        },
        actionProvider: { elements in
          guard elements.isEmpty == false else { return nil }
          self.commitURL = elementInfo.linkURL
          // Add our custom action to the existing actions passed in.
          var elementsToUse = elements
          let editMenu = UIMenu(title: "Open tab", options: .displayInline, children: [])
          elementsToUse.append(editMenu)
          let contextMenuTitle = elementInfo.linkURL?.lastPathComponent
          return UIMenu(title: contextMenuTitle!, image: nil,
                        identifier: nil, options: [], children: elementsToUse)
        }
      )
    completionHandler(configuration)
  }

  func webView(_ webView: WKWebView, contextMenuForElement elementInfo: WKContextMenuElementInfo, willCommitWithAnimator animator: UIContextMenuInteractionCommitAnimating) {
    guard let url = commitURL else { return }
    let view = factory.build(mode: currentMode, style: currentSyle)
    view.load(URLRequest(url: url))
    self.navigationController?.view.makeToast("Opened a tab in background, tap to switch", duration: 1.5, position: .top) { didTap in
      if (didTap) { self.replaceWebview(with: view) }
    }
  }
}


// MARK: Search related methods
extension BrowserViewController: UISearchControllerDelegate,
                                 UISearchBarDelegate,
                                 UITableViewDataSource,
                                 UITableViewDelegate {

  // MARK: Search bar delegates
  func searchDidConclude() {
    self.tableView.isHidden = true
    lastQuery = ""
  }

  func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
    guard let text = searchBar.text else { return }
    searchDidConclude()
    handleSearchInput(keywords: text)
    currentSearchState = .submitted
  }

  func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
    searchBar.text = ""
    searchBar.resignFirstResponder()
    searchDidConclude()
    currentSearchState = .cancelled
  }

  func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
    currentSearchState = .editing
  }

  func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
    let textField = self.searchBar.searchTextField

    guard let rangeOfQuery = textField.textRange(
      from: textField.beginningOfDocument,
      to: textField.selectedTextRange?.start ?? textField.endOfDocument
    ),
    let query = textField.text(in: rangeOfQuery),
    currentSearchState == .editing,
    !query.isEmpty, query != lastQuery
    else { return }

    let google = GoogleCompletions.shared.getCompletions(keywords: query)
    let domains = DomainCompletions.shared.getCompletions(keywords: query)
    let history = HistoryManager.shared.search(keywords: query)
    let exact = HistoryManager.shared.exactmatch(keywords: query)

    google.then { google in
      self.googleResults = Array(google.prefix(5))
      self.tableView.reloadData()
    }

    Promise<String?> { () -> String? in
      let topHistory = try await(exact)
      let domains = try await(domains)

      var completion: String?
      if var domain = topHistory?.domain, domain.starts(with: query) {
        let sanitized = self.removePrefix(string: &domain, prefix: "www.")
        completion = String(sanitized.suffix(from: query.endIndex))
      } else if !domains.isEmpty {
        if let top = domains.first {
          completion = String(top.suffix(from: query.endIndex))
        }
        self.topdomains = Array(domains.prefix(1).suffix(2))
        self.tableView.reloadData()
      }
      return completion
    }.then { completion -> Void in
      textField.setMarkedText(completion, selectedRange: NSRange())
    }

    history.then { results in
      self.historyRecords = Array(results.prefix(5))
      self.tableView.reloadData()
    }

    self.tableView.isHidden = false
    lastQuery = query
  }

  // MARK: Table view delegates
  @objc func didTapTableView(gesture: UITapGestureRecognizer) {
    // We get rid of our keyboard on screen
    searchBar.resignFirstResponder()
    // Find the location of the touch relative to the tableView
    let touch = gesture.location(in: tableView)
    // Convert that touch point to an index path
    if let indexPath = tableView.indexPathForRow(at: touch) {
      let q = getSelectedRow(indexPath: indexPath)
      searchDidConclude()
      handleSearchInput(keywords: q)
    }
  }

  func getSelectedRow(indexPath: IndexPath) -> String {
    var q = ""
    switch sections[indexPath.section] {
    case .domains:
      q = topdomains[indexPath.row]
      searchBar.searchTextField.text = q
      break
    case .google:
      q = googleResults[indexPath.row]
      searchBar.searchTextField.text = q
      break
    case .history:
      q = historyRecords[indexPath.row].url.absoluteString
      break
    }
    return q
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    searchDidConclude()
    handleSearchInput(keywords: getSelectedRow(indexPath: indexPath))
  }

  func getSectionResultCount(section: Int) -> Int {
    switch sections[section] {
    case .domains:
      return topdomains.count
    case .google:
      return googleResults.count
    case .history:
      return historyRecords.count
    }
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return getSectionResultCount(section: section)
  }

  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    if section < sections.count && getSectionResultCount(section: section) > 0 {
      return sections[section].rawValue
    }
    return nil
  }

  func numberOfSections(in tableView: UITableView) -> Int {
    sections.count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = UITableViewCell(style: .default, reuseIdentifier: "defaultCell")

    switch sections[indexPath.section] {
    case .domains:
      cell.textLabel?.text = topdomains[indexPath.row]
      return cell
    case .google:
      cell.textLabel?.text = googleResults[indexPath.row]
      return cell
    case .history:
      let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "subtitleCell")
      cell.textLabel?.text = historyRecords[indexPath.row].title
      let host = removePrefix(string: &historyRecords[indexPath.row].domain, prefix: "www.")
      cell.detailTextLabel?.text = "\(host) ○ \(historyRecords[indexPath.row].timestamp.timeAgoDisplay())"
      return cell
    }
  }

  func removePrefix(string: inout String, prefix: String) -> String {
    if string.starts(with: prefix) {
      string.removeFirst(prefix.count)
    }
    return string
  }
}

extension Date {
  func timeAgoDisplay() -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: self, relativeTo: Date())
  }
}
