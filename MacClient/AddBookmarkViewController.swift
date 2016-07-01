//
//  AddBookmarkViewController.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

class AddBookmarkViewController: NSViewController {
	@IBOutlet var continueButton:NSButton?
	@IBOutlet var containerView: NSView?
	var tabViewController:NSTabViewController?
	var selectServerController: SelectServerViewController?
	var projectManagerController: ProjectManagerViewController?
	var bookmarkManager:BookmarkManager?
	
	dynamic var isBusy:Bool = false
	dynamic var canContinue:Bool = false
	
	override func viewDidLoad() {
		super.viewDidLoad()
		tabViewController = self.storyboard?.instantiateControllerWithIdentifier("bookmarkTabController") as? NSTabViewController
		addChildViewController(tabViewController!)
		containerView?.addSubview(tabViewController!.view)
		tabViewController?.view.topAnchor.constraintEqualToAnchor(containerView?.topAnchor)
		tabViewController?.view.bottomAnchor.constraintEqualToAnchor(containerView!.bottomAnchor)
		tabViewController?.view.leftAnchor.constraintEqualToAnchor(containerView!.leftAnchor)
		tabViewController?.view.rightAnchor.constraintEqualToAnchor(containerView!.rightAnchor)
		selectServerController = firstChildViewController(self)
		projectManagerController = firstChildViewController(self)
	}
	
	override func viewDidAppear() {
		super.viewDidAppear()
		self.view.window?.preventsApplicationTerminationWhenModal = false
		selectServerController!.addObserver(self, forKeyPath: "canContinue", options: [.Initial], context: nil)
		projectManagerController!.addObserver(self, forKeyPath: "canContinue", options: [], context: nil)
	}

	override func viewDidDisappear() {
		super.viewDidDisappear()
		selectServerController!.removeObserver(self, forKeyPath: "canContinue")
		projectManagerController!.removeObserver(self, forKeyPath: "canContinue")
	}

	func displayError(error:NSError) {
		log.error("got error: \(error)")
	}
	
	func switchToProjectManager(serverInfo:SelectServerResponse) {
		tabViewController?.selectedTabViewItemIndex = 1
		projectManagerController!.host = serverInfo.server
		projectManagerController!.loginSession = serverInfo.loginSession
	}
	
	@IBAction func continueAction(sender:AnyObject?) {
		if selectServerController == tabViewController?.currentTabItemViewController {
			selectServerController!.continueAction() { (value, error) in
				guard error == nil else {
					self.displayError(error!)
					return
				}
				let serverResponse = value as! SelectServerResponse
				self.switchToProjectManager(serverResponse)
			}
		}
	}
	
	@IBAction func cancelAction(sender:AnyObject?) {
		self.presentingViewController?.dismissViewController(self)
	}
	
	override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>)
	{
		if keyPath == "canContinue" {
			//if object is the current view controller, adjust canContinue to its canContinue value
			if let embedded = object as? EmbeddedDialogController, let controller = object as? NSViewController where controller == tabViewController?.currentTabItemViewController
			{
				canContinue = embedded.canContinue
			}
		} else {
			super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
		}
	}
}
