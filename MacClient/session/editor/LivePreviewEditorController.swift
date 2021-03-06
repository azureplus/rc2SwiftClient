//
//  LivePreviewEditorController.swift
//  MacClient
//
//  Created by Mark Lilback on 10/30/18.
//  Copyright © 2018 Rc2. All rights reserved.
//

import Cocoa
import MJLLogger
import ClientCore
import WebKit
import SwiftyUserDefaults

class LivePreviewEditorController: BaseSourceEditorController {
	var outputController: LivePreviewOutputController? { didSet { outputController?.parserContext = parser } }

	private var webView: WKWebView?

	// used to prevent recursion (due to didSet) in outputControllerChanged()
	private var inOutputChange = false

	// used to wrap lastChange with a queue, but that was causing recursive errors. Instead, this values should only be used on the main thread
	private var lastTextChange: TimeInterval = 0
	private var lastChangeTimer: DispatchSourceTimer!
	private var lastChangeRange: NSRange?
	private var lastChangeDelta: Int = 0
	private var timerRunning = false

	override func viewDidLoad() {
		useParser = true
		super.viewDidLoad()
		editor?.isEditable = true
		lastChangeTimer = DispatchSource.makeTimerSource(queue: .main)
		lastChangeTimer.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(500), leeway: .milliseconds(100))
		lastChangeTimer.setEventHandler { [weak self] in
			guard let me = self else { return }
			guard let lastRange = me.lastChangeRange, let editor = me.editor else { return }
			let curTime = Date.timeIntervalSinceReferenceDate
			if (curTime - me.lastTextChange) > Defaults[.previewUpdateDelay] {
				me.lastTextChange = curTime
				defer { me.lastChangeRange = nil }
				if let oc = me.outputController,
					oc.contentsEdited(contents: editor.string, range: lastRange, delta: me.lastChangeDelta)
				{
					if me.ignoreContentChanges { return }
					me.save(edits: editor.string, reload: false)
				}
			}
		}
		lastChangeTimer.activate()
		lastChangeTimer.suspend()
	}

	override func setContext(context: EditorContext) {
		super.setContext(context: context)
		precondition(outputController != nil)
		outputController?.setEditorContext(context)
	}

	override func loaded(content: String) {
		guard context?.currentDocument.value?.isRmarkdown ?? false else {
			super.loaded(content: "")
			return
		}
		super.loaded(content: content)
		colorizeHighlightAttributes()
	}

	override func contentsChanged(_ contents: NSTextStorage, range: NSRange, changeLength delta: Int) {
		// really does nothing, but call to be safe
		super.contentsChanged(contents, range: range, changeLength: delta)
		do {
			try parser?.reparse()
		} catch {
			Log.warn("failed to parse rmd \(error)", .app)
		}
		colorizeHighlightAttributes()
		lastTextChange = Date.timeIntervalSinceReferenceDate
		lastChangeRange = range
		lastChangeDelta = delta
	}

	/// subclasses should override and save contents via save(edits:). super should not be called
	override func editsNeedSaving() {

	}

	func textDidBeginEditing(_ notification: Notification) {
		guard !timerRunning else { return }
		lastChangeTimer.resume()
	}

	func textDidEndEditing(_ notification: Notification) {
		lastChangeTimer.suspend()
		timerRunning = false
	}
}
