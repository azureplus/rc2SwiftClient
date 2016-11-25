//
//  Rc2Error.swift
//
//  Copyright ©2016 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation

/// A protocol to group domain-specific errors that will be nested inside an Rc2Error
public protocol Rc2DomainError {}

//error object used throughoout project
public struct Rc2Error: Error {
	/// basic categories of errors
	public enum Rc2ErrorType: String, Error {
		/// a requested object was not found
		case noSuchElement
		/// a requested operation is already in progress
		case alreadyInProgress
		/// problem parsing json, Freddy error is nested
		case invalidJson
		/// nestedError will be the NSError
		case cocoa
		/// nested error is related to the file system
		case file
		/// a wrapped error from a websocket
		case websocket
		/// a generic network error
		case network
		/// an error from the docker engine
		case docker
		/// update of an object failed
		case updateFailed
		/// logical error that is not critical
		case logic
		/// wraps an unknown error
		case unknown
	}

	/// possible severity levels of an error. defaults to .error
	public enum Severity: Int {
		case warning, error, fatal
	}

	/// the generic type of the error
	public let type: Rc2ErrorType
	/// the underlying error that caused the problem
	public let nestedError: Error?
	/// a clue as to how to handle the error
	public let severity: Severity
	/// details about the error suitable to show the user
	public let explanation: String?

	/// intialize an error
	public init(type: Rc2ErrorType = .unknown, nested: Error? = nil, severity: Severity = .error, explanation: String? = nil) {
		self.type = type
		self.nestedError = nested
		self.severity = severity
		self.explanation = explanation
	}
}