import Foundation
import IOKit.hid
import IOKit.hidsystem

/// Read each keyboard's lock state, independently of posted event flags.
/// Both CGEventSource and IOHIDGetModifierLockState can retain a false Caps bit.
final class CapsLockReader {
    static let shared = CapsLockReader()

    private let readKeyboardStates: () -> [Bool?]?

    convenience init() {
        // Keep one ARC-managed client; enumerate afresh to include hot-plugged
        // keyboards and drop removed services without retaining stale states.
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        self.init(readKeyboardStates: {
            guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
                return nil
            }
            return services.filter {
                IOHIDServiceClientConformsTo($0, UInt32(kHIDPage_GenericDesktop),
                                            UInt32(kHIDUsage_GD_Keyboard)) != 0
            }.map {
                CapsLockReader.readBoolean(IOHIDServiceClientCopyProperty($0, kIOHIDServiceCapsLockStateKey as CFString))
            }
        })
    }

    init(readKeyboardStates: @escaping () -> [Bool?]?) {
        self.readKeyboardStates = readKeyboardStates
    }

    func read() -> Bool? {
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
