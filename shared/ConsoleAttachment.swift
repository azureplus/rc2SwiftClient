//
//  ConsoleAttachment.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public enum ConsoleAttachmentType: Int {
	case Image, File
}

public protocol ConsoleAttachment: NSObjectProtocol, NSSecureCoding {
	func serializeToAttributedString() -> NSAttributedString
}
