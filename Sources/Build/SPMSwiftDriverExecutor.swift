/*
 This source file is part of the Swift.org open source project

 Copyright 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_implementationOnly import SwiftDriver
import TSCBasic
import Foundation

final class SPMSwiftDriverExecutor: DriverExecutor {

  private enum Error: Swift.Error, DiagnosticData {
    case inPlaceExecutionUnsupported

    var description: String {
      switch self {
      case .inPlaceExecutionUnsupported:
        return "the integrated Swift driver does not support in-place execution"
      }
    }
  }

  let resolver: ArgsResolver
  let fileSystem: FileSystem
  let env: [String: String]

  init(resolver: ArgsResolver,
       fileSystem: FileSystem,
       env: [String: String]) {
    self.resolver = resolver
    self.fileSystem = fileSystem
    self.env = env
  }

  func execute(job: Job,
               forceResponseFiles: Bool,
               recordedInputModificationDates: [TypedVirtualPath : Date]) throws -> ProcessResult {
    let arguments: [String] = try resolver.resolveArgumentList(for: job,
                                                               forceResponseFiles: forceResponseFiles)

    try job.verifyInputsNotModified(since: recordedInputModificationDates,
                                    fileSystem: fileSystem)
    
    if job.requiresInPlaceExecution {
      throw Error.inPlaceExecutionUnsupported
    }

    var childEnv = env
    childEnv.merge(job.extraEnvironment, uniquingKeysWith: { (_, new) in new })

    let process = try Process.launchProcess(arguments: arguments, env: childEnv)
    return try process.waitUntilExit()
  }

  func execute(jobs: [Job], delegate: JobExecutionDelegate,
               numParallelJobs: Int, forceResponseFiles: Bool,
               recordedInputModificationDates: [TypedVirtualPath : Date]) throws {
    fatalError("Multi-job build plans should be lifted into the SPM build graph.")
  }

  func checkNonZeroExit(args: String..., environment: [String : String]) throws -> String {
    return try Process.checkNonZeroExit(arguments: args, environment: environment)
  }

  func description(of job: Job, forceResponseFiles: Bool) throws -> String {
    // FIXME: This is duplicated from SwiftDriver, maybe it shouldn't be a protocol requirement.
    let (args, usedResponseFile) = try resolver.resolveArgumentList(for: job,
                                                                    forceResponseFiles: forceResponseFiles)
    var result = args.joined(separator: " ")

    if usedResponseFile {
      // Print the response file arguments as a comment.
      result += " # \(job.commandLine.joinedArguments)"
    }

    if !job.extraEnvironment.isEmpty {
      result += " #"
      for (envVar, val) in job.extraEnvironment {
        result += " \(envVar)=\(val)"
      }
    }
    return result
  }
}
