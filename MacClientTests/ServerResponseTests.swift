//
//  ServerResponseTests.swift
//  Rc2Client
//
//  Created by Mark Lilback on 1/13/16.
//  Copyright © 2016 West Virginia University. All rights reserved.
//

import XCTest
@testable import MacClient
import SwiftyJSON

class ServerResponseTests: XCTestCase {

	override func setUp() {
		super.setUp()
	}
	
	override func tearDown() {
		super.tearDown()
	}

	func testSessionImageFromJSON() {
		let path : String = NSBundle(forClass: self.dynamicType).pathForResource("resultsWithImages", ofType: "json")!
		let resultData = NSData(contentsOfFile: path)
		let srcJson = JSON(data:resultData!)
		let rsp = ServerResponse.parseResponse(srcJson)
		XCTAssertNotNil(rsp)
		switch (rsp!) {
			case .ExecComplete(let qid, let bid, let imgs):
				XCTAssertEqual(imgs.count, 3)
				XCTAssertEqual(bid, 1)
				XCTAssertEqual(qid, 1001)
				sessionImageCodingTest(imgs[0])
			default:
				XCTFail("parseResponse returned wrong ServerResponse type")
		}
	}
	
	func sessionImageCodingTest(image:SessionImage) {
		let data = NSKeyedArchiver.archivedDataWithRootObject(image)
		let obj = NSKeyedUnarchiver.unarchiveObjectWithData(data) as! SessionImage
		XCTAssertEqual(image, obj)
	}
}
