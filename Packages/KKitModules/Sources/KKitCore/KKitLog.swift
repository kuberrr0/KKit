import os

/// One log subsystem for the whole app; one category per feature or module.
/// Filter in Console.app with `subsystem:com.kv.kkit`.
public enum KKitLog {
    public static let subsystem = "com.kv.kkit"

    public static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
