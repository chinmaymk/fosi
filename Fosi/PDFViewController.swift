//
//  PDFViewController.swift
//  Fosi
//
//  Created by Chinmay Kulkarni on 12/20/20.
//

import Foundation
import PDFKit
import CoreGraphics

class PDFViewController : UIViewController,
                          PDFDocumentDelegate,
                          PDFViewDelegate {
  let pdfView = PDFView()
  let thumbnailView = PDFThumbnailView()
  var url: URL?
  let contextualMenus = [
    UIMenuItem(title: "Find In Page", action: #selector(findInPageFromSelection))
  ]

  override func viewDidLoad() {
    pdfView.displayMode = .singlePageContinuous
    pdfView.autoScales = true
    pdfView.displayDirection = .horizontal
    pdfView.autoresizesSubviews = true
    pdfView.usePageViewController(true)
    pdfView.enableDataDetectors = true
    pdfView.translatesAutoresizingMaskIntoConstraints = false
    pdfView.delegate = self

    let doc = PDFDocument(url: url!)
    doc?.delegate = self
    pdfView.document = doc

    UIMenuController.shared.menuItems = contextualMenus

    view.addSubview(pdfView)

    NSLayoutConstraint.activate([
      pdfView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
    ])
  }

  // https://stackoverflow.com/a/48927415
  @objc func findInPageFromSelection() {
    guard let text = pdfView.currentSelection?.string,
          let selections = pdfView.document?.findString(
            text, withOptions: [.caseInsensitive]
          ) else { return }

    var display: PDFSelection?
    selections.forEach { s in
      s.color = .systemYellow
      if display == nil {
        display = s
      } else {
        display?.add(s)
      }
    }
    pdfView.setCurrentSelection(display, animate: true)
  }

  func classForPage() -> AnyClass {
    if self.traitCollection.userInterfaceStyle == .dark {
      return DarkPage.self
    } else {
      return PDFPage.self
    }
  }
}

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

