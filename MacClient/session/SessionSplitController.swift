//
//  SessionSplitController
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ReactiveSwift

let LastSelectedSessionTabIndex = "LastSelectedSessionTabIndex"
let SidebarFixedWidth: CGFloat = 209

enum SidebarTab: Int {
	case files = 0, variables, helpTopics
}

fileprivate extension NSUserInterfaceItemIdentifier {
	static let sidebarController = NSUserInterfaceItemIdentifier(rawValue: "sidebarController")
}

class SessionSplitController: NSSplitViewController, ToolbarItemHandler {
	// MARK: properties
	var sidebarSegmentControl: NSSegmentedControl?
	var outputSegmentControl: NSSegmentedControl?
	private let (lifetime, token) = Lifetime.make()

	// MARK: methods
	override func awakeFromNib() {
		super.awakeFromNib()
		let splitItem = sidebarSplitItem()
		splitItem.minimumThickness = SidebarFixedWidth
		splitItem.maximumThickness = SidebarFixedWidth
		splitItem.isSpringLoaded = false
	}
	
	func handlesToolbarItem(_ item: NSToolbarItem) -> Bool {
		if item.itemIdentifier.rawValue == "leftView" {
			sidebarSegmentControl = item.view as! NSSegmentedControl? // swiftlint:disable:this force_cast
			sidebarSegmentControl?.target = self
			sidebarSegmentControl?.action = #selector(sidebarSwitcherClicked(_:))
			let sidebar = sidebarTabController()
			let lastSelection = UserDefaults.standard.integer(forKey: LastSelectedSessionTabIndex)
			sidebarSegmentControl?.selectedSegment = lastSelection
			sidebar.selectedTabViewItemIndex = lastSelection
			return true
		} else if item.itemIdentifier.rawValue == "rightView" {
			outputSegmentControl = item.view as! NSSegmentedControl? // swiftlint:disable:this force_cast
			outputSegmentControl?.target = self
			outputSegmentControl?.action = #selector(outputSwitcherClicked(_:))
			outputSegmentControl?.selectedSegment = 0
			outputTabController().selectedOutputTab.value = .console
			return true
		}
		return false
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		outputTabController().selectedOutputTab.signal.take(during: lifetime).observeValues { value in
			self.outputSegmentControl?.selectSegment(withTag: value.rawValue)
		}
	}
	
	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		guard let action = menuItem.action else { return super.validateMenuItem(menuItem) }
		switch action {
		case #selector(switchSidebarTab(_:)):
			if sidebarSplitItem().isCollapsed {
				menuItem.state = .off
			} else {
				menuItem.state = menuItem.tag == sidebarSegmentControl?.selectedSegment ? .on : .off
			}
			return true
		case #selector(switchSidebarTab(_:)):
			menuItem.state = menuItem.tag == outputSegmentControl?.selectedSegment ? .on : .off
			return true
		case #selector(toggleLeftView(_:)):
			menuItem.title = sidebarSplitItem().isCollapsed ? "Show Sidebar" : "Hide Sidebar"
			return true
		default:
			return false
//			return super.validateMenuItem(menuItem)
		}
	}
	
	@objc func outputSwitcherClicked(_ sender: NSSegmentedControl) {
		guard let tab = OutputTab(rawValue: sender.selectedSegment) else { fatalError() }
		outputTabController().selectedOutputTab.value = tab
	}

	func visibleSidebarTab() -> SidebarTab? {
		guard !sidebarSplitItem().isCollapsed else { return nil }
		return SidebarTab(rawValue: sidebarTabController().selectedTabViewItemIndex)
	}
	
	@IBAction func switchOutputTab(_ sender: NSMenuItem?) {
		guard let tab = OutputTab(rawValue: sender?.tag ?? -1) else { fatalError() }
		outputTabController().selectedOutputTab.value = tab
		outputSegmentControl?.selectSegment(withTag: tab.rawValue)
	}
	
	//action for sidebar segmented control
	@objc func sidebarSwitcherClicked(_ sender: NSSegmentedControl) {
		guard let tab = SidebarTab(rawValue: sender.selectedSegment) else { fatalError() }
		switchSidebarTo(tab: tab)
	}
	
	//action for menu items
	@IBAction func switchSidebarTab(_ sender: NSMenuItem?) {
		guard let tab = SidebarTab(rawValue: sender?.tag ?? -1) else { fatalError() }
		switchSidebarTo(tab: tab)
	}
	
	@IBAction func toggleLeftView(_ sender: Any?) {
		let splitItem = sidebarSplitItem()
		splitItem.isCollapsed = !splitItem.isCollapsed
		if let sidebar = sidebarSegmentControl {
			sidebar.animator().setSelected(!splitItem.isCollapsed, forSegment: sidebar.selectedSegment)
		}
	}
	
	func switchSidebarTo(tab: SidebarTab) {
		let index = tab.rawValue
		let sidebar = sidebarTabController()
		let splitItem = sidebarSplitItem()
//		let index = (segmentControl?.selectedSegment)!
		if index == sidebar.selectedTabViewItemIndex {
			//same as currently selected. toggle visibility
			sidebarSegmentControl?.animator().setSelected(splitItem.isCollapsed, forSegment: index)
			//don't use toggle because it grows the window on the first collapse, or takes all space from view2
//			toggleSidebar(nil)
			splitItem.isCollapsed = !splitItem.isCollapsed
		} else {
			if splitItem.isCollapsed {
				splitItem.isCollapsed = false
//				toggleSidebar(self)
			}
			sidebarSegmentControl?.animator().setSelected(true, forSegment: index)
			sidebar.selectedTabViewItemIndex = index
			UserDefaults.standard.set(index, forKey: LastSelectedSessionTabIndex)
		}
	}

	func sidebarSplitItem() -> NSSplitViewItem {
		return self.splitViewItems.first(where: { $0.viewController.identifier == .sidebarController })!
	}
	
	func sidebarTabController() -> NSTabViewController {
		// swiftlint:disable:next force_cast
		let scontroller = self.childViewControllers.first(where: { $0.identifier == .sidebarController }) as! SidebarController
		let _ = scontroller.view
		return scontroller.tabController
	}
	
	func outputTabController() -> OutputTabController {
		// swiftlint:disable:next force_cast
		return self.childViewControllers.first(where: { $0.identifier?.rawValue == "outputTabController" }) as! OutputTabController
	}
	
	override func splitView(_ splitView: NSSplitView, shouldHideDividerAt dividerIndex: Int) -> Bool
	{
		return false
	}
}

// MARK: -
/// subclass that resizes views 2/3 on double click on splitter
class SessionSplitView: NSSplitView {
	override func mouseDown(with event: NSEvent) {
		guard event.type == .leftMouseDown, event.clickCount == 2 else {
			super.mouseDown(with: event)
			return
		}
		let frame2 = arrangedSubviews[1].frame
		let frame3 = arrangedSubviews[2].frame
		let dividerRect = NSRect(x: frame2.maxX - 1.0, y: frame3.origin.y, width: dividerThickness + 1.0, height: frame3.height)
		let position = convert(event.locationInWindow, from: nil)
		guard dividerRect.contains(position) else {
			super.mouseDown(with: event)
			return
		}
		let contentWidth = frame3.maxX - frame2.origin.x
		let dest = frame2.origin.x + (contentWidth / 2.0)
		setPosition(dest, ofDividerAt: 1)
	}
}
