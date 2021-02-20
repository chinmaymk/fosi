//
//  CompletionProviders.swift
//  Fosi
//
//  Created by Chinmay Kulkarni on 12/29/20.
//

import Foundation
import SWXMLHash
import Promises

protocol CompletionProvider {
  func getCompletions(keywords: String) -> Promise<[String]>
}

class DomainCompletions: CompletionProvider {
  let MAX_MATCHES = 5
  static let shared = DomainCompletions()

  lazy var data: [String] = {
    let url = Bundle.main.url(forResource: "topdomains", withExtension: "txt")
    let source = try! String(contentsOf: url!)
    return source.components(separatedBy: "\n")
  }()

  func getCompletions(keywords: String) -> Promise<[String]> {
    // if user is still typing, chances of finding a match are very low
    if keywords.count > 12 {
      return Promise([String]())
    }
    
    var buffer = [String]()
    var it = data.makeIterator()
    while buffer.count < MAX_MATCHES,
          let domain = it.next() {
      if domain.starts(with: keywords) {
        buffer.append(domain)
      }
    }
    return Promise(buffer)
  }
}

extension UserDefaults {
  @objc dynamic var querySuggestions: Bool {
    get { return bool(forKey: AppSettingKeys.querySuggestions) }
  }
}

class SearchCompletions: CompletionProvider {
  static let shared = SearchCompletions()

  func getCompletions(keywords: String) -> Promise<[String]> {
    if UserDefaults.standard.querySuggestions {
      return SearchManager.shared.provider.completions(keywords: keywords)
    } else {
      return Promise([String]())
    }
  }
}
