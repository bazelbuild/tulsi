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

public final class TaskRunner {

  /// Information retrieved through execution of a task.
  public struct CompletionInfo {
    /// The task that was executed.
    public let task: NSTask

    /// The commandline that was executed, suitable for pasting in terminal to reproduce.
    public let commandlineString: String
    /// The task's standard output.
    public let stdout: NSData
    /// The task's standard error.
    public let stderr: NSData

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
  private var pendingTasks = Set<NSTask>()
  private let taskReader: TaskOutputReader

  public static func standardRunner() -> TaskRunner {
    return defaultInstance
  }

  /// Prepares an NSTask using the given launch binary with the given arguments that will collect
  // output and passing it to a terminationHandler.
  public func createTask(launchPath: String,
                         arguments: [String]? = nil,
                         terminationHandler: CompletionHandler) -> NSTask {

    func doOnMainThread(block: () -> Void) {
      if NSThread.isMainThread() {
        block()
      } else {
        dispatch_sync(dispatch_get_main_queue(), block)
      }
    }

    let task = NSTask()
    task.launchPath = launchPath
    task.arguments = arguments

    let dispatchGroup = dispatch_group_create()
    let notificationCenter = NSNotificationCenter.defaultCenter()
    func registerAndStartReader(fileHandle: NSFileHandle, outputData: NSMutableData) -> NSObjectProtocol {
      let observer = notificationCenter.addObserverForName(NSFileHandleReadToEndOfFileCompletionNotification,
                                                           object: fileHandle,
                                                           queue: nil) { (notification: NSNotification) in
        defer { dispatch_group_leave(dispatchGroup) }
        if let err = notification.userInfo?["NSFileHandleError"] as? NSNumber {
          assertionFailure("Read from pipe failed with error \(err)")
        }
        guard let data = notification.userInfo?[NSFileHandleNotificationDataItem] as? NSData else {
          assertionFailure("Unexpectedly received no data in read handler")
          return
        }
        outputData.appendData(data)
      }

      dispatch_group_enter(dispatchGroup)

      // The docs for readToEndOfFileInBackgroundAndNotify are unclear as to exactly what work is
      // done on the calling thread. By observation, it appears that data will not be read if the
      // main queue is in event tracking mode.
      fileHandle.performSelector(Selector("readToEndOfFileInBackgroundAndNotify"),
                                 onThread: taskReader.thread,
                                 withObject: nil,
                                 waitUntilDone: true)
      return observer
    }

    let stdoutData = NSMutableData()
    task.standardOutput = NSPipe()
    let stdoutObserver = registerAndStartReader(task.standardOutput!.fileHandleForReading,
                                                outputData: stdoutData)
    let stderrData = NSMutableData()
    task.standardError = NSPipe()
    let stderrObserver = registerAndStartReader(task.standardError!.fileHandleForReading,
                                                outputData: stderrData)

    task.terminationHandler = { (task: NSTask) -> Void in
      // The termination handler's thread is used to allow the caller's callback to do off-main work
      // as well.
      assert(!NSThread.isMainThread(),
             "Task termination handler unexpectedly called on main thread.")
      dispatch_group_wait(dispatchGroup, DISPATCH_TIME_FOREVER)

      // Construct a string suitable for cutting and pasting into the commandline.
      let commandlineArguments: String
      if let arguments = arguments {
        commandlineArguments = " " + arguments.map({ "\"\($0)\"" }).joinWithSeparator(" ")
      } else {
        commandlineArguments = ""
      }
      let commandlineRunnableString = "\"\(task.launchPath!)\"\(commandlineArguments)"
      terminationHandler(CompletionInfo(task: task,
                                        commandlineString: commandlineRunnableString,
                                        stdout: stdoutData,
                                        stderr: stderrData))

      doOnMainThread {
        notificationCenter.removeObserver(stdoutObserver)
        notificationCenter.removeObserver(stderrObserver)
        assert(self.pendingTasks.contains(task), "terminationHandler called with unexpected task")
        self.pendingTasks.remove(task)
      }
    }

    doOnMainThread {
      self.pendingTasks.insert(task)
    }
    return task
  }

  // MARK: - Private methods

  private init() {
    taskReader = TaskOutputReader()
    taskReader.start()
  }

  deinit {
    taskReader.stop()
  }


  // MARK: - TaskOutputReader

  // Provides a thread/runloop that may be used to read NSTask output pipes.
  private class TaskOutputReader: NSObject {
    lazy var thread: NSThread = {
      let value = NSThread(target: self, selector: Selector("threadMain:"), object: nil)
      value.name = "com.google.Tulsi.TaskOutputReader"
      return value
    }()

    private var continueRunning = false

    func start() {
      assert(!thread.executing, "Start called twice without a stop")
      thread.start()
    }

    func stop() {
      performSelector(Selector("stopThread"), onThread:thread, withObject:nil, waitUntilDone: false)
    }

    // MARK: - Private methods

    @objc
    private func threadMain(object: AnyObject) {
      let runLoop = NSRunLoop.currentRunLoop()
      // Add a dummy port to prevent the runloop from returning immediately.
      runLoop.addPort(NSMachPort(), forMode: NSDefaultRunLoopMode)

      while !thread.cancelled {
        runLoop.runMode(NSDefaultRunLoopMode, beforeDate: NSDate.distantFuture())
      }
    }

    @objc
    private func stopThread() {
      thread.cancel()
    }
  }
}
