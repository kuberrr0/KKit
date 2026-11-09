import Foundation
import Observation
import os

/// Every command from KKit itself and from each running feature.
///
/// The `FeatureManager` registers a feature's commands when it starts and removes them
/// when it stops; hosts read from here (Settings › Shortcuts, Floating Bar) and the
/// hotkey service observes changes to bind and unbind shortcuts.
@MainActor
@Observable
public final class CommandRegistry {
    public enum Change: Sendable, Hashable {
        case added([CommandID])
        case removed([CommandID])
    }

    public enum RegistryError: LocalizedError, Equatable {
        case unknownCommand(CommandID)
        case commandDisabled(CommandID)

        public var errorDescription: String? {
            switch self {
            case .unknownCommand(let id): String(localized: "No command named \(id.rawValue).")
            case .commandDisabled(let id): String(localized: "\(id.rawValue) can't run right now.")
            }
        }
    }

    public private(set) var commands: [CommandID: Command] = [:]

    @ObservationIgnored private var owners: [FeatureID: [CommandID]] = [:]
    @ObservationIgnored private var observers: [UUID: @MainActor (Change) -> Void] = [:]
    private let log = KKitLog.logger("commands")

    public init() {}

    /// Adds `newCommands` for `owner`. Commands whose id doesn't start with
    /// `<owner>.`, or whose id is already taken, are skipped and logged.
    /// - Returns: the ids that were added.
    @discardableResult
    public func register(_ newCommands: [Command], owner: FeatureID) -> [CommandID] {
        var added: [CommandID] = []
        for command in newCommands {
            guard command.id.featureID == owner, !command.id.verb.isEmpty else {
                log.error("Skipping command \(command.id.rawValue, privacy: .public): id must be \(owner.rawValue, privacy: .public).<verb>")
                continue
            }
            guard commands[command.id] == nil else {
                log.error("Skipping duplicate command \(command.id.rawValue, privacy: .public)")
                continue
            }
            commands[command.id] = command
            added.append(command.id)
        }
        guard !added.isEmpty else { return [] }
        owners[owner, default: []].append(contentsOf: added)
        notify(.added(added))
        return added
    }

    /// Removes every command `owner` registered.
    public func unregister(owner: FeatureID) {
        guard let ids = owners.removeValue(forKey: owner), !ids.isEmpty else { return }
        for id in ids {
            commands[id] = nil
        }
        notify(.removed(ids))
    }

    public func command(_ id: CommandID) -> Command? {
        commands[id]
    }

    public func commands(owner: FeatureID) -> [Command] {
        (owners[owner] ?? []).compactMap { commands[$0] }
    }

    /// All commands, sorted by title.
    public var allCommands: [Command] {
        commands.values.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    public func perform(_ id: CommandID, _ invocation: CommandInvocation = .init()) async throws {
        guard let command = commands[id] else { throw RegistryError.unknownCommand(id) }
        guard command.isEnabled() else { throw RegistryError.commandDisabled(id) }
        log.debug("Running \(id.rawValue, privacy: .public)")
        try await command.perform(invocation)
    }

    /// Calls `handler` on every change. Keep the returned id to remove it.
    @discardableResult
    public func addObserver(_ handler: @escaping @MainActor (Change) -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        return id
    }

    public func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    private func notify(_ change: Change) {
        for handler in observers.values {
            handler(change)
        }
    }
}
