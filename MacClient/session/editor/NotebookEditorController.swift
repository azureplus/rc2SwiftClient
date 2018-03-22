//
//  NotebookEditorController.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import Networking
import SyntaxParsing
import MJLLogger

private enum AddChunkType: Int {
	case code = 0
	case mdown
	case equation
}

class NotebookEditorController: AbstractEditorController {
	// MARK: - constants
	let viewItemId = NSUserInterfaceItemIdentifier(rawValue: "NotebookViewItem")
	let equationItemId = NSUserInterfaceItemIdentifier(rawValue: "EquationViewItem")
	let markdownItemId = NSUserInterfaceItemIdentifier(rawValue: "MarkdownViewItem")
	// The highlighted line where the dropped item will go:
	let dropIndicatorId = NSUserInterfaceItemIdentifier(rawValue: "DropIndicator")
	// Holds dragged item for dropping:
	let notebookItemPasteboardType = NSPasteboard.PasteboardType(rawValue: "io.rc2.client.notebook.entry")

	// MARK: - properties
	@IBOutlet weak var notebookView: NSCollectionView!
	@IBOutlet var addChunkPopupMenu: NSMenu!

	var rmdDocument: RmdDocument?
	var dataArray: [NotebookItemData] = []	// holds data for all items
	var dragIndices: Set<IndexPath>?	// items being dragged

	private var parser: SyntaxParser?
	private let storage = NSTextStorage()

	// MARK: - standard
	override func viewDidLoad() {
		super.viewDidLoad()
		// Set up CollectionView:
		notebookView.registerForDraggedTypes([notebookItemPasteboardType])
		notebookView.setDraggingSourceOperationMask(.move, forLocal: true)
		notebookView.register(NotebookViewItem.self, forItemWithIdentifier: viewItemId)
		notebookView.register(EquationViewItem.self, forItemWithIdentifier: equationItemId)
		notebookView.register(MarkdownViewItem.self, forItemWithIdentifier: markdownItemId)
		notebookView.register(NotebookDropIndicator.self, forSupplementaryViewOfKind: .interItemGapIndicator, withIdentifier: dropIndicatorId)
		// Set some CollectionView layout constrains:
		guard let layout = notebookView.collectionViewLayout as? NSCollectionViewFlowLayout else {
			fatalError() } // make sure we have a layout object
		layout.sectionInset = NSEdgeInsets(top: 20, left: 8, bottom: 20, right: 8)
		layout.minimumLineSpacing = 20.0
		layout.minimumInteritemSpacing = 14.0
	}

	// Called initially and when window is resized:
	override func viewWillLayout() {
		// Make sure things are laid out again after all our manual changes:
		notebookView.collectionViewLayout?.invalidateLayout()
		super.viewWillLayout()
	}

	// MARK: - editor
	override func loaded(document: EditorDocument, content: String) {
		self.rmdDocument = try! RmdDocument(contents: content) { (topic) in
			return HelpController.shared.hasTopic(topic)
		}
		storage.replaceCharacters(in: storage.string.fullNSRange, with: content)
		dataArray = self.rmdDocument!.chunks.map { NotebookItemData(chunk: $0, result: "") }
		notebookView.reloadData()
		notebookView.collectionViewLayout?.invalidateLayout()
	}
	
	override func documentWillSave(_ notification: Notification) {
		// need to convert dataArray back to single source
	}
	
	// MARK: actions
	
	@IBAction func addChunk(_ sender: Any?) {
		guard let menuItem = sender as? NSMenuItem, let type = AddChunkType(rawValue: menuItem.tag), let previousChunk = menuItem.representedObject as? NotebookViewItem
			else { Log.warn("addChunk called from non-menu item or with incorrect tag", .app); return }
		switch type {
		case .code:
			rmdDocument?.insertCodeChunk(initalContents: "# R code", at: dataArray.index(of: previousChunk.data!)! + 1)
		case .mdown:
			rmdDocument?.insertTextChunk(initalContents: "# R code", at: dataArray.index(of: previousChunk.data!)! + 1)
		case .equation:
			rmdDocument?.insertEquationChunk(initalContents: "# R code", at: dataArray.index(of: previousChunk.data!)! + 1)
		}
		notebookView.reloadData()
	}
}

