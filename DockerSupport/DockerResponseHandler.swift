//
//  BaseResponseHandler.swift
//
//  Copyright ©2017 Mark Lilback. This file is licensed under the ISC license.
//

import Foundation
import Freddy
import ClientCore
import os

///This class takes a socket that contains the response from a docker api call

enum MessageType: Equatable {
	case headers(HttpHeaders), json([JSON]), data(Data), complete, error(Rc2Error)
	
	static func == (a: MessageType, b: MessageType) -> Bool {
		switch (a, b) {
		case (.error(let e1), .error(let e2)):
			return e1.type == e2.type //FIXME: not correct
		case (.complete, .complete):
			return true
		case (.json(let j1), .json(let j2)):
			return j1 == j2
		case (.data(let d1), .data(let d2)):
			return d1 == d2
		case (.headers(let h1), .headers(let h2)):
			return h1 == h2
		default:
			return false
		}
	}
}

///Parses the http response from a socket that is returning mulitple json messages separated by newlines
class DockerResponseHandler {
	let crnl = Data(bytes: [13, 10])
	private let handler: (MessageType) -> Void
	private let fileHandle: FileHandle
	private var readSource: DispatchSourceRead?
	private var gotHeader = false
	private var myQueue = DispatchQueue.global()
	private var isChunked: Bool = false
	private var isHijacked = false
	private var chunkCount: Int = 0
	
	/// Initiailize an instance
	///
	/// - Parameters:
	///   - fileHandle: the source of the data, must have a valid fileDescriptor value
	init(fileHandle: FileHandle, hijacked: Bool = false, handler: @escaping (MessageType) -> Void) {
		self.fileHandle = fileHandle
		self.handler = handler
		self.isHijacked = hijacked
	}
	
	///chokepoint for logging/debugging
	func sendMessage(_ msgType: MessageType) {
		myQueue.async {
			self.handler(msgType)
		}
	}
	
	/// starts reading input
	///
	/// - Parameter queue: the queue to receive dispatch callbacks on
	func start(queue: DispatchQueue = .global()) {
		myQueue = queue
		readSource = DispatchSource.makeReadSource(fileDescriptor: fileHandle.fileDescriptor, queue: queue)
		readSource?.setEventHandler(handler: eventHandler)
		readSource?.setCancelHandler(handler: cancelHandler)
		readSource?.resume()
	}
	
	private func cancelHandler() {
		fileHandle.closeFile()
		//if there was an error, don't send complete
		guard readSource != nil else { return }
		sendMessage(.complete)
	}
	
	private func eventHandler() {
		guard let source = readSource else { return }
		let sizeRead = source.data
		//handle end of stream
		if sizeRead == 0 {
			sendMessage(.complete)
			readSource = nil
			source.cancel()
			return
		}
		let data = fileHandle.readData(ofLength: Int(sizeRead))
		do {
			guard gotHeader else {
				parseHeader(data)
				return
			}
			try parse(data: data)
		} catch {
			readSource = nil
			sendMessage(.error(Rc2Error(type: .network, nested: error)))
			source.cancel()
		}
	}
	
