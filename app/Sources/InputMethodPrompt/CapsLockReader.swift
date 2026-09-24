import Foundation
import IOKit.hid
import IOKit.hidsystem

/// Read each keyboard's lock state, independently of posted event flags.
/// Both CGEventSource and IOHIDGetModifierLockState can retain a false Caps bit.
final class CapsLockReader {
    static let shared = CapsLockReader()
    typealias KeyboardStateQuery = () -> [Bool?]?
    private static let clientRefreshInterval: TimeInterval = 0.5

    private let makeKeyboardQuery: () -> KeyboardStateQuery
    private let now: () -> TimeInterval
    private var readKeyboardStates: KeyboardStateQuery
    private var refreshAfter: TimeInterval

    init(makeKeyboardQuery: @escaping () -> KeyboardStateQuery = CapsLockReader.makeSystemQuery,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.makeKeyboardQuery = makeKeyboardQuery
        self.now = now
        readKeyboardStates = makeKeyboardQuery()
        refreshAfter = now() + Self.clientRefreshInterval
    }

    convenience init(readKeyboardStates: @escaping KeyboardStateQuery) {
        self.init(makeKeyboardQuery: { readKeyboardStates })
    }

    static func makeSystemQuery() -> KeyboardStateQuery {
        // A simple client's service list can omit newly connected keyboards
        // while every retained service still returns a valid boolean.
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
        if now() >= refreshAfter {
            // Refresh even successful queries: valid values do not guarantee
            // that the client includes all currently connected keyboards.
            // Replace once after a long pause, without catching up missed ticks.
            readKeyboardStates = makeKeyboardQuery()
            refreshAfter = now() + Self.clientRefreshInterval
        }
        guard let states = readKeyboardStates(), !states.isEmpty else { return nil }
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
