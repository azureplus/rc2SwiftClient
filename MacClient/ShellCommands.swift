//
//  ShellCommands.swift
//  SwiftClient
//
//  Copyright © 2016 Mark Lilback. This file is licensed under the ISC license.
//

import Cocoa

///Provides wrappers for executing shell commands
public class ShellCommands {
	///executes a command returning stdout, optionally matching a capture of a regular expression
	/// - parameter for: program/script to execute
	/// - parameter arguments: array of arguments to the command. Defaults to an empty array.
	/// - parameter pattern: an optional regular expression to use to extract a value from stdout.
	/// - parameter matchNumber: the index of the grouping of pattern to return. Defaults to the entire match.
	/// - returns: stdout or the substring of stdout matching grouping matchNumber of pattern
	static func stdout(for command:String, arguments:[String] = [], pattern:String? = nil) throws -> [String]
	{
		let task:NSTask = NSTask()
		let pipe:NSPipe = NSPipe()
		task.launchPath = command
		task.arguments = arguments
		task.standardOutput = pipe
		task.launch()
		
		let handle = pipe.fileHandleForReading
		let data = handle.readDataToEndOfFile()
		let fullString = NSString(data: data, encoding: NSUTF8StringEncoding)!
		if let regexStr = pattern
		{
			let regex = try NSRegularExpression(pattern: regexStr, options: [])
			if let matchResult = regex.firstMatchInString(fullString as String, options: [], range: NSMakeRange(0, fullString.length))
			{
				var results = [String]()
				for i in 0..<matchResult.numberOfRanges {
					results.append(fullString.substringWithRange(matchResult.rangeAtIndex(i)))
				}
				return results
			}
		}
		return []
	}
	
}
