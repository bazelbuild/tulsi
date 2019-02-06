// Copyright 2016 The Tulsi Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation


/// Encapsulates functionality to launch and manage Processes.
public final class ProcessRunner {

  /// Information retrieved through execution of a process.
  public struct CompletionInfo {
    /// The process that was executed.
    public let process: Process

    /// The commandline that was executed, suitable for pasting in terminal to reproduce.
    public let commandlineString: String
    /// The process's standard output.
    public let stdout: Data
    /// The process's standard error.
    public let stderr: Data

    /// The exit status for the process.
    public var terminationStatus: Int32 {
      return process.terminationStatus
    }
  }

  /// Coordinates logging with Process lifetime to accurately report when a given process started.
  final class TimedProcessRunnerObserver: NSObject {
    /// Context for KVO
    private static var KVOContext: Int = 0

    /// Mapping between Processes and LogSessionHandles created for each.
    private var pendingLogHandles = Dictionary<Process, LocalizedMessageLogger.LogSessionHandle>()

    /// Start logging the given Process with KVO to determine the time when it starts running.
    fileprivate func startLoggingProcessTime(process: Process,
                                             loggingIdentifier: String,
                                             messageLogger: LocalizedMessageLogger) {
      self.pendingLogHandles[process] = messageLogger.startProfiling(loggingIdentifier)
      process.addObserver(self,
                          forKeyPath: #keyPath(Process.isRunning),
                          options: .new,
                          context: &TimedProcessRunnerObserver.KVOContext)
    }

    /// Report the time this process has taken, and cleanup its logging handle and KVO observer.
    fileprivate func stopLogging(process: Process, messageLogger: LocalizedMessageLogger) {
      if let logHandle = self.pendingLogHandles[process] {
        messageLogger.logProfilingEnd(logHandle)
        process.removeObserver(self,
                               forKeyPath: #keyPath(Process.isRunning),
                               context: &TimedProcessRunnerObserver.KVOContext)
        self.pendingLogHandles.removeValue(forKey: process)
      }
    }

    /// KVO to set the logger start time to the moment when the Process indicates that it's running.
    override public func observeValue(forKeyPath keyPath: String?,
                                      of object: Any?,
                                      change: [NSKeyValueChangeKey : Any]?,
                                      context: UnsafeMutableRawPointer?) {
      if context != &TimedProcessRunnerObserver.KVOContext {
        super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        return
      }

      if keyPath == #keyPath(Process.isRunning),
          let newValue = change?[NSKeyValueChangeKey.newKey] as? NSNumber,
          newValue.boolValue,
          let process = object as? Process {
        pendingLogHandles[process]?.resetStartTime()
      }
    }
  }


  public typealias CompletionHandler = (CompletionInfo) -> Void

  private static var defaultInstance: ProcessRunner = {
    ProcessRunner()
  }()

  /// The outstanding processes.
  private var pendingProcesses = Set<Process>()
  private let processReader: ProcessOutputReader


  /// Handle KVO around processes to determine when a process starts running.
  private let timedProcessRunnerObserver = TimedProcessRunnerObserver()


  /// Prepares a Process using the given launch binary with the given arguments that will collect
  /// output and passing it to a terminationHandler.
  static func createProcess(_ launchPath: String,
                            arguments: [String],
                            environment: [String: String]? = nil,
                            messageLogger: LocalizedMessageLogger? = nil,
                            loggingIdentifier: String? = nil,
                            terminationHandler: @escaping CompletionHandler) -> Process {
    return defaultInstance.createProcess(launchPath,
                                         arguments: arguments,
                                         environment: environment,
                                         messageLogger: messageLogger,
                                         loggingIdentifier: loggingIdentifier,
                                         terminationHandler: terminationHandler)
  }

  /// Creates and launches a Process using the given launch binary with the given arguments that
  /// will run synchronously to completion and return a CompletionInfo.
  static func launchProcessSync(_ launchPath: String,
                                arguments: [String],
                                environment: [String: String]? = nil,
                                messageLogger: LocalizedMessageLogger? = nil,
                                loggingIdentifier: String? = nil) -> CompletionInfo {
    let semaphore = DispatchSemaphore(value: 0)
    var completionInfo: CompletionInfo! = nil
    let process = defaultInstance.createProcess(launchPath,
                                                arguments: arguments,
                                                environment: environment,
                                                messageLogger: messageLogger,
                                                loggingIdentifier: loggingIdentifier) {
      processCompletionInfo in
        completionInfo = processCompletionInfo
        semaphore.signal()
    }

    process.launch()
    _ = semaphore.wait(timeout: DispatchTime.distantFuture)
    return completionInfo
  }

  // MARK: - Private methods

  private init() {
    processReader = ProcessOutputReader()
    processReader.start()
  }

  deinit {
    processReader.stop()
  }

