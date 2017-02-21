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


/// Encapsulates functionality to launch and manage NSTasks.
public final class TaskRunner {

  /// Information retrieved through execution of a task.
  public struct CompletionInfo {
    /// The task that was executed.
    public let task: Process

    /// The commandline that was executed, suitable for pasting in terminal to reproduce.
    public let commandlineString: String
    /// The task's standard output.
    public let stdout: Data
    /// The task's standard error.
    public let stderr: Data

    /// The exit status for the task.
    public var terminationStatus: Int32 {
      return task.terminationStatus
    }
  }


  public typealias CompletionHandler = (CompletionInfo) -> Void

  private static var defaultInstance: TaskRunner = {
    TaskRunner()
  }()

    /// The outstanding tasks.
  private var pendingTasks = Set<Process>()
  private let taskReader: TaskOutputReader

  /// Prepares an NSTask using the given launch binary with the given arguments that will collect
  /// output and passing it to a terminationHandler.
  public static func createTask(_ launchPath: String,
                         arguments: [String]? = nil,
                         environment: [String: String]? = nil,
                         terminationHandler: @escaping CompletionHandler) -> Process {
    return defaultInstance.createTask(launchPath,
                                      arguments: arguments,
                                      environment: environment,
                                      terminationHandler: terminationHandler)
  }

  // MARK: - Private methods

  private init() {
    taskReader = TaskOutputReader()
    taskReader.start()
  }

  deinit {
    taskReader.stop()
  }

  private func createTask(_ launchPath: String,
                          arguments: [String]? = nil,
                          environment: [String: String]? = nil,
                          terminationHandler: @escaping CompletionHandler) -> Process {
    let task = Process()
    task.launchPath = launchPath
    task.arguments = arguments
    if let environment = environment {
      task.environment = environment
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
      fileHandle.perform(Selector("readToEndOfFileInBackgroundAndNotify"),
                                 on: taskReader.thread,
                                 with: nil,
                                 waitUntilDone: true)
      return observer
    }

    let stdoutData = NSMutableData()
    task.standardOutput = Pipe()
    let stdoutObserver = registerAndStartReader((task.standardOutput! as AnyObject).fileHandleForReading,
                                                outputData: stdoutData)
    let stderrData = NSMutableData()
    task.standardError = Pipe()
    let stderrObserver = registerAndStartReader((task.standardError! as AnyObject).fileHandleForReading,
                                                outputData: stderrData)

    task.terminationHandler = { (task: Process) -> Void in
      // The termination handler's thread is used to allow the caller's callback to do off-main work
      // as well.
      assert(!Thread.isMainThread,
             "Task termination handler unexpectedly called on main thread.")
      dispatchGroup.wait(timeout: DispatchTime.distantFuture)

      // Construct a string suitable for cutting and pasting into the commandline.
      let commandlineArguments: String
      if let arguments = arguments {
        commandlineArguments = " " + arguments.map({ "\"\($0)\"" }).joined(separator: " ")
      } else {
        commandlineArguments = ""
      }
      let commandlineRunnableString = "\"\(task.launchPath!)\"\(commandlineArguments)"
      terminationHandler(CompletionInfo(task: task,
                                        commandlineString: commandlineRunnableString,
                                        stdout: stdoutData as Data,
                                        stderr: stderrData as Data))

      Thread.doOnMainQueue {
        notificationCenter.removeObserver(stdoutObserver)
        notificationCenter.removeObserver(stderrObserver)
        assert(self.pendingTasks.contains(task), "terminationHandler called with unexpected task")
        self.pendingTasks.remove(task)
      }
    }

    Thread.doOnMainQueue {
      self.pendingTasks.insert(task)
    }
    return task
  }


  // MARK: - TaskOutputReader

  // Provides a thread/runloop that may be used to read NSTask output pipes.
  private class TaskOutputReader: NSObject {
    lazy var thread: Thread = { [unowned self] in
      let value = Thread(target: self, selector: #selector(threadMain(_:)), object: nil)
      value.name = "com.google.Tulsi.TaskOutputReader"
      return value
    }()

    private var continueRunning = false

    func start() {
      assert(!thread.isExecuting, "Start called twice without a stop")
      thread.start()
    }

    func stop() {
      perform(#selector(TaskOutputReader.stopThread),
                      on:thread,
                      with:nil,
                      waitUntilDone: false)
    }

    // MARK: - Private methods

    @objc
    private func threadMain(_ object: AnyObject) {
      let runLoop = RunLoop.current
      // Add a dummy port to prevent the runloop from returning immediately.
      runLoop.add(NSMachPort(), forMode: RunLoopMode.defaultRunLoopMode)

      while !thread.isCancelled {
        runLoop.run(mode: RunLoopMode.defaultRunLoopMode, before: Date.distantFuture)
      }
    }

    @objc
    private func stopThread() {
      thread.cancel()
    }
  }
}
