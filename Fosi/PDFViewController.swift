//
//  PDFViewController.swift
//  Fosi
//
//  Created by Chinmay Kulkarni on 12/20/20.
//

import Foundation
import PDFKit
import CoreGraphics

class DarkPage: PDFPage {

  override func draw(with box: PDFDisplayBox, to context: CGContext) {
    UIGraphicsPushContext(context)
    context.saveGState()

    context.setFillColor(UIColor(red: 0.09, green: 0.10, blue: 0.11, alpha: 1.00).cgColor)
    context.setBlendMode(.destinationAtop)
    context.drawPDFPage(pageRef!)

    context.setBlendMode(.exclusion)
    context.drawPDFPage(pageRef!)

    context.restoreGState()
    UIGraphicsPopContext()
  }
}

class PDFViewController : UIViewController, PDFDocumentDelegate, PDFViewDelegate {
  let pdfView = PDFView()

  var url: URL?

  let contextualMenus = [
    UIMenuItem(title: "In Page", action: #selector(findInPageFromSelection))
  ]

  func setURL(url: URL) {
    self.url = url
  }

  // https://stackoverflow.com/a/48927415
  @objc func findInPageFromSelection() {
    if let text = pdfView.currentSelection?.string {
      var display: PDFSelection?
      if let selections = pdfView.document?.findString(text, withOptions: [.caseInsensitive]) {
        for s in selections {
          s.color = .systemYellow
          if display == nil {
            display = s
          } else {
            display?.add(s)
          }
        }
        pdfView.setCurrentSelection(display, animate: true)
      }
    }
  }

  func classForPage() -> AnyClass {
    if self.traitCollection.userInterfaceStyle == .dark {
      return DarkPage.self
    } else {
      return PDFPage.self
    }
  }

  let thumbnailView = PDFThumbnailView()
  private func setupThumbnailView() {
    thumbnailView.pdfView = pdfView
    thumbnailView.backgroundColor = UIColor(displayP3Red: 179/255, green: 179/255, blue: 179/255, alpha: 0.5)
    thumbnailView.layoutMode = .horizontal
    thumbnailView.thumbnailSize = CGSize(width: 80, height: 100)
    thumbnailView.contentInset = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
    view.addSubview(thumbnailView)
  }

  override func viewDidLoad() {
    self.pdfView.displayMode = .singlePageContinuous
    self.pdfView.autoScales = true
    self.pdfView.displayDirection = .horizontal
    self.pdfView.autoresizesSubviews = true

    let doc = PDFDocument(url: self.url!)
    doc?.delegate = self
    pdfView.document = doc
    pdfView.delegate = self
    pdfView.usePageViewController(true)
    pdfView.enableDataDetectors = true
    pdfView.translatesAutoresizingMaskIntoConstraints = false

    UIMenuController.shared.menuItems = contextualMenus
    
    view.addSubview(pdfView)

    NSLayoutConstraint.activate([
      pdfView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
    ])
  }
}
