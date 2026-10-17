import Foundation

// Propagate cancellation into detached CPU/file work; never publish its late result.
enum LocalWorker {
  static func run<T>(priority: TaskPriority = .userInitiated, _ operation: @escaping @Sendable () throws -> T) async throws -> T {
    try Task.checkCancellation()
    let worker = Task.detached(priority: priority) { try Task.checkCancellation(); return try operation() }
    return try await withTaskCancellationHandler(operation: {
      let result = try await worker.value
      try Task.checkCancellation()
      return result
    }, onCancel: { worker.cancel() })
  }
}
