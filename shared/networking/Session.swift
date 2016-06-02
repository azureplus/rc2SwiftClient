//
//  Session.swift
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import XCGLogger
#if os(OSX)
	import AppKit
#endif
import SwiftyJSON
import MessagePackSwift

public enum ExecuteType: String {
	case Run = "run", Source = "source", None = ""
}

public enum FileOperation: String {
	case Remove = "rm", Rename = "rename", Duplicate = "duplicate"
}

public class Session : NSObject, SessionFileHandlerDelegate {
	/// a static singleton for maintaining the current session. It is setable, so unit tests can use a mock session
	///tried kvo, forced to use notifications
	class Manager: NSObject {
		dynamic var currentSession: Session? {
			didSet {
				if let session = currentSession {
					NSNotificationCenter.defaultCenter().postNotificationNameOnMainThread(CurrentSessionChangedNotification, object: session)
				}
			}
		}
		///need to keep a reference while open is in progress, as it is not yet assigned to currentSession
		var sessionBeingOpened: Session?
	}
	static var manager: Manager = Manager()
	
	//the workspace this session represents
	let workspace : Workspace
	///the WebSocket for communicating with the server
	let wsSource : WebSocketSource
	///used to report progress on async operations
	weak var appStatus: AppStatus?
	///abstraction of file handling
	let fileHandler: SessionFileHandler
	///
	weak var delegate : SessionDelegate?

	///regex used to catch user entered calls to help so we can hijack and display through our mechanism
	var helpRegex : NSRegularExpression = {
		return try! NSRegularExpression(pattern: "(help\\(\\\"?([\\w\\d]+)\\\"?\\))\\s*;?\\s?", options: [.DotMatchesLineSeparators])
	}()
	
