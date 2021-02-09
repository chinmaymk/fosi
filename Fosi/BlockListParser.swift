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

  static let topDomains = Set(DomainCompletions.shared.data.dropFirst(100))

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
      let incoming = String(data: data, encoding: .ascii)
      let result = parse_easylist(incoming)
      defer {
        free_contentlist(UnsafeMutablePointer(mutating: result))
      }
      guard let unwrapped = result,
            let ascii = String(cString: unwrapped, encoding: .ascii)
      else { return }
      let decoder = JSONDecoder()
      let parsedList = String(cString: unwrapped) // we know this exists
      guard var rules = try? decoder.decode(Array<BlockRule>.self, from: ascii.data(using: .utf8)!)
      else { return }
      rules.removeAll { (rule) -> Bool in
        let regex = try? NSRegularExpression(pattern: rule.trigger.urlFilter, options: .caseInsensitive)
        if let domains = rule.trigger.ifDomain, rule.action.type == .cssDisplayNone {
          if !domains.allSatisfy({ (d) -> Bool in
            RemoteList.topDomains.contains(d) && d.canBeConverted(to: .ascii)
          }) {
            return true
          }
        }
        return regex == nil
          || rule.trigger.urlFilter.contains("|")
          || rule.trigger.urlFilter.contains("\\w")
      }
      if rules.count > 50000 {
        rules.removeFirst(rules.count - 50000)
      }
      let encoder = JSONEncoder()
      let contentBlockList = try? encoder.encode(rules)
      try? contentBlockList?.write(to: downloadedPath())
    }.resume()
  }

  func contents() -> String? {
    return try? String(contentsOf: downloadedPath(), encoding: .ascii)
  }
}

class BlockListManager {
  static let defaultLists = [
    RemoteList(name: "easylist.json", url: "https://easylist.to/easylist/easylist.txt"),
    // RemoteList(name: "easyprivacy", url: "https://easylist.to/easylist/easyprivacy.txt"),
    // RemoteList(name: "fanboy-annoyance", url: "https://secure.fanboy.co.nz/fanboy-annoyance.txt"),
    RemoteList(name: "fanboy-cookiemonster.json", url: "https://secure.fanboy.co.nz/fanboy-cookiemonster.txt"),
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
    guard let s = String(data: data, encoding: .utf8) else { return [] }
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
    case comment
    case lastModified
    case expires
    case domainRule
    case overrideDomainRule
    case filterResourceRule
    case domainResourceWithCap
  }
  func categorize(value: String.SubSequence) -> LineType {
    if value.starts(with: "!") || value.starts(with: "[") { return .comment }
    if value.starts(with: "!") && value.contains("Last Modified")  { return .lastModified }
    if value.starts(with: "!") && value.contains("Expires")  { return .expires }
    if value.contains("#@#") { return .overridenCssDisplayNone }
    if value.starts(with: "@@||") && value.contains("^") { return .overrideDomainRule }
    if value.starts(with: "||") && value.contains("^$") { return .domainResourceWithCap }
    if value.starts(with: "||") && value.contains("$") { return .filterResourceRule }
    if value.starts(with: "||") && value.contains("^") { return .domainRule }
    if value.contains("#?#") { return .withFilterOptions }
    if value.contains("##")  { return .cssDisplayNone }
    return .verbatim
  }

  private func constructRules(with s: String) -> RuleList {
    var rules: RuleList = []
    let topDomains = Set(DomainCompletions.shared.data.dropFirst(100))
    let lines = s.split(separator: "\n")

    func getResourceType(resourceTypes: String) -> Array<String> {
      let loadTypes: Array<String> = ["document", "image", "style-sheet", "script", "font", "raw", "svg-document", "media", "popup"]
      var typesToSend: Array<String> = []
      for type in loadTypes {
        if resourceTypes.contains(type) {
          typesToSend.append(type)
        }
      }
      return typesToSend
    }

    func getLoadTypes(filter: String) -> Array<String> {
      var loadTypes: Array<String> = []
      if filter.contains("third-party") {
        loadTypes.append("third-party")
      }
      return loadTypes
    }

    func convertToAscii(subsequence val: String.SubSequence) -> String? {
      return convertToAscii(string: String(val))
    }

    func convertToAscii(string val: String) -> String? {
      if let data = String(val).data(using: .ascii),
         let asciiFilter = String(data: data, encoding: .ascii) {
        return asciiFilter
      }
      return nil
    }

    func validateRegex(line: String.SubSequence?) -> Bool {
      guard let line = line,
            let _ = try? NSRegularExpression(pattern: String(line), options: .caseInsensitive),
            !line.contains("*"),
            !line.contains("|") else { return false }
      return true
    }

    func parseDomainRule(line: String) -> BlockRule? {
      guard let asciiFilter = convertToAscii(string: line) else { return nil }

      let firstSplit = asciiFilter.split(separator: "$")
      let urlFilter = firstSplit.first?.split(separator: "^").first
      guard validateRegex(line: urlFilter) else { return nil }
      let resourceTypes = firstSplit.last

      return BlockRule(type: .block, urlFilter: String(urlFilter ?? "^https?://"), resourceType: getResourceType(resourceTypes: String(resourceTypes ?? "")), loadType: getLoadTypes(filter:  String(resourceTypes ?? "")), ifDomain: nil)
    }

    lines.forEach { line in
      let type = categorize(value: line)
      switch type {
      case .verbatim:
        // only interested in "webkit" valid regex
        guard let _ = try? NSRegularExpression(pattern: String(line), options: .caseInsensitive),
              !line.contains("*"),
              !line.contains("*"),
              !line.contains("|") else { return }
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
        guard let asciiFilter = convertToAscii(subsequence: line) else { return }
        let components = asciiFilter.components(separatedBy: "##")
        guard let urlfilter = components.first else { return }
        let domains = urlfilter.components(separatedBy: ",").filter { !$0.isEmpty }
        let hits = domains.filter { val in return topDomains.contains(val) }
        if !urlfilter.isEmpty && hits.count == 0 { return }
        let ifDomains = domains.filter { !$0.starts(with: "~") }
        let unlessDomains = domains.filter { $0.starts(with: "~") }
        let selector = components.last
        rules.append(
          BlockRule(type: .cssDisplayNone, urlFilter: "^https?://", ifDomain: ifDomains, unlessDomain: unlessDomains, selector: selector)
        )

      case .domainRule:
        let prefixStripped = line.replacingOccurrences(of: "||", with: "")
        if !prefixStripped.contains("domain="), let rule = parseDomainRule(line: prefixStripped) {
          rules.append(rule)
        }

      case .overrideDomainRule:
        let prefixStripped = line.replacingOccurrences(of: "@@", with: "")
          .replacingOccurrences(of: "||", with: "")
        if let rule = parseDomainRule(line: prefixStripped) {
          rules.append(rule)
        }
      case .filterResourceRule:
        guard let asciiFilter = convertToAscii(subsequence: line) else { return }
        let prefixStripped = asciiFilter.replacingOccurrences(of: "||", with: "")
        if let rule = parseDomainRule(line: prefixStripped) {
          rules.append(rule)
        }

      case .domainResourceWithCap:
        let prefixStripped = line.replacingOccurrences(of: "||", with: "")
        if let rule = parseDomainRule(line: prefixStripped) {
          rules.append(rule)
        }

      default:
        return
      }
    }
    return rules
  }
}
