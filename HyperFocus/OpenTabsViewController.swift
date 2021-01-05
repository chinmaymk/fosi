//
//  OpenTabsViewController.swift
//  HyperFocus
//
//  Created by Chinmay Kulkarni on 1/1/21.
//

import Foundation
import UIKit
import iCarousel
import WebKit

class OpenTabsViewController: UIViewController, iCarouselDataSource {
    
    let collectionView = iCarousel(frame: .zero)
    var pool: WebviewPool?
    var projected: Array<(WebviewPool.Index, WebviewPool.Item)> {
        get {
            if let pool = pool {
                return pool.sorted(by: .createdAt)
            } else {
                return []
            }
        }
    }
    var openNewTabHandler: ((WKWebView) -> Void)?
    var tabDidClose: ((WKWebView) -> Void)?
    var allTabsClosed: (() -> Void)?
    
    let heightMultiplier = CGFloat(0.6)
    let widthMultiplier = CGFloat(0.6)
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
    }
    
    @objc func closeAllTabs() {
        pool?.removeAll()
        allTabsClosed?()
        _ = projected[0]
        collectionView.reloadData()
    }
    
    @objc func dismissVC() {
        dismiss(animated: true, completion: nil)
    }
    
    @objc func dismissTab(_ sender: UISwipeGestureRecognizer) {
        let item = projected[collectionView.currentItemIndex]
        tabDidClose?(item.1.view)
        pool?.remove(at: item.0)
        // collectionView.removeItem(at: collectionView.currentItemIndex, animated: true)
        collectionView.reloadData()
    }
    
    @objc func openTab() {
        let view = projected[collectionView.currentItemIndex].1.view
        openNewTabHandler?(view)
        dismissVC()
    }
    
    func carousel(_ carousel: iCarousel, viewForItemAt index: Int, reusing view: UIView?) -> UIView {
        let img = projected[index].1.snapshot
        let w =  img.size.width * widthMultiplier
        let h = img.size.height * heightMultiplier
        let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: w, height: h))
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.image = img
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(dismissTab))
        swipe.direction = .up
        let open = UITapGestureRecognizer(target: self, action: #selector(openTab))
        
        imageView.layer.borderColor = UIColor.separator.cgColor
        imageView.layer.borderWidth = 0.5
        imageView.isOpaque = true
        imageView.layer.backgroundColor = UIColor.white.cgColor
        imageView.isUserInteractionEnabled = true
        imageView.addGestureRecognizer(swipe)
        imageView.addGestureRecognizer(open)
        
        return imageView
    }
    
    func numberOfItems(in carousel: iCarousel) -> Int {
        projected.count
    }
    
    override func viewDidLoad() {
        view.backgroundColor = .systemFill
        
        let closeAll = UIButton(type: .system)
        closeAll.setTitle("Close All", for: .normal)
        closeAll.layer.cornerRadius = 5
        closeAll.addTarget(self, action: #selector(closeAllTabs), for: .touchDown)
        
        let dismissSelf = UIButton(type: .system)
        dismissSelf.setTitle("Cancel", for: .normal)
        dismissSelf.layer.cornerRadius = 5
        dismissSelf.setTitleColor(.systemRed, for: .normal)
        dismissSelf.addTarget(self, action: #selector(dismissVC), for: .touchDown)
        
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.text = "Open Tabs"
                
        collectionView.dataSource = self
        collectionView.type = .coverFlow
        collectionView.currentItemIndex = 0
        
        collectionView.layer.cornerRadius = 10
        collectionView.clipsToBounds = true
        
        collectionView.backgroundColor = .systemBackground
        closeAll.backgroundColor = .systemBackground
        
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(dismissVC))
        swipe.direction = .down
        
        let bottomMask = UIView()
        bottomMask.backgroundColor = .systemBackground
        bottomMask.translatesAutoresizingMaskIntoConstraints = false
        collectionView.addGestureRecognizer(swipe)
        view.addSubview(collectionView)
        view.addSubview(closeAll)
        view.addSubview(bottomMask)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        closeAll.translatesAutoresizingMaskIntoConstraints = false
        dismissSelf.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        //view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            collectionView.widthAnchor.constraint(equalTo: view.widthAnchor),
            collectionView.bottomAnchor.constraint(equalTo: closeAll.topAnchor, constant: 10),
            
            collectionView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: CGFloat(heightMultiplier) + 0.12),
            
            closeAll.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            closeAll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            closeAll.heightAnchor.constraint(equalToConstant: 20),
            closeAll.widthAnchor.constraint(equalTo: view.widthAnchor),
            
            bottomMask.topAnchor.constraint(equalTo: closeAll.bottomAnchor),
            bottomMask.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomMask.leftAnchor.constraint(equalTo: view.leftAnchor),
            bottomMask.widthAnchor.constraint(equalTo: view.widthAnchor),
        ])
    }
}
