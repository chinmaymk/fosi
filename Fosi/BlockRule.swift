//
//  Rule.swift
//  Fosi
//
//  Created by Chinmay Kulkarni on 1/24/21.
//
import Foundation

struct BlockRule: Codable {
  let action: Action
  let trigger: Trigger

  enum ActionType: String, Codable {
    case block = "block"
    case blockCookies = "block-cookies"
    case cssDisplayNone = "css-display-none"
    case ignorePreviousRules = "ignore-previous-rules"
  }
  struct Action: Codable {
    let type: ActionType
    let selector: String?
  }

  struct Trigger: Codable {
    let urlFilter: String
    let ifDomain: Array<String>?
    let unlessDomain: Array<String>?

    let loadType: Array<String>?
    let resourceType: Array<String>?
    let caseSensitive: Bool?

    enum CodingKeys: String, CodingKey {
      case urlFilter = "url-filter"
      case ifDomain = "if-domain"
      case unlessDomain = "unless-domain"
      case loadType = "load-type"
      case resourceType = "resource-type"
      case caseSensitive = "url-filter-is-case-sensitive"
    }
  }

  init(type: ActionType, trigger: Trigger) {
    action = Action(type: type, selector: nil)
    self.trigger = trigger
  }

  init(action: Action, trigger: Trigger) {
    self.action = action
    self.trigger = trigger
  }

  init(type: ActionType, urlFilter: String,
       ifDomain: Array<String>? = nil, unlessDomain: Array<String>? = nil,
       selector: String? = nil) {
    action = Action(type: type, selector: selector)
    trigger = Trigger(urlFilter: urlFilter,
                      ifDomain: ifDomain?.count == 0 ? nil: ifDomain,
                      unlessDomain: unlessDomain?.count == 0 ? nil: unlessDomain,
                      loadType: nil,
                      resourceType: nil,
                      caseSensitive: nil)
  }

  init(type: ActionType, urlFilter: String,
       resourceType: Array<String>,
       loadType: Array<String>, ifDomain: Array<String>?) {
    action = Action(type: type, selector: nil)
    trigger = Trigger(urlFilter: urlFilter, ifDomain: ifDomain?.count == 0 ? nil : ifDomain,
                      unlessDomain: nil,
                      loadType: loadType.count == 0 ? nil : loadType,
                      resourceType: resourceType.count == 0 ? nil : resourceType,
                      caseSensitive: nil)
  }

  init(type: ActionType, urlFilter: String) {
    action = Action(type: type, selector: nil)
    trigger = Trigger(urlFilter: urlFilter, ifDomain: nil,
                      unlessDomain: nil, loadType: nil,
                      resourceType: nil, caseSensitive: nil)
  }

  init(type: ActionType, rule: BlockRule) {
    action = Action(type: type, selector: rule.action.selector)
    trigger = rule.trigger
  }
}
