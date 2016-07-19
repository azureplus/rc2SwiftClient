//
//  LocalServerProtocol.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

@objc protocol LocalServerProtocol {
	func isDockerRunning(handler: (Bool) -> Void)
}
