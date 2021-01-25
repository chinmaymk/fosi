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
    if (FileManager.default.fileExists(atPath: downloadedPath())) {
      do {
        let attr = try FileManager.default.attributesOfItem(atPath: downloadedPath())
        return Date() > (attr[FileAttributeKey.modificationDate] as? Date ?? expires)
      } catch {
        print(error)
      }
    }
    return true
  }

  func downloadedPath() -> String {
    let documentsURL = try! FileManager.default.url(
      for: .libraryDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: false)
    return documentsURL.appendingPathComponent(name).absoluteString
  }

  func download() {
    URLSession.shared.dataTask(with: url) { (data, _, err) in
      guard err == nil else { return }
      FileManager.default.createFile(atPath: downloadedPath(), contents: data, attributes: [:])
    }.resume()
  }

  func blocklist() -> Promise<RuleList> {
    let parser = BlockListParser()
    return parser.parse(url: url)
  }
}

class BlockListManager {


  static let defaultLists = [
    RemoteList(name: "easylist", url: "https://easylist.to/easylist/easylist.txt"),
    RemoteList(name: "easyprivacy", url: "https://easylist.to/easylist/easyprivacy.txt"),
    RemoteList(name: "fanboy-annoyance", url: "https://secure.fanboy.co.nz/fanboy-annoyance.txt"),
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

  func blocklists() -> Promise<String?> {
    let p = lists.compactMap { $0.blocklist() }
    return all(p).then { rules -> Promise<String?> in
      let encoder = JSONEncoder()
      let p = try! encoder.encode(rules)
      return Promise(String(data: p, encoding: .utf8))
    }
  }
}

class BlockListParser {
  typealias RuleList = Array<BlockRule>

  func parse(url: URL) -> Promise<RuleList> {
    let p = Promise<RuleList>.pending()
    var returnRules: RuleList = []
    URLSession.shared.dataTask(with: url) { (data, _, err) in
      guard let data = data, err == nil else { return }
      let rules = self.constructRules(with: data)
      returnRules.append(contentsOf: rules)
      p.fulfill(returnRules)
    }.resume()
    return p
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
    if value.starts(with: "!") || value.starts(with: "[")  { return .comment }
    if value.starts(with: "!") && value.contains("Last Modified")  { return .lastModified }
    if value.starts(with: "!") && value.contains("Expires")  { return .expires }
    if value.contains("#@#") { return .overridenCssDisplayNone }
    if value.starts(with: "||") || value.contains("^$") || value.contains("$") { return .withFilterOptions }
    if value.contains("##")  { return .cssDisplayNone }
    if value.contains("@@")  { return .exception }
    return .verbatim
  }

  private func constructRules(with data: Data) -> RuleList {
    var rules: RuleList = []
    guard let s = String(data: data, encoding: .utf8) else { return [] }
    let lines = s.split(separator: "\n")
    lines.forEach { line in
      let type = categorize(value: line)
      switch type {
      case .verbatim:
        rules.append(BlockRule(type: .block, urlFilter: String(line)))
      case .cssDisplayNone:
        let components = line.components(separatedBy: "##")
        let domains = components.first?.components(separatedBy: ",")
        let ifDomains = domains?.filter { !$0.starts(with: "~") }
        let unlessDomains = domains?.filter { $0.starts(with: "~") }
        let selector = components.last
        rules.append(
          BlockRule(
            action: BlockRule.Action(type: .cssDisplayNone, selector: selector),
            trigger: BlockRule.Trigger(
              urlFilter: "^https?://", ifDomain: ifDomains,
              unlessDomain: unlessDomains, loadType: nil,
              resourceType: nil, caseSensitive: nil
            ))
        )
      default:
        return
      }
    }
    return rules
  }
}
