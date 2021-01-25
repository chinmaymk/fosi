//
//  CompletionProviders.swift
//  Fosi
//
//  Created by Chinmay Kulkarni on 12/29/20.
//

import Foundation
import SWXMLHash
import Promises.Swift

protocol CompletionProvider {
  func getCompletions(keywords: String) -> Promise<[String]>
}

class DomainCompletions: CompletionProvider {
  let MAX_MATCHES = 5
  
  func getCompletions(keywords: String) -> Promise<[String]> {
    // if user is still typing, chances of finding a match are very low
    if keywords.count > 12 {
      return Promise([String]())
    }
    
    var buffer = [String]()
    var it = data.makeIterator()
    while buffer.count < MAX_MATCHES,
          let domain = it.next() {
      if (domain.starts(with: keywords)) {
        buffer.append(domain)
      }
    }
    return Promise(buffer)
  }
  
  static let shared = DomainCompletions()
  
  lazy var data: [String] = {
    let url = Bundle.main.url(forResource: "topdomains", withExtension: "txt")
    let source = try! String(contentsOf: url!)
    return source.components(separatedBy: "\n")
  }()
}

class GoogleCompletions: CompletionProvider {
  
  static let shared = GoogleCompletions()
  
  func getCompletions(keywords: String) -> Promise<[String]> {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "suggestqueries.google.com"
    components.path = "/complete/search"
    components.queryItems = [
      URLQueryItem(name: "q", value: keywords),
      URLQueryItem(name: "output", value: "toolbar"),
      URLQueryItem(name: "hl", value: "en")
    ]
    
    guard let url = components.url else { return Promise([String]()) }
    
    let promise = Promise<[String]>.pending()
    
    let task = URLSession.shared.dataTask(with: url) { (data, _, err) in
      guard let data = data, err == nil else { return }
      var buffer = [String]()
      
      do {
        let xml = SWXMLHash.parse(data)
        let sugeesstions = xml["toplevel"]["CompleteSuggestion"]
        for elem in sugeesstions.all {
          let suggestion: String = try elem["suggestion"].value(ofAttribute: "data")
          buffer.append(suggestion)
        }
        promise.fulfill(buffer)
      } catch {
        promise.reject(error)
      }
    }
    task.resume()
    return promise
  }
}
