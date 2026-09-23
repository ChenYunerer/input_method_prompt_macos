import Foundation
import IOKit.hid
import IOKit.hidsystem

/// Read each keyboard's lock state, independently of posted event flags.
/// Both CGEventSource and IOHIDGetModifierLockState can retain a false Caps bit.
final class CapsLockReader {
    static let shared = CapsLockReader()
    typealias KeyboardStateQuery = () -> [Bool?]?

    private let makeKeyboardQuery: () -> KeyboardStateQuery
    private let now: () -> TimeInterval
    private var readKeyboardStates: KeyboardStateQuery
    private var retryAfter: TimeInterval

    init(makeKeyboardQuery: @escaping () -> KeyboardStateQuery = CapsLockReader.makeSystemQuery,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.makeKeyboardQuery = makeKeyboardQuery
        self.now = now
        readKeyboardStates = makeKeyboardQuery()
        retryAfter = now() + 0.5
    }

    convenience init(readKeyboardStates: @escaping KeyboardStateQuery) {
        self.init(makeKeyboardQuery: { readKeyboardStates })
    }

    static func makeSystemQuery() -> KeyboardStateQuery {
        // A simple client can retain disconnected services across sleep/device
        // reconnects. Re-enumerating on that same client is not sufficient.
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        return {
            guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
                return nil
            }
            return services.filter {
                IOHIDServiceClientConformsTo($0, UInt32(kHIDPage_GenericDesktop),
                                            UInt32(kHIDUsage_GD_Keyboard)) != 0
            }.map {
                CapsLockReader.readBoolean(IOHIDServiceClientCopyProperty($0, kIOHIDServiceCapsLockStateKey as CFString))
            }
        }
    }

    func read() -> Bool? {
        var snapshot = readKeyboardStates()
        let complete = snapshot.map { !$0.isEmpty && $0.allSatisfy { $0 != nil } } ?? false
        if !complete && now() >= retryAfter {
            // Release the old client's closure and retry once with a fresh
            // client. Limit rebuilds to twice per second while unavailable.
            readKeyboardStates = makeKeyboardQuery()
            retryAfter = now() + 0.5
            snapshot = readKeyboardStates()
        }
        guard let states = snapshot, !states.isEmpty else { return nil }
        // macOS combines keyboard modifier states with OR. An idle keyboard
        // reporting false must not veto Caps Lock on another keyboard.
        if states.contains(true) { return true }
        // Missing/invalid properties are unknown, not evidence of Caps being off.
        guard states.allSatisfy({ $0 == false }) else { return nil }
        return false
    }

    static func readBoolean(_ property: CFTypeRef?) -> Bool? {
        guard let property, CFGetTypeID(property) == CFBooleanGetTypeID() else { return nil }
        return property as? Bool
    }
}
