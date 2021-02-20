//
//  HyperFocusTests.swift
//  HyperFocusTests
//
//  Created by Chinmay Kulkarni on 12/18/20.
//
//

import XCTest
@testable import Fosi

class FosiTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testWheelCounter() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
      let counter = WheelCounter<Int>(labels: [0, 1, 2])
      XCTAssert(counter.up() == 1)
      XCTAssert(counter.up() == 2)
      XCTAssert(counter.down() == 1)
      XCTAssert(counter.down() == 0)
      XCTAssert(counter.down() == 2)
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
