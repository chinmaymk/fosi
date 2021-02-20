//
//  CircularProgressView.swift
//  Fosi
//
//  Created by Chinmay Kulkarni on 12/29/20.
//

import Foundation
import UIKit

class CircularProgressView: UIView {

  let progressLayer = CAShapeLayer()

  init() {
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  override func layoutSubviews() {
    constructLayer()
  }

  func constructLayer() {
    self.backgroundColor = UIColor.clear
    self.layer.cornerRadius = self.frame.size.width/2
    let circlePath = UIBezierPath(arcCenter: CGPoint(x: frame.size.width/2, y: frame.size.height/2), radius: (frame.size.width)/2.4, startAngle: CGFloat(-0.5 * .pi), endAngle: CGFloat(1.5 * .pi), clockwise: true)

    progressLayer.path = circlePath.cgPath
    progressLayer.fillColor = UIColor.clear.cgColor
    progressLayer.strokeColor = UIColor.systemGray.cgColor
    progressLayer.lineWidth = 1.5
    layer.addSublayer(progressLayer)
  }

  func setProgress(value: Float) {
    let animation = CABasicAnimation(keyPath: "strokeEnd")
    animation.duration = 1
    animation.fillMode = .forwards
    animation.isRemovedOnCompletion = false
    animation.toValue = value
    animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.linear)

    progressLayer.strokeEnd = CGFloat(value)
    progressLayer.strokeColor = UIColor.systemBlue.cgColor
    progressLayer.add(animation, forKey: "animateprogress")
  }
}

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