	private func parseHijacked(data: Data) throws {
		//header := [8]byte{STREAM_TYPE, 0, 0, 0, SIZE1, SIZE2, SIZE3, SIZE4}
		let headerSize: Int = 8
		var currentOffset: Int = 0
		repeat {
			guard data.count - currentOffset > headerSize else {
				throw DockerError.httpError(statusCode: 500, description: "received hijacked data with invalid length", mimeType: nil)
			}
			// cast first 8 bytes to array of 2 Int32s. Convert the second to big endian to get size of message
			let (type, size) = data.subdata(in: currentOffset..<currentOffset + headerSize).withUnsafeBytes
			{ (ptr: UnsafePointer<UInt8>) -> (UInt8, Int) in
				return (ptr[0], ptr.withMemoryRebound(to: Int32.self, capacity: 2)
				{ (intPtr: UnsafePointer<Int32>) -> Int in
					return Int(Int32(bigEndian: intPtr[1]))
				})
			}
			guard type == 1 || type == 2 else {
				throw DockerError.httpError(statusCode: 500, description: "invalid hijacked stream type", mimeType: nil)
			}
			currentOffset += headerSize
			let nextOffset = currentOffset + size
			let currentChunk = data.subdata(in: currentOffset..<nextOffset)
			sendMessage(.data(currentChunk))
			currentOffset += size
		} while data.count > currentOffset

//		let headerSize = 8
//		var currentOffset = 0
//		repeat {
//			guard data.count - currentOffset > headerSize else {
//				throw DockerError.httpError(statusCode: 500, description: "received hijacked data with invalid length", mimeType: nil)
//			}
//			// cast first 8 bytes to array of 2 Int32s. Convert the second to big endian to get size of message
//			let (type, size) = data.subdata(in: currentOffset..<headerSize).withUnsafeBytes
//				{ (ptr: UnsafePointer<UInt8>) -> (UInt8, Int) in
//					return (ptr[0], ptr.withMemoryRebound(to: Int32.self, capacity: 2)
//						{ (intPtr: UnsafePointer<Int32>) -> Int in
//							return Int(Int32(bigEndian: intPtr[1]))
//						})
//			}
//			guard type == 1 || type == 2 else {
//				throw DockerError.httpError(statusCode: 500, description: "invalid hijacked stream type", mimeType: nil)
//			}
//			currentOffset += headerSize
//			let nextOffset = currentOffset + size
//			let currentChunk = data.subdata(in: headerSize..<nextOffset)
//			sendMessage(.data(currentChunk))
//			currentOffset += size
//		} while data.count > currentOffset
	}
	
	/// Parses the data for any chunks
	private func parse(data: Data) throws {
		guard let lineEnd = data.range(of: crnl) else {
			os_log("failed to find CRNL in chunk", log: .docker)
			throw DockerError.httpError(statusCode: 500, description: "failed to find CRNL in chunk", mimeType: nil)
		}
		let sizeData = data.subdata(in: 0..<lineEnd.lowerBound)
		guard let dataStr = String(data: sizeData, encoding: .utf8),
			let chunkLength = Int(dataStr, radix: 16)
			else { fatalError("failed to read chunk length") }
		os_log("got chunk length %d", log: .docker, type: .debug, chunkLength)
		guard chunkLength > 0 else {
			sendMessage(.complete)
			return
		}
		if isHijacked {
			try parseHijacked(data: data.subdata(in: lineEnd.upperBound..<data.count))
			return
		}
		let chunkEnd = chunkLength + sizeData.count + 1
		let chunkData = data.subdata(in: lineEnd.upperBound..<chunkEnd)
		sendMessage(.data(chunkData))
		//remaining data starts with the CRNL after chunkEnd
		let rawRemaining = data.subdata(in: chunkEnd + 1..<data.count)
		guard let nextCRNL = rawRemaining.range(of: crnl) else {
			throw DockerError.httpError(statusCode: 500, description: "error parsing chunk remainder", mimeType: "")
		}
		let remaining = rawRemaining.subdata(in: nextCRNL.upperBound..<rawRemaining.count)
		try parse(data: remaining)
	}
	
	/// subclasses should override
	func parseChunkData(data: Data) -> MessageType {
		return .data(data)
	}
	
	private func parseHeader(_ data: Data) {
		var cancel = false
		defer { if cancel { DispatchQueue.main.async { self.readSource?.cancel() } } }
		do {
			let (headData, remainingData) = try HttpStringUtils.splitResponseData(data)
			guard let headString = String(data: headData, encoding: .utf8),
				let headers = try? HttpStringUtils.extractHeaders(headString)
				else
			{
				sendMessage(.error(Rc2Error(type: .network, explanation: "failed to parse headers")))
				cancel = true
				return
			}
			guard headers.statusCode >= 200, headers.statusCode <= 299 else {
				sendMessage(.error(Rc2Error(type: .docker, explanation: "invalid status code")))
				cancel = true
				return
			}
			if let teheader = headers.headers["Transfer-Encoding"], teheader == "chunked" {
				isChunked = true
			} else {
				cancel = true
			}
			//TODO: confirm 200 response on http status from headData
			sendMessage(.headers(headers))
			gotHeader = true
			guard remainingData.count > 0 else { return }
			if isChunked {
				try parse(data: remainingData)
			} else {
				sendMessage(.data(remainingData))
			}
		} catch {
			os_log("error parsing data %{public}s", log: .docker, error as NSError)
		}
	}
}