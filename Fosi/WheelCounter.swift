//
//  WheelCounter.swift
//  Fosi
//
//  Created by Chinmay Kulkarni on 1/1/21.
//
// 0 3 2 1 0 3 2 1 2
class WheelCounter<T> {
  private var index = 0
  private var labels = [T]()

  init(labels: [T], startIndex: Int = 0) {
    self.labels = labels
    self.index = startIndex
  }

  func up() -> T {
    index = (index + 1) % labels.count
    return labels[index]
  }

  func down() -> T {
    index = (index - 1) % labels.count
    if index < 0 {
      index = labels.count - 1
    }
    return labels[index]
  }
}
