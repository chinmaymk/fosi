//
//  HFDatabase.swift
//  HyperFocus
//
//  Created by Chinmay Kulkarni on 12/30/20.
//

import Foundation
import GRDB.Swift
import Promises.Swift

class HFDatabase {
  static var shared: HFDatabase!
  
  private let dbQueue: DatabaseQueue
  
  init(_ dbQueue: DatabaseQueue) throws {
    self.dbQueue = dbQueue
    try migrator.migrate(dbQueue)
  }
  
  func withQueue(handler: (DatabaseQueue) -> Void) {
    handler(self.dbQueue)
  }
  
  func withWriteDb<T>(promise: Promise<T>, handler: (Database) throws -> T) {
    self.withQueue { q in
      do {
        try q.write { db in
          let records = try handler(db)
          promise.fulfill(records)
        }
      }
      catch {
        promise.reject(error)
      }
    }
  }
  
  func withReadDb<T>(promise: Promise<T>, handler: (Database) throws -> T) {
    self.withQueue { q in
      do {
        try q.read { db in
          let records = try handler(db)
          promise.fulfill(records)
        }
      } catch {
        promise.reject(error)
      }
    }
  }
  
  private var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()
    
    #if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
    #endif
    
    migrator.registerMigration("history related views") { db in
      try db.create(table: "historyRecord") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("title", .text)
        t.column("url", .text)
        t.column("domain", .text)
        t.column("keywords", .text)
        t.column("timestamp", .datetime)
      }
      
      try db.create(virtualTable: "historyRecordFTS", using: FTS5()) { t in
        t.tokenizer = .porter()
        t.prefixes = [2]
        t.synchronize(withTable: "historyRecord")
        t.column("title")
        t.column("url")
        t.column("domain")
        t.column("keywords")
      }
    }
    
    return migrator
  }
}
