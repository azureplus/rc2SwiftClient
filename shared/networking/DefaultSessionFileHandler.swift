//
//  DefaultSessionFileHandler.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import BrightFutures

class DefaultSessionFileHandler: SessionFileHandler {
	var workspace:Workspace
	let fileCache:FileCache
	let appStatus:AppStatus?
	var baseUrl:NSURL
	weak var fileDelegate:SessionFileHandlerDelegate?
	private(set) var filesLoaded:Bool = false
	private var downloadPromise: Promise <Bool,NSError>
	
	init(wspace:Workspace, baseUrl:NSURL, config:NSURLSessionConfiguration, appStatus:AppStatus?) {
		self.workspace = wspace
		self.appStatus = appStatus
		self.fileCache = FileCache(workspace: workspace, baseUrl: baseUrl, config: config, appStatus:appStatus)
		self.baseUrl = baseUrl
		self.downloadPromise = Promise<Bool,NSError>()
	}
	
	func loadFiles() {
		filesLoaded = false //can be called to cache any new files
		fileCache.cacheAllFiles() { (progress) in
			self.appStatus?.updateStatus(progress)
			progress.rc2_addCompletionHandler() {
				if let error = progress.rc2_error {
					self.downloadPromise.failure(error)
				} else {
					self.filesLoaded = true
					self.downloadPromise.success(true)
				}
				self.appStatus?.updateStatus(nil)
			}
		}
	}

	func contentsOfFile(file:File) -> Future<NSData?,FileError> {
		let p = Promise<NSData?,FileError>()
		if !filesLoaded {
			//still downloading
			downloadPromise.future.onSuccess { _ in
				if let data = NSData(contentsOfURL: self.fileCache.cachedFileUrl(file)) {
					p.success(data)
				} else {
					p.failure(FileError.FoundationError(error: self.downloadPromise.future.error!))
				}
			}.onFailure() { err in
				p.failure(FileError.FoundationError(error: err))
			}
		} else {
			if let data = NSData(contentsOfURL: fileCache.cachedFileUrl(file)) {
				p.success(data)
			} else {
				p.failure(.ReadError)
			}
		}
		return p.future
	}
	
	///called when all the files have been downloaded and cached
	func loadComplete() {
		fileDelegate?.filesLoaded()
		filesLoaded = true
		downloadPromise.success(true)
	}
	
}