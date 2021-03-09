//
//  HistoryManager.swift
//  Fosi
//
//  Created by Chinmay Kulkarni on 12/29/20.
//

import Foundation
import GRDB.Swift
import Promises.Swift

struct HistoryRecord {
  var id: Int64?
  var title: String
  var url: URL
  var domain: String
  var content: String
  var keywords: String
  var timestamp: Date
}

class HistoryManager {
  var maxRows: Int
  static let shared = HistoryManager(limit: 5)

  init(limit: Int) {
    self.maxRows = limit
  }

  func insert(record: inout HistoryRecord) -> Promise<HistoryRecord> {
    let promise = Promise<HistoryRecord>.pending()
    AppDatabase.shared.withQueue { q in
      do {
        try q.write { db in
          try record.insert(db)
          promise.fulfill(record)
        }
      } catch {
        promise.reject(error)
      }
    }
    return promise
  }

  func search(keywords: String) -> Promise<[HistoryRecord]> {
    let promise = Promise<[HistoryRecord]>.pending()
    AppDatabase.shared.withReadDb(promise: promise) { db in
      let sql = """
      SELECT historyRecord.*
      FROM historyRecord
      JOIN (
          SELECT rowid, rank
          FROM historyRecordFTS
          WHERE content MATCH ?
          ORDER BY rank
      ) AS ranktable
      ON ranktable.rowid = historyRecord.rowid
      GROUP BY url
      ORDER BY timestamp DESC
      LIMIT ?
      """
      let pattern = FTS5Pattern(matchingAllTokensIn: keywords)
      return try HistoryRecord.fetchAll(db, sql: sql, arguments: [pattern, maxRows])
    }
    return promise
  }

  func exactmatch(keywords: String) -> Promise<HistoryRecord?> {
    let promise = Promise<HistoryRecord?>.pending()
    AppDatabase.shared.withReadDb(promise: promise) { db in
      let sql = """
      SELECT historyRecord.*
      FROM historyRecord
      JOIN (
          SELECT rowid, domain
          FROM historyRecordFTS
          WHERE historyRecordFTS MATCH 'domain: \(keywords)*'
          LIMIT 1
      ) AS ranktable
      ON ranktable.rowid = historyRecord.rowid
      """
      return try HistoryRecord.fetchOne(db, sql: sql, arguments: [])
    }
    return promise
  }

  func mostLikelyWebsite() -> Promise<[HistoryRecord]?> {
    let promise = Promise<[HistoryRecord]?>.pending()
    AppDatabase.shared.withReadDb(promise: promise) { db in
      let sql = """
      SELECT historyRecord.*
      FROM historyRecord
      GROUP BY domain ORDER BY COUNT(*) DESC
      """
      return try HistoryRecord.fetchAll(db, sql: sql, arguments: [])
    }
    return promise
  }

  func delete(domain: String?) -> Promise<Bool> {
    let promise = Promise<Bool>.pending()
    AppDatabase.shared.withQueue { q in
      do {
        try q.write { db  in
          try HistoryRecord.deleteAll(db)
          promise.fulfill(true)
        }
      } catch {
        promise.reject(error)
      }
    }
    return promise
  }
}

extension HistoryRecord: Codable, FetchableRecord, MutablePersistableRecord {
  // Define database columns from CodingKeys
  enum Columns {
    static let title = Column(CodingKeys.title)
    static let url = Column(CodingKeys.url)
    static let keywords = Column(CodingKeys.keywords)
    static let domain = Column(CodingKeys.domain)
    static let timestamp = Column(CodingKeys.timestamp)
  }

  mutating func didInsert(with rowID: Int64, for column: String?) {
    id = rowID
  }
}
