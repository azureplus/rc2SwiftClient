//
//  NetworkingError.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

public enum NetworkingError: Error {
	case invalidJson
	case unsupportedFileType
	case connectionError(Error)
	case canceled
}