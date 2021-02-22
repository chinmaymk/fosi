//
//  SearchHolderView.swift
//  Fosi
//
//  Created by Chinmay Kulkarni on 2/21/21.
//
import Foundation
import UIKit
import Promises

// MARK: Search related methods
protocol SearchHolderDelegate {
  func handleSearchInput(keywords: String)
  func textDidChange(keywords: String?)
}

class SearchHolderView: UIView,
                     UISearchControllerDelegate,
                     UISearchBarDelegate,
                     UITableViewDataSource,
                     UITableViewDelegate  {
  var lastQuery: String?
  private var currentSearchState: SearchState = .editing

  private var suggestionResults = [String]()
  private var topDomains = [String]()
  private var historyRecords = [HistoryRecord]()
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
    case suggestions = "Query Suggestions"
    case domains = "Top domains"
    case history = "History"
  }
  private let sections: [TableSections] = [.history, .suggestions, .domains]
  enum SearchBarText {
    case lastQuery
    case url
    case title
  }

  var delegate: SearchHolderDelegate?

  // MARK: Search bar delegates
  func searchDidConclude() {
    tableView.isHidden = true
    lastQuery = ""
  }

  func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
    guard let text = searchBar.text else { return }
    searchDidConclude()
    delegate?.handleSearchInput(keywords: text)
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

  func showCompletions(query: String) {
    let textField = searchBar.searchTextField
    guard currentSearchState == .editing,
          let rangeOfQuery = textField.textRange(
            from: textField.beginningOfDocument,
            to: textField.selectedTextRange?.start ?? textField.endOfDocument
          ),
          let query = textField.text(in: rangeOfQuery),
          !query.isEmpty, query != lastQuery
    else { return }

    SearchCompletions.shared.getCompletions(keywords: query).then { results in
      self.suggestionResults = Array(results.prefix(5))
      self.tableView.reloadData()
    }

    let domains = DomainCompletions.shared.getCompletions(keywords: query)
    let exact = HistoryManager.shared.exactmatch(keywords: query)
    Promise<String?> { () -> String? in
      let topHistory = try await(exact)
      let domains = try await(domains)

      var completion: String?
      if var domain = topHistory?.domain, domain.starts(with: query) {
        let sanitized = self.stripWww(string: &domain)
        completion = String(sanitized.suffix(from: query.endIndex))
      } else if !domains.isEmpty {
        if let top = domains.first {
          completion = String(top.suffix(from: query.endIndex))
        }
        self.topDomains = Array(domains.prefix(1).suffix(2))
        self.tableView.reloadData()
      }
      return completion
    }.then { completion -> Void in
      textField.setMarkedText(completion, selectedRange: NSRange())
    }

    HistoryManager.shared.search(keywords: query).then { results in
      self.historyRecords = Array(results.prefix(5))
      self.tableView.reloadData()
    }

    tableView.isHidden = false
    lastQuery = query
  }

  func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
    let textField = searchBar.searchTextField
    delegate?.textDidChange(keywords: textField.text)
  }

  // MARK: Table view delegates
  @objc func didTapTableView(gesture: UITapGestureRecognizer) {
    searchBar.resignFirstResponder()
    let touch = gesture.location(in: tableView)
    if let indexPath = tableView.indexPathForRow(at: touch),
       let q = updateSearchText(using: indexPath) {
      searchDidConclude()
      self.delegate?.handleSearchInput(keywords: q)
    }
  }

  func updateSearchText(using indexPath: IndexPath) -> String? {
    switch sections[indexPath.section] {
    case .domains:
      searchBar.searchTextField.text = topDomains[indexPath.row]
      break
    case .suggestions:
      searchBar.searchTextField.text = suggestionResults[indexPath.row]
      break
    case .history:
      return historyRecords[indexPath.row].url.absoluteString
    }
    return searchBar.searchTextField.text
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    searchDidConclude()
    if let val = updateSearchText(using: indexPath) {
      self.delegate?.handleSearchInput(keywords: val)
    }
  }

  func getSectionResultCount(section: Int) -> Int {
    switch sections[section] {
    case .domains:
      return topDomains.count
    case .suggestions:
      return suggestionResults.count
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
      cell.textLabel?.text = topDomains[indexPath.row]
      return cell

    case .suggestions:
      cell.textLabel?.text = suggestionResults[indexPath.row]
      return cell

    case .history:
      let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "subtitleCell")

      var item = historyRecords[indexPath.row]
      cell.textLabel?.text = item.title

      let host = stripWww(string: &item.domain)
      let timeAgo = item.timestamp.timeAgoDisplay()
      cell.detailTextLabel?.text = "\(host) ○ \(timeAgo)"
      return cell
    }
  }

  func stripWww(string: inout String) -> String {
    let prefix = "www."
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
