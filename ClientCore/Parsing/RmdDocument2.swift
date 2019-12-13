//
//  RmdDocument2.swift
//  ClientCore
//
//  Created by Mark Lilback on 12/10/19.
//  Copyright © 2019 Rc2. All rights reserved.
//

import Cocoa
import Rc2Parser
import Logging
import ReactiveSwift

internal let parserLog = Logger(label: "io.rc2.rc2parser")

fileprivate extension Array {
	/// same as using subscript, but it does range checking and returns nil if invalid index
	func element(at index: Int) -> Element? {
		guard index >= 0, index < count else { return nil }
		return self[index]
	}
}

/// a callback that recieves a parsed keyword. returns true if a help URL should be included for it
public typealias HelpCallback = (String) -> Bool

public enum ChunkType: String {
	case markdown, code, equation
	
	init(_ pctype: Rc2Parser.ChunkType) {
		switch pctype {
		case .markdown:
			self = .markdown
		case .code:
			self = .code
		case .equation:
			self = .equation
		default:
			fatalError("unsupported chunk type \(pctype)")
		}
	}
}

/// A parsed representation of an .Rmd file
public class RmdDocument2: CustomDebugStringConvertible {
	private var textStorage = NSTextStorage()
	private var parser = RmdParser()
	/// the chunks in this document
	public private(set) var chunks = [RmdDocumentChunk]()
	/// any frontmatter that exists in the document
	public private(set) var frontMatter: String?
	/// the attributed contents of this document
	public var attributedString: NSAttributedString { return NSAttributedString(attributedString: textStorage) }
	/// version of contents after removing any text attachments
	public var rawString: String {
		return textStorage.string.replacingOccurrences(of: "\u{0ffe}", with: "")
	}
	
	public var debugDescription: String { return "RmdDocument with \(chunks.count) chunks" }
	
	/// types of ranges that can be requested
	public enum RangeType: Int {
		/// the contents without delimiters, arguments, etc.
		case inner
		/// the full contents of the chunk, including delimiters
		case outer
	}
	
	/// Creates a structure document.
	///
	/// - Parameters:
	///   - contents: Initial contents of the document.
	///   - helpCallback: Callback that returns true if a term should be highlighted as a help term.
	public init(contents: String, helpCallback: HelpCallback? = nil) throws {
		textStorage.append(NSAttributedString(string: contents))
		let pchunks = try parser.parse(input: contents)
		for (idx, aChunk) in pchunks.enumerated() {
			chunks.append(RmdDocChunk(rawChunk: aChunk, number: idx, parentRange: aChunk.range))
		}
	}
	
	/// Returns the contents of chunk as a String
	/// - Parameter chunk: The chunk whose ccntent will be returned
	/// - Parameter type: Which range should be used. Defaults to .outer
	/// - Returns: the requested contents
	public func string(for chunk: RmdDocumentChunk, type: RangeType = .outer) -> String {
		return attrString(for: chunk, rangeType: type).string.replacingOccurrences(of: "\u{0ffe}", with: "")
	}
	
	/// Returns the contents of chunk as an NSAttributedString
	/// - Parameter chunk: The chunk whose ccntent will be returned
	/// - Parameter type: Which range should be used. Defaults to .outer
	/// - Returns: the requested contents
	public func attrtibutedString(for chunk: RmdDocumentChunk, type: RangeType = .outer) -> NSAttributedString {
		return attrString(for: chunk, rangeType: .inner)
	}
	
	/// internal method to reduce code duplication of bounds checking
	private func attrString(for chunk: RmdDocumentChunk, rangeType: RangeType) -> NSAttributedString {
		guard let realChunk = chunk as? RmdDocChunk,
			let tmpChunk = chunks.element(at: realChunk.chunkNumber),
			let pChunk = tmpChunk as? RmdDocChunk,
			realChunk == pChunk
			else { fatalError("invalid chunk index") }
		let desiredString = textStorage.attributedSubstring(from: rangeType == .outer ? realChunk.chunkRange : realChunk.innerRange)
		if chunk.isExecutable {
			let baseStr = NSMutableAttributedString(attributedString: desiredString)
			do {
				try parser.highlight(content: baseStr)
			} catch {
				parserLog.info("error highligthing R code: \(error.localizedDescription)")
			}
			return baseStr
		}
		return desiredString
	}
}

/// A chunk in a document
public protocol RmdDocumentChunk {
	/// tye type of the chunk (.markdown, .code, .equation)
	var chunkType: ChunkType { get }
	/// true if a n inline code or equation chunk
	var isInline: Bool { get }
	/// trrue if it is a code module that can be executed
	var isExecutable: Bool { get }
	/// for .markdown chunks, any inline chunks. an empty arrary for other chunk types
	var children: [RmdDocumentChunk] { get }
}

internal class RmdDocChunk: RmdDocumentChunk {
	let chunkType: ChunkType
	private let parserChunk: AnyChunk
	let chunkNumber: Int
	public private(set) var children = [RmdDocumentChunk]()
	
	init(rawChunk: AnyChunk, number: Int, parentRange: NSRange) {
		chunkType = ChunkType(rawChunk.type)
		parserChunk = rawChunk
		chunkNumber = number
		parsedRange = rawChunk.range
		innerRange = rawChunk.innerRange
		if rawChunk.isInline {
			chunkRange = NSRange(location: parsedRange.location - parentRange.location,
								 length: parsedRange.length)
		} else {
			chunkRange = parsedRange
		}
		if let mchunk = rawChunk.asMarkdown {
			// need to add inline chunks
			var i = 0
			mchunk.inlineChunks.forEach { ichk in
				children.append(RmdDocChunk(rawChunk: ichk, number: i, parentRange: parsedRange))
				i += 1
			}
		}
		if rawChunk.type == .code {
			// FIXME: set name and argument
		}
	}
	
	/// true if this is a code or inline code chunk
	public var isExecutable: Bool { return chunkType == .code || parserChunk.type == .inlineCode }
	/// trtue if this is an inline chunk
	public var isInline: Bool { return parserChunk.isInline }
	/// the range of this chunk in the entire document
	public let parsedRange: NSRange
	/// the range of the content (without open/close markers)
	public let innerRange: NSRange
	/// If an inline chunk, the range of this chunk inside the parent markdown chunk.
	/// Otherwise, the same a parsedRange
	public let chunkRange: NSRange
	// if this is a .code chunk, the argument in the chunk header
	public private(set) var arguments: String?
	// if this is a code chunk, the name given to the chunk
	public private(set) var name: String?
	
	public var executableCode: String {
		guard isExecutable else { return "" }
		if let cchunk = parserChunk.asCode { return cchunk.code }
		if let icc = parserChunk.asInlineCode { return icc.code }
		fatalError("not possible")
	}
}

extension RmdDocChunk: Equatable {
	static func == (lhs: RmdDocChunk, rhs: RmdDocChunk) -> Bool {
		return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
	}
}
