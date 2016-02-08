//
//  FileCache.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import BrightFutures

public class FileCache: NSObject {
	var fileManager:FileManager
	private lazy var urlSession:NSURLSession = {
		return NSURLSession(configuration: RestServer.sharedInstance.urlConfig)
	}()
	
	lazy var fileCacheUrl: NSURL = { () -> NSURL in
		do {
			let cacheDir = try self.fileManager.URLForDirectory(.CachesDirectory, inDomain: .UserDomainMask, appropriateForURL: nil, create: true)
			if !cacheDir.checkResourceIsReachableAndReturnError(nil) {
				try self.fileManager.createDirectoryAtURL(cacheDir, withIntermediateDirectories: true, attributes: nil)
			}
			return cacheDir
		} catch let err {
			log.error("failed to create file cache dir:\(err)")
		}
		fatalError("failed to create file cache")
	}()
	
	override init() {
		fileManager = NSFileManager.defaultManager()
		super.init()
	}
	
	func isFileCached(file:File) -> Bool {
		return cachedFileUrl(file).checkResourceIsReachableAndReturnError(nil)
	}
	
	func downloadFile(file:File, fromWorkspace wspace:Workspace) -> Future<NSURL?,FileError> {
		var p = Promise<NSURL?,FileError>()
		let restServer = RestServer.sharedInstance
		let cachedUrl = cachedFileUrl(file)
		let reqUrl = NSURL(string: "workspaces/\(wspace.wspaceId)/files/\(file.fileId)", relativeToURL: restServer.baseUrl)
		let req = NSMutableURLRequest(URL: reqUrl!)
		req.HTTPMethod = "GET"
		if cachedUrl.checkResourceIsReachableAndReturnError(nil) {
			req.addValue("f/\(file.fileId)/\(file.version)", forHTTPHeaderField: "If-None-Match")
		}
		req.addValue(file.fileType.mimeType, forHTTPHeaderField: "Accept")
		let task = urlSession.downloadTaskWithRequest(req) { (dloadUrl, response, error) -> Void in
			let hresponse = response as! NSHTTPURLResponse
			guard error == nil else { p.failure(.FileNotFound); return }
			switch (hresponse.statusCode) {
			case 304: //use existing
				p.success(cachedUrl)
			case 200: //dloaded it
				self.fileManager.moveTempFile(dloadUrl!, toUrl: cachedUrl, file:file, promise: &p)
			default:
				break
			}
		}
		task.resume()
		return p.future
	}
	
	private func cachedFileUrl(file:File) -> NSURL {
		let fileUrl = NSURL(fileURLWithPath: "\(file.fileId).\(file.fileType.fileExtension)", relativeToURL: fileCacheUrl)
		return fileUrl
	}
}
