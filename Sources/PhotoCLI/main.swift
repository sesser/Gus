import Foundation
import PhotoCore

// A thin dispatcher: the commands, their schemas and the output contract live
// in PhotoCore (`CommandRegistry`, `CommandLineInterface`).
let environment = CommandEnvironment(currentDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath,
                                                           isDirectory: true))
let output = await CommandLineInterface(environment: environment).run(Array(CommandLine.arguments.dropFirst()))
FileHandle.standardOutput.write(Data(output.standardOutput.utf8))
FileHandle.standardError.write(Data(output.standardError.utf8))
exit(output.exitCode)
