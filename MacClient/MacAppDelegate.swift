//
//  MacAppDelegate.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import XCGLogger
import SwinjectStoryboard
import Swinject
import SwiftyJSON

let log = XCGLogger.defaultInstance()

@NSApplicationMain
class MacAppDelegate: NSObject, NSApplicationDelegate {
	var sessionWindowControllers = Set<MainWindowController>()
	var bookmarkWindowController: NSWindowController?
	let bookmarkManager = BookmarkManager()
	dynamic var dockerManager: DockerManager?

	private dynamic var _currentProgress: NSProgress?
	private let _statusQueue = dispatch_queue_create("io.rc2.statusQueue", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0))

	func applicationWillFinishLaunching(notification: NSNotification) {
		dockerManager = DockerManager()
		dockerManager?.isDockerRunning() { isRunning in
			log.info("docker is running \(isRunning ? "yes" : "no")")
		}
		log.setup(.Debug, showLogIdentifier: false, showFunctionName: true, showThreadName: false, showLogLevel: true, showFileNames: true, showLineNumbers: true, showDate: false, writeToFile: nil, fileLogLevel: .Debug)
		let cdUrl = NSBundle.mainBundle().URLForResource("CommonDefaults", withExtension: "plist")
		NSUserDefaults.standardUserDefaults().registerDefaults(NSDictionary(contentsOfURL: cdUrl!)! as! [String : AnyObject])
		NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(MacAppDelegate.windowWillClose), name: NSWindowWillCloseNotification, object: nil)
	}

	func applicationDidFinishLaunching(aNotification: NSNotification) {
		//skip showing bookmarks when running unit tests
		guard NSProcessInfo.processInfo().environment["XCTestConfigurationFilePath"] == nil else { return }
		showBookmarkWindow(nil)
	#if HOCKEYAPP_ENABLED
		log.info("key is \(kHockeyAppIdentifier)")
		BITHockeyManager.sharedHockeyManager().configureWithIdentifier(kHockeyAppIdentifier)
		//BITHockeyManager.sharedHockeyManager().debugLogEnabled = true
		// Do some additional configuration if needed here
		BITHockeyManager.sharedHockeyManager().startManager()
	#endif
		restoreSessions()
	}

	func applicationWillTerminate(aNotification: NSNotification) {
		NSNotificationCenter.defaultCenter().removeObserver(self, name: NSWindowWillCloseNotification, object: nil)
		let defaults = NSUserDefaults.standardUserDefaults()
		//save info to restore open sessions
		var reopen = [Bookmark]()
		for controller in sessionWindowControllers {
			if let session = controller.session, let rest = session.restServer, let proj = session.workspace.project {
				let bmark = Bookmark(name: "irrelevant", server: rest.host, project: proj.name, workspace: session.workspace.name)
				reopen.append(bmark)
			}
		}
		do {
			let bmarks = try JSON(reopen.map() { try $0.serialize() })
			defaults.setObject(bmarks.rawString(), forKey: PrefKeys.OpenSessions)
		} catch let err {
			log.error("failed to serialize bookmarks: \(err)")
		}
	}

	func applicationShouldOpenUntitledFile(sender: NSApplication) -> Bool {
		return NSApp.modalWindow == nil
	}
	
	func applicationOpenUntitledFile(sender: NSApplication) -> Bool {
		bookmarkWindowController?.window?.makeKeyAndOrderFront(self)
		return true
	}
	
	override func validateMenuItem(menuItem: NSMenuItem) -> Bool {
		switch(menuItem.action) {
			case #selector(MacAppDelegate.showBookmarkWindow(_:)):
				return NSApp.mainWindow != bookmarkWindowController?.window
			default:
				return false
		}
	}
	
	func restoreSessions() {
		let defaults = NSUserDefaults.standardUserDefaults()
		//load them, or create default ones
		var bookmarks = [Bookmark]()
		if let bmstr = defaults.stringForKey(PrefKeys.OpenSessions) {
			for aJsonObj in JSON.parse(bmstr).arrayValue {
				bookmarks.append(Bookmark(json: aJsonObj)!)
			}
		}
		guard let bmarkController = bookmarkWindowController?.contentViewController as? BookmarkViewController else
		{
			log.error("failed to get bookmarkViewController to restore sessions")
			return
		}
		//TODO: show progress dialog
		for bmark in bookmarks {
			bmarkController.openSession(withBookmark: bmark, password: nil)
		}
	}
	
	func windowForAppStatus(session:Session?) -> NSWindow {
		return windowControllerForSession(session!)!.window!
	}
	
	@IBAction func showBookmarkWindow(sender:AnyObject?) {
		if nil == bookmarkWindowController {
			let container = Container()
			container.registerForStoryboard(NSWindowController.self, name: "bmarkWindow") { r,c in
				log.info("wc registered")
			}
			container.registerForStoryboard(BookmarkViewController.self) { r, c in
				c.bookmarkManager = self.bookmarkManager
			}
			container.registerForStoryboard(AddBookmarkViewController.self) { r, c in
				c.bookmarkManager = self.bookmarkManager
			}
			container.registerForStoryboard(SelectServerViewController.self) { r, c in
				c.bookmarkManager = self.bookmarkManager
//				c.docker = self.dockerManager
			}

			let sboard = SwinjectStoryboard.create(name: "BookmarkManager", bundle: nil, container: container)
			bookmarkWindowController = sboard.instantiateControllerWithIdentifier("bookmarkWindow") as? NSWindowController
			let bvc = bookmarkWindowController!.contentViewController as! BookmarkViewController
			bvc.openSessionCallback = openSession
		}
		bookmarkWindowController?.window?.makeKeyAndOrderFront(self)
	}
	
	func openSession(restServer:RestServer) {
		let appStatus = MacAppStatus(windowAccessor: windowForAppStatus)
		let wc = MainWindowController.createFromNib()
		sessionWindowControllers.insert(wc)
		
		let container = Container()
		container.registerForStoryboard(RootViewController.self) { r, c in
			c.appStatus = appStatus
		}
		container.registerForStoryboard(SidebarFileController.self) { r, c in
			c.appStatus = appStatus
		}
		container.registerForStoryboard(AbstractSessionViewController.self) { r, c in
			c.appStatus = appStatus
		}

		let sboard = SwinjectStoryboard.create(name: "MainController", bundle: nil, container: container)
		wc.window?.makeKeyAndOrderFront(self)
		//a bug in storyboard loading is causing DI to fail for the rootController when loaded via the window
		let root = sboard.instantiateControllerWithIdentifier("rootController") as? RootViewController
		wc.contentViewController = root
		wc.appStatus = appStatus
		restServer.appStatus = appStatus
		wc.session = restServer.session
		wc.setupChildren(restServer)
	}
	
	func windowWillClose(note:NSNotification) {
		//if no windows will be visible, acitvate/show bookmark window
		if let sessionWC = (note.object as! NSWindow).windowController as? MainWindowController {
			sessionWindowControllers.remove(sessionWC)
			if sessionWindowControllers.count < 1 {
				performSelector(#selector(MacAppDelegate.showBookmarkWindow), withObject: nil, afterDelay: 0.2)
			}
		}
	}
	
	func windowControllerForSession(session:Session) -> MainWindowController? {
		for wc in sessionWindowControllers {
			if wc.session == session { return wc }
		}
		return nil
	}
}
