//
//  FileCacheTests.swift
//  SwiftClient
//
//  Created by Mark Lilback on 2/8/16.
//  Copyright © 2016 Rc2. All rights reserved.
//

import XCTest
@testable import MacClient
import BrightFutures
import Mockingjay

class FileCacheTests: BaseTest, FileCacheDownloadDelegate {
	var cache:FileCache!
	var wspace:Workspace!
	var file:File!
	var filePath:String!
	var fileData:NSData!
	var destUri:String!
	var cachedUrl:NSURL!
	var baseUrl:NSURL = NSURL(string: "http://localhost/")!
	var multiExpectation:XCTestExpectation?

	override class func initialize() {
		NSURLSessionConfiguration.mockingjaySwizzleDefaultSessionConfiguration()
	}
	
	override func setUp() {
		super.setUp()
		cache = FileCache(baseUrl: baseUrl)
		wspace = sessionData.workspaces.first!
		file = (wspace.files.first)!
		filePath = NSBundle(forClass: self.dynamicType).pathForResource("lognormal", ofType: "R")!
		fileData = NSData(contentsOfFile: filePath)!
		destUri = "/workspaces/\(wspace.wspaceId)/files/\(wspace.files[0].fileId)"
		cachedUrl = cache.cachedFileUrl(file)
		do { try mockFM.removeItemAtURL(cachedUrl) } catch _ {}
	}
	
	override func tearDown() {
		do { try mockFM.removeItemAtURL(cachedUrl) } catch _ {}
		super.tearDown()
	}
	
	func testDownload() {
		XCTAssertFalse(cache.isFileCached(file))
		//test download
		stub(everything, builder: http(200, headers:["Content-Type":file.fileType.mimeType], data:fileData))
		let expect = expectationWithDescription("download from server")
		cache.downloadFile(file, fromWorkspace: wspace).onSuccess { (furl) -> Void in
			XCTAssertEqual(NSData(contentsOfURL: furl!), self.fileData, "data failed to match")
			XCTAssert(self.file.urlXAttributesMatch(furl!), "xattrs don't match")
			expect.fulfill()
		}.onFailure { (error) -> Void in
			log.error("download error: \(error)")
			XCTAssert(false)
			expect.fulfill()
		}
		self.waitForExpectationsWithTimeout(2) { (err) -> Void in }
	}
	
	func testCacheHit() {
		fileData.writeToURL(cachedUrl, atomically: true)
		file.writeXAttributes(cachedUrl)
		
		//test file is cached
		stub(uri(destUri), builder: http(404, headers:[:], data:fileData))
		let expect = expectationWithDescription("download from server")
		cache.downloadFile(file, fromWorkspace: wspace).onSuccess { (furl) -> Void in
			XCTAssertEqual(NSData(contentsOfURL: furl!), self.fileData)
			XCTAssert(self.file.urlXAttributesMatch(furl!))
			expect.fulfill()
		}.onFailure { (error) -> Void in
			XCTAssert(false)
			expect.fulfill()
		}
		self.waitForExpectationsWithTimeout(2) { (err) -> Void in }
	}

	func testNoSuchFile() {
		stub(uri(destUri), builder: http(404, headers:[:], data:fileData))
		let expect = expectationWithDescription("404 from server")
		cache.downloadFile(file, fromWorkspace: wspace).onSuccess { (furl) -> Void in
			XCTFail("404 download was a success")
			expect.fulfill()
			}.onFailure { (error) -> Void in
				XCTAssertTrue(error == .FileNotFound)
				expect.fulfill()
		}
		self.waitForExpectationsWithTimeout(2) { (err) -> Void in }
	}

	func testMultipleDownload() {
		//use contents of words file instead of the R file we use in other tests (i.e. make it a lot larger)
		let wordsUrl = NSURL(fileURLWithPath: "/usr/share/dict/words")
		fileData = NSData(contentsOfURL: wordsUrl)!
		let fakeFile = File(json: JSON.parse("{\"id\" : 1,\"wspaceId\" : 1,\"name\" : \"sample.R\",\"version\" : 0,\"dateCreated\" : 1439407405827,\"lastModified\" : 1439407405827,\"etag\": \"f/1/0\", \"fileSize\":\(fileData.length) }"))
		file = fakeFile
		wspace.filesArray.removeObjectAtIndex(0)
		wspace.filesArray.insertObject(fakeFile, atIndex: 0)
		//stub out download of both files
		stub(uri("/workspaces/\(wspace.wspaceId)/files/\(wspace.files[0].fileId)"), builder: http(200, headers:[:], data:fileData))
		let file1Data = fileData.subdataWithRange(NSMakeRange(0, wspace.files[1].fileSize))
		stub(uri("/workspaces/\(wspace.wspaceId)/files/\(wspace.files[1].fileId)"), builder: http(200, headers:[:], data:file1Data))
		
		multiExpectation = expectationWithDescription("download from server")
		try! cache.cacheFilesForWorkspace(wspace, delegate:self)
		self.waitForExpectationsWithTimeout(2) { (err) -> Void in }
		var fileSize:UInt64 = 0
		do {
			let fileAttrs:NSDictionary = try NSFileManager.defaultManager().attributesOfItemAtPath(cachedUrl.path!)
			fileSize = fileAttrs.fileSize()
		} catch let e as NSError {
			XCTAssertFalse(true, "error getting file size:\(e)")
		}
		XCTAssertEqual(fileSize, UInt64(fileData.length))
	}
	
	///called as bytes are recieved over the network
	func fileCache(cache:FileCache, updatedProgressWithStatus progress:FileCacheDownloadStatus) {
		//TODO: inspect that the percentage is what we expect
		log.info("got progress \(progress.percentComplete)")
	}
	
	///called when all the files have been downloaded and cached
	func fileCacheDidFinishDownload(cache:FileCache, workspace:Workspace) {
		log.info("got complete")
		multiExpectation?.fulfill()
	}
	
	///called on error. The download is canceled and fileCacheDidFinishDownload is not called
	func fileCache(cache:FileCache, failedToDownload file:File, error:ErrorType) {
		log.info("error for dload:\(error)")
		multiExpectation?.fulfill()
	}

}