	private(set) var connectionOpen:Bool = false
	private var keepAliveTimer:dispatch_source_t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue())
	
	///closure syntax for a transaction complete callback
	/// - parameter $0: the transaction id (key in the pendingTransaction dictionary)
	/// - parameter $1: the message received from the server, if available
	typealias TransactionCompletion = (String, JSON?) -> Void
	
	///a dictionary of transaction ids mapped to closures called when the server says the transaction is complete
	private var pendingTransactions: [String:TransactionCompletion] = [:]
	///if we are getting variable updates from the server
	private var watchingVariables:Bool = false
	
	init(_ wspace:Workspace,  source:WebSocketSource, appStatus:AppStatus, networkConfig config:NSURLSessionConfiguration, delegate:SessionDelegate?=nil)
	{
		workspace = wspace
		self.delegate = delegate
		self.wsSource = source
		self.appStatus = appStatus
		self.fileHandler = DefaultSessionFileHandler(wspace: workspace, baseUrl: RestServer.sharedInstance.baseUrl!, config: config, appStatus: appStatus)

		super.init()
		fileHandler.fileDelegate = self
		wsSource.binaryType = .NSData
		wsSource.event.open = { [unowned self] in
			dispatch_async(dispatch_get_main_queue()) {
				Session.manager.currentSession = self
				Session.manager.sessionBeingOpened = nil
				self.connectionOpen = true
				self.fileHandler.loadFiles()
				self.delegate?.sessionOpened()
			}
		}
		wsSource.event.close = { [unowned self] (code, reason, clear)in
			self.connectionOpen = false
			self.delegate?.sessionClosed()
			//only release session once we have confirmed from remote server that it is closed
			Session.manager.currentSession = nil
		}
		wsSource.event.message = { [unowned self] message in
			log.info("got message:\(message)")
			self.handleReceivedMessage(message)
		}
		wsSource.event.error = { [unowned self] error in
			self.delegate?.sessionErrorReceived(error)
		}
		//setup a timer to send keep alive messages every 2 minutes
		let interval = 120 * NSEC_PER_SEC
		dispatch_source_set_timer(keepAliveTimer, dispatch_time(DISPATCH_TIME_NOW, Int64(interval)), interval, NSEC_PER_SEC/10)
		dispatch_source_set_event_handler(keepAliveTimer) { [unowned self] in
			self.sendMessage(["msg":"keepAlive"])
		}
		dispatch_resume(keepAliveTimer)
		//need to keep a reference or ARC will dealloc while waiting on open response
		Session.manager.sessionBeingOpened = self
	}
	
	///opens the websocket with the specified request
	/// - parameter request: a ws:// or wss:// request to use for the websocket
	func open(request:NSURLRequest) {
		self.wsSource.open(request: request, subProtocols: [])
	}
	
	///closes the websocket, which can not be reopened
	func close() {
		dispatch_source_cancel(keepAliveTimer)
		self.wsSource.close(1000, reason: "") //default values that can't be specified in a protocol
	}
	
	//MARK: public request methods
	
	///Sends an execute request to the server
	/// - parameter srcScript: the script code to send to the server
	/// - parameter type: whether to run or source the script
	func executeScript(srcScript: String, type:ExecuteType = .Run) {
		//don't send empty scripts
		guard srcScript.characters.count > 0 else {
			return
		}
		var script = srcScript
		let helpCheck = helpRegex.firstMatchInString(script, options: [], range: NSMakeRange(0, script.utf16.count))
		if helpCheck?.numberOfRanges == 3 {
			let topic = script.substringWithRange((helpCheck?.rangeAtIndex(2).toStringRange(script))!)
			let adjScript = script.stringByReplacingCharactersInRange((helpCheck?.range.toStringRange(script))!, withString: "")
			lookupInHelp(topic)
			guard adjScript.utf16.count > 0 else {
				return
			}
			script = adjScript
		}
		sendMessage(["msg":"execute", "type":type.rawValue, "code":script])
	}
	
	/// sends a request to execute a script file
	/// - parameter fileId: the id of the file to execute
	/// - parameter type: whether to run or source the file
	func executeScriptFile(fileId:Int, type:ExecuteType = .Run) {
		sendMessage(["msg":"execute", "type":type.rawValue, "fileId":fileId])
	}
	
	/// clears all variables in the global environment
	func clearVariables() {
		executeScript("rc2.clearEnvironment()");
	}
	
	/// sends a help request
	/// - parameter str: The string to search for
	func lookupInHelp(str:String) {
		sendMessage(["msg":"help", "topic":str])
	}
	
	/// asks the server for a refresh of all environment variables
	func forceVariableRefresh() {
		sendMessage(["msg":"watchVariables", "watch":true])
	}
	
	/// ask the server to send a message with current variable values and delta messages as they change
	func startWatchingVariables() {
		if (watchingVariables) { return; }
		sendMessage(["msg":"watchVariables", "watch":true])
		watchingVariables = true
	}

	/// ask the server to stop sending environment delta messages
	func stopWatchingVariables() {
		if (!watchingVariables) { return }
		sendMessage(["msg":"watchVariables", "watch":false])
		watchingVariables = false
	}
	
	/// asks the server to remove a file
	/// - parameter file: The file to remove
	func removeFile(file:File) {
		let transId = NSUUID().UUIDString
		sendMessage(["msg":"fileop", "fileId":file.fileId, "fileVersion":file.version, "operation":"rm", "transId":transId])
		let prog = NSProgress(parent: nil, userInfo: nil)
		prog.localizedDescription = "Removing file '\(file.name)'"
		appStatus?.updateStatus(prog)
		pendingTransactions[transId] = { [weak self] (responseId, _) in
			self?.appStatus?.updateStatus(nil)
		}
	}
	
	//MARK: SessionFileHandlerDelegate methods
	
	/// callback when the file handler has loaded all files
	func filesLoaded() {
		appStatus?.updateStatus(nil)
		delegate?.sessionFilesLoaded(self)
	}
	
	///sends document changes to the server
	///parameter completionHandler: called when the server confirms it saved it and passed to any subsytems (like R)
	func sendSaveFileMessage(document:EditorDocument, executeType:ExecuteType = .None, completionHandler:(EditorDocument, NSError?) -> Void) {
		let data = NSMutableData()
		let transId = encodeDocumentSaveMessage(document, data: data)
		pendingTransactions[transId] = { (responseId, _) in
			completionHandler(document, nil)
		}
		self.wsSource.send(data)
	}
	
	//MARK: private methods
	
	//assumes currentContents of document is what should be sent to the server
	///returns a token to uniquely identify this transaction, encoded into the message data
	private func encodeDocumentSaveMessage(document:EditorDocument, data:NSMutableData) -> String {
		let uniqueIdent = NSUUID().UUIDString
		let encoder = MessagePackEncoder()
		var attrs = ["msg":MessageValue.forValue("save"), "apiVersion":MessageValue.forValue(Int(1))]
		attrs["transId"] = MessageValue.forValue(uniqueIdent)
		attrs["fileId"] = MessageValue.forValue(document.file.fileId)
		attrs["fileVersion"] = MessageValue.forValue(document.file.version)
		attrs["content"] = MessageValue.forValue(document.currentContents)
		encoder.encodeValue(MessageValue.DictionaryValue(MessageValueDictionary(attrs)))
		data.appendData(encoder.data!)
	data.writeToURL(NSURL(fileURLWithPath: "/tmp/lastSaveToServer"), atomically: true)
		return uniqueIdent
	}
	
	///processes a binary response from the WebSocket
	/// - parameter data: The MessagePack data
	private func processBinaryResponse(data:NSData) {
		var parsedValues:[MessageValue]? = nil
		let decoder = MessagePackDecoder(data: data)
		do {
			parsedValues = try decoder.parse()
		} catch let err {
			log.error("error parsing binary message:\(err)")
		}
		//get the dictionary of messagevalues
		guard case MessageValue.DictionaryValue(let msgDict) = parsedValues![0] else {
			log.warning("received invalid binary response from server")
			return
		}
		let dict = msgDict.nativeValue()
		switch dict["msg"] as! String {
		case "saveResponse":
			handleSaveResponse(dict)
		case "showOutput":
			let file = File(dict: dict["file"] as! [String:AnyObject])
			let response = ServerResponse.ShowOutput(queryId: dict["queryId"] as! Int, updatedFile: file)
			delegate?.sessionMessageReceived(response)
			fileHandler.updateFile(file, withData: dict["fileData"] as? NSData)
		default:
			log.warning("received unknown binary message: \(dict["msg"])")
			return
		}
	}
	
	//we've got a dictionary of the save response. keys should be transId, success, file, error
	private func handleSaveResponse(rawDict:[String:AnyObject]) {
		if let transId = rawDict["transId"] as? String {
			pendingTransactions[transId]?(transId, nil)
			pendingTransactions.removeValueForKey(transId)
		}
		if let errorDict = rawDict["error"] as? Dictionary<String,AnyObject> {
			//TODO: inform user
			log.error("got save response error \(errorDict["message"] as? String)")
			return
		}
		do {
			let fileData = try NSJSONSerialization.dataWithJSONObject(rawDict["file"]!, options: [])
			let json = JSON(data: fileData)
			let file = File(json: json)
			let idx = workspace.indexOfFilePassingTest()
			{ obj, idx, _ in
				return (obj as! File).fileId == file.fileId
			}
			assert(idx != NSNotFound)
			workspace.replaceFileAtIndex(idx, withFile: file)
		} catch let err {
			log.error("error parsing binary message: \(err)")
		}
	}
	
	private func handleFileResponse(transId:String, operation:FileOperation, file:File) {
		switch(operation) {
		case .Duplicate:
			//TODO: support
			break
		case .Rename:
			//TODO: support
			break
		case .Remove:
			if let idx = workspace.indexOfFile(file) {
				workspace.removeFileAtIndex(idx)
			} else {
				log.warning("got remove response for unknown file")
			}
			break
		}
	}
	
	private func handleReceivedMessage(message:Any) {
		if let stringMessage = message as? String {
			let jsonMessage = JSON.parse(stringMessage)
			if let response = ServerResponse.parseResponse(jsonMessage) {
				if case let .FileOperationResponse(transId, operation, file) = response {
					handleFileResponse(transId, operation:operation, file:file)
				} else {
					self.delegate?.sessionMessageReceived(response)
				}
			}
			if let transId = jsonMessage["transId"].string {
				pendingTransactions[transId]?(transId, jsonMessage)
				pendingTransactions.removeValueForKey(transId)
			}
		} else if let _ = message as? NSData {
			processBinaryResponse(message as! NSData)
		} else {
			log.error("invalid binary data format received: \(message)")
		}
	}
	
	func sendMessage(message:Dictionary<String,AnyObject>) -> Bool {
		guard NSJSONSerialization.isValidJSONObject(message) else {
			return false
		}
		do {
			let json = try NSJSONSerialization.dataWithJSONObject(message, options: [])
			let jsonStr = NSString(data: json, encoding: NSUTF8StringEncoding)
			self.wsSource.send(jsonStr as! String)
		} catch let err as NSError {
			log.error("error sending json message on websocket:\(err)")
			return false
		}
		return true
	}
}
