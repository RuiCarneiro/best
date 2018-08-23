//  Copyright © 2018 Rui Carneiro. All rights reserved.

import Darwin
import Foundation

// MARK: - Exit

enum Exit {
    case normal, walkOptionWithoutFileOrDirectoryOption, noArgument, invalidOption(option: Character), noResult

    var code: Int32 {
        switch self {
        case .normal: return 0
        case .walkOptionWithoutFileOrDirectoryOption, .noArgument, .invalidOption(option: _):
            return POSIXError.EINVAL.rawValue
        case .noResult: return 1
        }
    }

    func exit() {
        switch self {
        case .walkOptionWithoutFileOrDirectoryOption: printError("Option -w requires option -f and/or option -d.")
        case .noArgument: printError("Missing argument."); printUsage()
        case .invalidOption(option: let c): printError("Invalid option: \(c)"); printUsage()
        case .normal: ()
        case .noResult: ()
        }

        Darwin.exit(self.code)
    }
}

// MARK: - Prints

func printError(_ message: String) {
    fputs("\(message)\n\r", stderr)
}

func printUsage() {
    print("usage: best [-fdwpecrsi] argument")
}

// MARK: - Process Command Line Arguments

enum OperatingMode {
    case stdin, files
}

struct Options {
    var operatingMode: OperatingMode {
        return (!includeFiles && !includeDirectories && !walkSubDirs) ? .stdin : .files
    }
    var includeFiles: Bool = false
    var includeDirectories: Bool = false
    var walkSubDirs: Bool = false
    var printFullPath: Bool = false
    var quitWithErrorIfNoResultsFound: Bool = false
    var replaceDotsWithSpaces: Bool = false
    var caseSentitive: Bool = false
    var removeWhiteSpace: Bool = false
    var ignoreCandidatesThatDontContainTheArgument: Bool = false
}

func getOptions() -> Options {
    var temp = Options()
    let args = CommandLine.arguments.dropFirst()
    let argumentsWithHyphenPrefix = args.filter { (arg) -> Bool in
        return arg.hasPrefix("-")
    }

    for argument in argumentsWithHyphenPrefix {
        let argumentWithoutHyphen = argument.dropFirst()
        for character in argumentWithoutHyphen {
            switch character {
            case "f": temp.includeFiles = true
            case "d": temp.includeDirectories = true
            case "w": temp.walkSubDirs = true
            case "p": temp.printFullPath = true
            case "e": temp.quitWithErrorIfNoResultsFound = true
            case "c": temp.caseSentitive = true
            case "r": temp.replaceDotsWithSpaces = true
            case "s": temp.removeWhiteSpace = true
            case "i": temp.ignoreCandidatesThatDontContainTheArgument = true
            default: Exit.invalidOption(option: character).exit()
            }
        }
    }

    // Check the validity of options
    if temp.walkSubDirs {
        if !(temp.includeFiles || temp.includeDirectories) {
            Exit.walkOptionWithoutFileOrDirectoryOption.exit()
        }
    }

    return temp
}

func getArgument() -> String? {
    func _getArgument() -> String? {
        let args = CommandLine.arguments.dropFirst()

        let argumentsWithoutHypenPrefix = args.filter { (arg) -> Bool in
            return !arg.hasPrefix("-")
        }

        if argumentsWithoutHypenPrefix.isEmpty {
            return nil
        } else if argumentsWithoutHypenPrefix.count == 1 {
            return argumentsWithoutHypenPrefix[0]
        } else {
            return argumentsWithoutHypenPrefix.joined(separator: " ")
        }
    }

    if let arg = _getArgument() {
        return options.caseSentitive ? arg : arg.lowercased()
    } else {
        return nil
    }
}

// MARK: - Init

struct Candidate {
    var value: String
    var distance: Int
}

let options = getOptions()
let argument = getArgument()
var best: Candidate?

// MARK: - Helper functions

// executes loop while the return of the condition is not nil
// TODO: better doc
func whileNotNil<T>(_ condition: () -> T?, _ loop: (T) -> Void) {
    var foo = condition()
    while foo != nil {
        if let bar = foo {
            loop(bar)
        }
        foo = condition()
    }
}

// replaces the current candiadate if the new one is better or the old one is nil
func replaceIfBetterCandidate(old: inout Candidate?, new: Candidate) {
    if let o = old {
        let oldDist = o.distance
        let newDist = new.distance

        if newDist < oldDist {
            old = new
        }
    } else {
        old = new
    }
}

// process a input string according to the options speccified
func processString(_ str: String) -> String {
    var out = str

    if options.caseSentitive {
        out = out.lowercased()
    }

    if options.replaceDotsWithSpaces {
        out = out.replacingOccurrences(of: ".", with: " ")
    }

    if options.removeWhiteSpace {
        out = out.trimmingCharacters(in: .whitespaces)
    }

    return out
}

// determines if line should be accepted
func shouldAcceptLine(_ str: String) -> Bool {
    if options.ignoreCandidatesThatDontContainTheArgument {
        if !str.contains(argument!) {
            return false
        }
    }
    return true
}

// MARK: - Main

guard let argument = argument else {
    Exit.noArgument.exit()
    fatalError()
}

guard !argument.isEmpty else {
    Exit.noArgument.exit()
    fatalError()
}

if options.operatingMode == .stdin {
    // stdin mode

    whileNotNil({ return readLine(strippingNewline: true) }) {
        let newString = processString($0)

        if shouldAcceptLine(newString) {
            let newDist = argument.levenshtein(newString)
            let newCandidate = Candidate(value: $0, distance: newDist)

            replaceIfBetterCandidate(old: &best, new: newCandidate)
        }
    }

} else {
    // file mode
    let fm = FileManager.default
    let currentDirectory = fm.currentDirectoryPath

    func fillFiles(_ directory: String) -> [String] {
        do {
            if options.walkSubDirs {
                return try fm.subpathsOfDirectory(atPath: currentDirectory)
            } else {
                return try fm.contentsOfDirectory(atPath: currentDirectory)
            }
        } catch {
            fatalError(error.localizedDescription)
        }
    }

    var contents: [String] = fillFiles(currentDirectory)

    let includeBothFilesAndDirs = options.includeDirectories && options.includeFiles
    if !includeBothFilesAndDirs {
        contents = contents.filter { (item) -> Bool in
            let isDir = fm.isDirectory(atPath: item)
            let isFile = !isDir

            if options.includeDirectories {
                return isDir
            } else {
                return isFile
            }
        }
    }

    for item in contents {
        let newString = processString(item)

        if shouldAcceptLine(newString) {
            let newDistance = argument.levenshtein(newString)
            let dir = currentDirectory == "/" ? currentDirectory : currentDirectory + "/"
            let newPath = options.printFullPath ? dir + item : item
            let newCandidate = Candidate(value: newPath, distance: newDistance)

            replaceIfBetterCandidate(old: &best, new: newCandidate)
        }
    }
}

// present the result

if let b = best {
    print(b.value)
    Exit.normal.exit()
} else {
    if options.quitWithErrorIfNoResultsFound {
        Exit.noResult.exit()
    } else {
        Exit.normal.exit()
    }
}
