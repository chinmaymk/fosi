//
//  SearchEngines.swift
//  Fosi
//
//  Created by Chinmay Kulkarni on 2/14/21.
//

import Foundation
import Promises
import SWXMLHash

protocol SearchProvider {
  func searchUrl(keywords: String) -> URL
  func completions(keywords: String) -> Promise<[String]>
}

extension UserDefaults {
  @objc dynamic var searchEngine: String? {
    get { return string(forKey: AppSettingKeys.searchEngine) }
    set { set(newValue, forKey: AppSettingKeys.searchEngine) }
  }
}

class SearchManager {
  static let shared = SearchManager()
  var provider: SearchProvider {
    if UserDefaults.standard.searchEngine == "DuckDuckGo" {
      return ddg
    } else {
      return google
    }
  }
  private let ddg = DuckDuckGoSearch()
  private let google = GoogleSearch()
}

class DuckDuckGoSearch: SearchProvider {
  func searchUrl(keywords: String) -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "duckduckgo.com"
    components.path = "/"
    components.queryItems = [
      URLQueryItem(name: "q", value: keywords),
    ]
    return components.url!
  }

  struct DDGAC: Decodable {
    let phrase: String
  }
  func completions(keywords: String) -> Promise<[String]> {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "duckduckgo.com"
    components.path = "/ac"
    components.queryItems = [
      URLQueryItem(name: "q", value: keywords)
    ]
    let promise = Promise<[String]>.pending()
    URLSession.shared.dataTask(with: components.url!) { data, _, err in
      guard let data = data, err == nil else { return }
      var buffer = [String]()
      let values = try? JSONDecoder().decode([DDGAC].self, from: data)
      values?.forEach { completion in
        buffer.append(completion.phrase)
      }
      promise.fulfill(buffer)
    }.resume()
    return promise
  }
}

class GoogleSearch: SearchProvider {
  func searchUrl(keywords: String) -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "google.com"
    components.path = "/search"
    components.queryItems = [
      URLQueryItem(name: "q", value: keywords),
    ]
    return components.url!
  }

  func completions(keywords: String) -> Promise<[String]> {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "suggestqueries.google.com"
    components.path = "/complete/search"
    components.queryItems = [
      URLQueryItem(name: "q", value: keywords),
      URLQueryItem(name: "output", value: "toolbar"),
      URLQueryItem(name: "hl", value: "en")
    ]
    let promise = Promise<[String]>.pending()
    URLSession.shared.dataTask(with: components.url!) { data, _, err in
      guard let data = data, err == nil else { return }
      var buffer = [String]()
      let xml = SWXMLHash.parse(data)
      let sugeesstions = xml["toplevel"]["CompleteSuggestion"]
      sugeesstions.all.forEach { elem in
        guard let suggestion: String = try? elem["suggestion"].value(ofAttribute: "data")
        else { return }
        buffer.append(suggestion)
      }
      promise.fulfill(buffer)
    }.resume()
    return promise
  }
}
