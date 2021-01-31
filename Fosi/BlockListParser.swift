//
//  Parser.swift
//  Fosi
//
//  Created by Chinmay Kulkarni on 1/24/21.
//

import Foundation
import Promises.Swift

typealias RuleList = Array<BlockRule>

struct RemoteList {
  let url: URL
  let lastModified: Date
  let expires: Date
  let name: String

  init(name: String, url: String) {
    self.name = name
    self.url = URL(string: url)!
    lastModified = Date()
    expires = Date(timeIntervalSince1970: 0)
  }

  func isExpired() -> Bool {
    let path = downloadedPath().absoluteString
    if (FileManager.default.fileExists(atPath: path)) {
      do {
        let attr = try FileManager.default.attributesOfItem(atPath: path)
        return Date() > (attr[FileAttributeKey.modificationDate] as? Date ?? expires).addingTimeInterval(3600 * 24 * 4)
      } catch {
        print(error)
      }
    }
    return true
  }

  func downloadedPath() -> URL {
    let documentsURL = try! FileManager.default.url(
      for: .libraryDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: false)
    return documentsURL.appendingPathComponent(name)
  }

  func download() {
    try? FileManager.default.removeItem(at: downloadedPath())
    URLSession.shared.dataTask(with: url) { (data, _, err) in
      guard let data = data else { return }
      let parser = BlockListParser()
      let rules = parser.parse(data: data)
      let encoder = JSONEncoder()
      let contentBlockList = try? encoder.encode(rules)
      try? contentBlockList?.write(to: downloadedPath())
    }.resume()
  }

  func contents() -> String? {
    return try? String(contentsOf: downloadedPath(), encoding: .utf8)
  }
}

class BlockListManager {
  static let defaultLists = [
    RemoteList(name: "easylist", url: "https://easylist.to/easylist/easylist.txt"),
    // RemoteList(name: "easyprivacy", url: "https://easylist.to/easylist/easyprivacy.txt"),
    // RemoteList(name: "fanboy-annoyance", url: "https://secure.fanboy.co.nz/fanboy-annoyance.txt"),
    RemoteList(name: "fanboy-cookiemonster", url: "https://secure.fanboy.co.nz/fanboy-cookiemonster.txt"),
  ]

  static let shared = BlockListManager()

  let lists: Array<RemoteList>
  init(lists: Array<RemoteList> = defaultLists) {
    self.lists = lists
  }

  func refresh() {
    lists.filter { $0.isExpired() }.forEach { $0.download() }
  }
}

class BlockListParser {
  typealias RuleList = Array<BlockRule>

  func parse(data: Data) -> RuleList {
    guard let s = String(data: data, encoding: .ascii) else { return [] }
    return self.constructRules(with: s)
  }

  func parse(s: String) -> RuleList {
    return self.constructRules(with: s)
  }

  enum LineType {
    case verbatim
    case cssDisplayNone
    case overridenCssDisplayNone
    case withFilterOptions
    case exception
    case comment
    case lastModified
    case expires
  }
  func categorize(value: String.SubSequence) -> LineType {
    if value.starts(with: "!") || value.starts(with: "[") { return .comment }
    if value.starts(with: "!") && value.contains("Last Modified")  { return .lastModified }
    if value.starts(with: "!") && value.contains("Expires")  { return .expires }
    if value.contains("#@#") { return .overridenCssDisplayNone }
    if value.starts(with: "||")
        || value.contains("^$")
        || value.contains("$")
        || value.contains("#?#")
        { return .withFilterOptions }
    if value.contains("##")  { return .cssDisplayNone }
    if value.contains("@@")  { return .exception }
    return .verbatim
  }

  private func constructRules(with s: String) -> RuleList {
    var rules: RuleList = []
    let lines = s.split(separator: "\n")

    lines.forEach { line in
      let type = categorize(value: line)
      switch type {
      case .verbatim:
        guard let _ = try? NSRegularExpression(pattern: String(line), options: .caseInsensitive), !line.contains("|") else { return }
        // only interested in "webkit" valid regex
        guard let data = String(line).data(using: .ascii),
              let asciiFilter = String(data: data, encoding: .ascii),
              asciiFilter.count > 5 else { return }

        let index = asciiFilter.lastIndex(of: "^")
        // doesnt exist
        if index == nil {
          rules.append(BlockRule(type: .block, urlFilter: asciiFilter))
        } else if index != nil && index == line.startIndex {
          // exists, and only in the begining
          rules.append(BlockRule(type: .block, urlFilter: asciiFilter))
        }
      case .cssDisplayNone:
        guard let data = String(line).data(using: .ascii),
              let asciiFilter = String(data: data, encoding: .ascii) else { return }

        let components = asciiFilter.components(separatedBy: "##")
        let domains = components.first?.components(separatedBy: ",")
        let ifDomains = domains?.filter { !$0.isEmpty && !$0.starts(with: "~") }
        let unlessDomains = domains?.filter { !$0.isEmpty && $0.starts(with: "~") }
        let selector = components.last
        var trigger: BlockRule.Trigger
        if (ifDomains?.count == 0 && unlessDomains?.count == 0) {
          return
        } else if (unlessDomains?.count == 0) {
          trigger = BlockRule.Trigger(
            urlFilter: "^https?://", ifDomain: ifDomains,
            unlessDomain: nil, loadType: nil,
            resourceType: nil, caseSensitive: nil
          )
        } else if (ifDomains?.count == 0) {
          trigger = BlockRule.Trigger(
            urlFilter: "^https?://", ifDomain: nil,
            unlessDomain: unlessDomains, loadType: nil,
            resourceType: nil, caseSensitive: nil
          )
        } else {
          trigger = BlockRule.Trigger(
            urlFilter: "^https?://", ifDomain: ifDomains,
            unlessDomain: unlessDomains, loadType: nil,
            resourceType: nil, caseSensitive: nil
          )
        }
        rules.append(
          BlockRule(
            action: BlockRule.Action(type: .cssDisplayNone, selector: selector),
            trigger: trigger
          )
        )
      default:
        return
      }
    }
    return rules
  }
}