extension NotebookEditorController: NSMenuDelegate {
	func menuDidClose(_ menu: NSMenu) {
		if menu == addChunkPopupMenu { // clear rep objects which are all set to the NotebookViewItem to add after
			// not supposed to modify menu during this call. perform in a little bit. probably could just do next time through event loop. need action to complete first
			DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) {
				self.addChunkPopupMenu.items.forEach { $0.representedObject = nil }
			}
		}
	}
}

// MARK: - NotebookViewItemDelegate
extension NotebookEditorController: NotebookViewItemDelegate {
	func addChunk(after: NotebookViewItem, sender: NSButton?) {
		guard let button = sender else { fatalError("no button supplied for adding chunk") }
		addChunkPopupMenu.items.forEach { $0.representedObject = after }
		addChunkPopupMenu.popUp(positioning: nil, at: CGPoint(x: 0, y: button.bounds.maxY), in: button)
	}
}

// MARK: - NSCollectionViewDataSource
extension NotebookEditorController: NSCollectionViewDataSource {
	func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
		return dataArray.count
	}
	
	// Inits views for each item given its indexPath:
	func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem
	{
		let itemData = dataArray[indexPath.item]
		var itemId = viewItemId
		if itemData.chunk is Equation {
			itemId = equationItemId
		} else if itemData.chunk is TextChunk {
			itemId = markdownItemId
		}
		guard let view = collectionView.makeItem(withIdentifier: itemId, for: indexPath) as? NotebookViewItem else { fatalError() }
		view.context = context
		view.data = itemData
		view.delegate = self
		return view
	}
	
	// Inits the horizontal line used to highlight where the drop will go:
	func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath) -> NSView
	{
		if kind == .interItemGapIndicator {
			return collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: dropIndicatorId, for: indexPath)
		}
		// All other supplementary views go here (like footers), which are currently none:
		return collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: NSUserInterfaceItemIdentifier(rawValue: ""), for: indexPath)
	}
}

// MARK: - NSCollectionViewDelegate

extension NotebookEditorController: NSCollectionViewDelegateFlowLayout {
	
	// Returns the size of each item:
	func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize
	{
		let dataItem = dataArray[indexPath.item]
		let sz = NSSize(width: collectionView.visibleWidth, height: dataItem.height)
		Log.debug("sz for \(indexPath.item) is \(sz)", .app)
		return sz
	}
	
	// Places the data for the drag operation on the pasteboard:
	func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
		return true // when front matter is displayed, will need to return false for it
	}
	
	// Provides the pasteboard writer for the item at the specified index:
	func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt index: Int) -> NSPasteboardWriting? {
		let pbitem = NSPasteboardItem()
		pbitem.setString("\(index)", forType: notebookItemPasteboardType)
		return pbitem
	}
	
	// Notifies your delegate that a drag session is about to begin:
	func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
		dragIndices = indexPaths // get the dragIndices
	}
	
	// Notifies your delegate that a drag session ended:
	func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
		dragIndices = nil		// reset dragIndices
	}
	
	// Returns what type of drag operation is allowed:
	func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
		guard let _ = dragIndices else { return [] } // make sure we have indices being dragged
		// Turn any drop on an item to a drop before since none are containers:
		if proposedDropOperation.pointee == .on {
			proposedDropOperation.pointee = .before }
		return .move
	}
	
	// Performs the drag (move) opperation, both updating our data and animating the move:
	func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
		for fromIndexPath in dragIndices! {
			let fromIndex = fromIndexPath.item
			var toIndex = indexPath.item
			if toIndex > fromIndex { toIndex -= 1 }
			Log.debug("moving \(fromIndex) to \(toIndex)", .app)
			let itemData = dataArray[fromIndex]
			dataArray.remove(at: fromIndex)	// must be done first
			dataArray.insert(itemData, at: toIndex)
			collectionView.animator().moveItem(at: fromIndexPath, to: IndexPath(item: toIndex, section: 0))
		}
		return true
	}
}

// MARK: -

// Uses width of parent view to determine item width minus insets
extension NSCollectionView {
	var visibleWidth: CGFloat {
		guard let layout = collectionViewLayout as? NSCollectionViewFlowLayout else {
			return frame.width }
		return frame.width - layout.sectionInset.left - layout.sectionInset.right
	}
}


// MARK: -
class NoScrollView: NSScrollView {
	override func scrollWheel(with event: NSEvent) {
		nextResponder?.scrollWheel(with: event)
	}
}
