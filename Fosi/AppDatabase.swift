//
//  AppDatabase.swift
//  Fosi
//
//  Created by Chinmay Kulkarni on 12/30/20.
//

import Foundation
import GRDB.Swift
import Promises.Swift

class AppDatabase {
  static func databaseUrl() -> URL {
    return try! FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ).appendingPathComponent("fosi.sqlite")
  }

  static func setup() throws {
    let databaseURL = databaseUrl()
    let dbQueue = try DatabaseQueue(path: databaseURL.path)
    let database = try AppDatabase(dbQueue)
    AppDatabase.shared = database
  }

  static var shared: AppDatabase!
  
  private var dbQueue: DatabaseQueue
  
  init(_ dbQueue: DatabaseQueue) throws {
    self.dbQueue = dbQueue
    try migrator.migrate(dbQueue)
  }

  func withQueue(handler: (DatabaseQueue) -> Void) {
    handler(self.dbQueue)
  }

  func withWriteDb<T>(promise: Promise<T>,
                      handler: @escaping (Database) throws -> T) {
    DispatchQueue.global(qos: .utility).async {
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
  }

  func withDeleteDb<T>(promise: Promise<T>, handler: (Database) throws -> T) {
    self.withQueue { q in
      do {
        try q.inDatabase { db in
          let records = try handler(db)
          promise.fulfill(records)
        }
      }
      catch {
        promise.reject(error)
      }
    }
    // close the connection, so vacuum actually shrinks size
    if let q = try? DatabaseQueue(path: AppDatabase.databaseUrl().path) {
      try? self.dbQueue.vacuum()
      self.dbQueue = q
    }
  }

  func withReadDb<T>(promise: Promise<T>,
                     handler: @escaping (Database) throws -> T) {
    DispatchQueue.global(qos: .userInteractive).async {
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
  }

  func clearCache() {
    let url = try! FileManager.default.url(
      for: .cachesDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: false
    )
    let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path)
    let urls = contents?.filter {
      $0.contains("fosi-export")
    }.map {
      URL(string:"\(url.appendingPathComponent("\($0)"))")!
    }
    urls?.forEach {
      debugPrint($0)
      try? FileManager.default.removeItem(at: $0)
    }
  }

  func backup() -> URL {
    clearCache()
    let dateFormatterPrint = DateFormatter()
    dateFormatterPrint.dateFormat = "dd-MMM-yyyy"
    let date = dateFormatterPrint.string(from: Date())
    let exportPath = try! FileManager.default.url(
      for: .cachesDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ).appendingPathComponent("fosi-export-\(date).sqlite")
    if let backupQueue = try? DatabaseQueue(path: exportPath.path) {
      try? self.dbQueue.backup(to: backupQueue)
      try? backupQueue.vacuum()
    }
    return exportPath
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
        t.column("content", .text)
        t.column("timestamp", .datetime)
      }
      
      try db.create(virtualTable: "historyRecordFTS", using: FTS5()) { t in
        t.tokenizer = .porter()
        t.prefixes = [2]
        t.synchronize(withTable: "historyRecord")
        t.column("title")
        t.column("url")
        t.column("content")
        t.column("domain")
        t.column("keywords")
      }
    }
    
    return migrator
  }
}
