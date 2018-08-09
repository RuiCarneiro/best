//  Copyright © 2018 Rui Carneiro. All rights reserved.

import Foundation
import Darwin

// MARK: - Exit

enum Exit {
    case normal, walkOptionWithoutFileOrDirectoryOption, noArgument, invalidOption(option: Character), noResult

    var code : Int32 {
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
        default: ()
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
    var operatingMode : OperatingMode {
        return (!includeFiles && !includeDirectories && !walkSubDirs) ? .stdin : .files
    }
    var includeFiles : Bool = false
    var includeDirectories : Bool = false
    var walkSubDirs : Bool = false
    var printFullPath : Bool = false
    var quitWithErrorIfNoResultsFound : Bool = false
    var replaceDotsWithSpaces : Bool = false
    var caseSentitive : Bool = false
    var removeWhiteSpace : Bool = false
    var ignoreCandidatesThatDontContainTheArgument : Bool = false
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

func _getArgument() -> String? {
    let args = CommandLine.arguments.dropFirst()

    let argumentsWithoutHypenPrefix = args.filter { (arg) -> Bool in
        return !arg.hasPrefix("-")
    }

    if argumentsWithoutHypenPrefix.count == 0 {
        return nil
    }
    else if argumentsWithoutHypenPrefix.count == 1 {
        return argumentsWithoutHypenPrefix[0]
    }
    else {
        return argumentsWithoutHypenPrefix.joined(separator: " ")
    }
}

func getArgument() -> String? {
    if let arg = _getArgument() {
        return options.caseSentitive ? arg : arg.lowercased()
    }
    else {
        return nil
    }
}

// MARK: - Init

struct Candidate {
    var value : String
    var distance : Int
}

let options = getOptions()
let argument = getArgument()
var best : Candidate?

// MARK: - Main

// process the input string according to the options speccified
func processString(_ str: String) -> String {
    let a = options.caseSentitive ? str : str.lowercased()
    let b = options.replaceDotsWithSpaces ? a.replacingOccurrences(of: ".", with: " ") : a
    let c = options.removeWhiteSpace ? b.trimmingCharacters(in: CharacterSet.whitespaces) : b
    return c
}

guard let argument = argument else {
    Exit.noArgument.exit()
    fatalError()
}

guard argument.count > 0 else {
    Exit.noArgument.exit()
    fatalError()
}

if options.operatingMode == .stdin {
    // stdin mode
    var newLine: String? = "" // not nil
    while newLine != nil {
        newLine = readLine(strippingNewline: true)

        if let nl = newLine {
            let newString = processString(nl)

            var skipThisOne = false
            if options.ignoreCandidatesThatDontContainTheArgument {
                if !newString.contains(argument) {
                    skipThisOne = true
                }
            }

            if !skipThisOne {
                let newDist = argument.levenshtein(newString)
                let newCandidate = Candidate(value: newLine!, distance: newDist)

                if let b = best {
                    let oldDist = b.distance

                    if newDist < oldDist {
                        best = newCandidate
                    }
                }
                else {
                    best = newCandidate
                }
            }
        }
    }
}
else {
    // file mode
    let fm = FileManager.default
    let currentDirectory = fm.currentDirectoryPath

    func fillFiles(_ directory: String) -> [String] {
        if options.walkSubDirs {
            return try! fm.subpathsOfDirectory(atPath: currentDirectory)
        }
        else {
            return try! fm.contentsOfDirectory(atPath: currentDirectory)
        }
    }

    var contents : [String] = fillFiles(currentDirectory)

    contents = contents.filter({ (item) -> Bool in
        let isDir = fm.isDirectory(atPath: item)

        return isDir ? options.includeDirectories : options.includeFiles

    })

    for item in contents {
        let newString = processString(item)

        var skipThisOne = false
        if options.ignoreCandidatesThatDontContainTheArgument {
            if !newString.contains(argument) {
                skipThisOne = true
            }
        }

        if !skipThisOne {
            let newDistance = argument.levenshtein(newString)
            let dir = currentDirectory == "/" ? currentDirectory : currentDirectory + "/"
            let newPath = options.printFullPath ? dir + item : item
            let itemCandidate = Candidate(value: newPath, distance: newDistance)


            if let b = best {
                if newDistance < b.distance {
                    best = itemCandidate
                }
            }
            else {
                best = itemCandidate
            }
        }
    }

}



// present the result

if let b = best {
    print(b.value)
}
else {
    if options.quitWithErrorIfNoResultsFound {
        Exit.noResult.exit()
    }
}

Exit.normal.exit()