  private func createProcess(_ launchPath: String,
                             arguments: [String],
                             environment: [String: String]? = nil,
                             messageLogger: LocalizedMessageLogger? = nil,
                             loggingIdentifier: String? = nil,
                             terminationHandler: @escaping CompletionHandler) -> Process {
    let process = Process()
    process.launchPath = launchPath
    process.arguments = arguments
    if let environment = environment {
      process.environment = environment
    }
    // Construct a string suitable for cutting and pasting into the commandline.
    let commandlineArguments = arguments.map { $0.escapingForShell }.joined(separator: " ")
    let commandlineRunnableString = "\(launchPath.escapingForShell) \(commandlineArguments)"

    // If the localizedMessageLogger was passed as an arg, start logging the runtime of the process.
    if let messageLogger = messageLogger {
      timedProcessRunnerObserver.startLoggingProcessTime(process: process,
                                                         loggingIdentifier: (loggingIdentifier ?? launchPath),
                                                         messageLogger: messageLogger)
      messageLogger.infoMessage("Running \(commandlineRunnableString)")
    }

    let dispatchGroup = DispatchGroup()
    let notificationCenter = NotificationCenter.default
    func registerAndStartReader(_ fileHandle: FileHandle, outputData: NSMutableData) -> NSObjectProtocol {
      let observer = notificationCenter.addObserver(forName: NSNotification.Name.NSFileHandleReadToEndOfFileCompletion,
                                                    object: fileHandle,
                                                    queue: nil) { (notification: Notification) in
        defer { dispatchGroup.leave() }
        if let err = notification.userInfo?["NSFileHandleError"] as? NSNumber {
          assertionFailure("Read from pipe failed with error \(err)")
        }
        guard let data = notification.userInfo?[NSFileHandleNotificationDataItem] as? Data else {
          assertionFailure("Unexpectedly received no data in read handler")
          return
        }
        outputData.append(data)
      }

      dispatchGroup.enter()

      // The docs for readToEndOfFileInBackgroundAndNotify are unclear as to exactly what work is
      // done on the calling thread. By observation, it appears that data will not be read if the
      // main queue is in event tracking mode.
      let selector = #selector(FileHandle.readToEndOfFileInBackgroundAndNotify as (FileHandle) -> () -> Void)
      fileHandle.perform(selector, on: processReader.thread, with: nil, waitUntilDone: true)
      return observer
    }

    let stdoutData = NSMutableData()
    process.standardOutput = Pipe()
    let stdoutObserver = registerAndStartReader((process.standardOutput! as AnyObject).fileHandleForReading,
                                                outputData: stdoutData)
    let stderrData = NSMutableData()
    process.standardError = Pipe()
    let stderrObserver = registerAndStartReader((process.standardError! as AnyObject).fileHandleForReading,
                                                outputData: stderrData)

    process.terminationHandler = { (process: Process) -> Void in
      // The termination handler's thread is used to allow the caller's callback to do off-main work
      // as well.
      assert(!Thread.isMainThread,
             "Process termination handler unexpectedly called on main thread.")
      _ = dispatchGroup.wait(timeout: DispatchTime.distantFuture)

      // If the localizedMessageLogger was an arg, report total runtime of this process + cleanup.
      if let messageLogger = messageLogger {
        self.timedProcessRunnerObserver.stopLogging(process: process, messageLogger: messageLogger)
      }

      terminationHandler(CompletionInfo(process: process,
                                        commandlineString: commandlineRunnableString,
                                        stdout: stdoutData as Data,
                                        stderr: stderrData as Data))

      Thread.doOnMainQueue {
        notificationCenter.removeObserver(stdoutObserver)
        notificationCenter.removeObserver(stderrObserver)
        assert(self.pendingProcesses.contains(process), "terminationHandler called with unexpected process")
        self.pendingProcesses.remove(process)
      }
    }

    Thread.doOnMainQueue {
      self.pendingProcesses.insert(process)
    }
    return process
  }


  // MARK: - ProcessOutputReader

  // Provides a thread/runloop that may be used to read Process output pipes.
  private class ProcessOutputReader: NSObject {
    lazy var thread: Thread = { [unowned self] in
      let value = Thread(target: self, selector: #selector(threadMain(_:)), object: nil)
      value.name = "com.google.Tulsi.ProcessOutputReader"
      return value
    }()

    private var continueRunning = false

    func start() {
      assert(!thread.isExecuting, "Start called twice without a stop")
      thread.start()
    }

    func stop() {
      perform(#selector(ProcessOutputReader.stopThread),
                        on:thread,
                        with:nil,
                        waitUntilDone: false)
    }

    // MARK: - Private methods

    @objc
    private func threadMain(_ object: AnyObject) {
      let runLoop = RunLoop.current
      // Add a dummy port to prevent the runloop from returning immediately.
      runLoop.add(NSMachPort(), forMode: RunLoop.Mode.default)

      while !thread.isCancelled {
        runLoop.run(mode: RunLoop.Mode.default, before: Date.distantFuture)
      }
    }

    @objc
    private func stopThread() {
      thread.cancel()
    }
  }
}
