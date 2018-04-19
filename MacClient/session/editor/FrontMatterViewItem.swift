//
//  FrontMatterView.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa
import ReactiveSwift
import SyntaxParsing

class FrontMatterViewItem: NSCollectionViewItem, NotebookViewItem {
	
	// only here because protocol demands, won't be used
	var data: NotebookItemData?
	
	@IBOutlet var sourceView: SourceTextView!
	@IBOutlet var topView: NSView!

	weak var delegate: NotebookViewItemDelegate?
	var context: EditorContext? { didSet { contextChanged() } }
	private var fontDisposable: Disposable?
	private var fmDisposable: Disposable?
	private var myEdit = false
	var rmdDocument: RmdDocument? {
		didSet {
			fmDisposable?.dispose()
			fmDisposable = rmdDocument?.frontMatter.producer.startWithValues { [weak self] fmString in
				if self?.myEdit ?? false { return }
				self?.sourceView.string = fmString
			}
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		topView?.layer?.backgroundColor = noteBookFrontMatterColor.cgColor
		view.layer?.borderColor = NSColor.black.cgColor
		view.layer?.borderWidth = 1
		sourceView.delegate = self
		sourceView.changeCallback = { [weak self] in
			guard let me = self else { return }
			me.myEdit = true
			me.rmdDocument?.frontMatter.value = me.sourceView.string
			me.myEdit = false
			me.collectionView?.collectionViewLayout?.invalidateLayout()
		}
	}
	
	func size(forWidth width: CGFloat, data: NotebookItemData) -> NSSize {
		fatalError("not implemented")
	}
	
	func size(forWidth width: CGFloat) -> NSSize {
		let tmpSize = NSSize(width: width, height: 100)
		sourceView.setFrameSize(tmpSize)
		guard let manager = sourceView.textContainer?.layoutManager, let container = sourceView.textContainer else { return .zero }
		manager.ensureLayout(for: container)
		let textSize = manager.usedRect(for: container).size
		return NSSize(width: width, height: textSize.height + topView.frame.size.height + Notebook.textEditorMargin)
	}

	private func contextChanged() {
		fontDisposable?.dispose()
		fontDisposable = context?.editorFont.signal.observeValues { [weak self] font in
			self?.sourceView.font = font
		}
		guard let context = context else { return }
		sourceView.font = context.editorFont.value
	}
	
	@IBAction func addChunk(_ sender: Any?) {
		delegate?.addChunk(after: self, sender: sender as? NSButton)
	}
}

extension FrontMatterViewItem: NSTextViewDelegate {
	func textDidChange(_ notification: Notification) {
		myEdit = true
		rmdDocument?.frontMatter.value = sourceView.string
		myEdit = false
	}
}
