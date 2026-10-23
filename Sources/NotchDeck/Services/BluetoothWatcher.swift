import Foundation
import IOBluetooth

/// Announces Bluetooth devices (AirPods, keyboards, mice…) as they connect and disconnect.
final class BluetoothWatcher: NSObject {
    var onChange: ((_ name: String, _ symbol: String, _ connected: Bool) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    private var startedAt = Date()

    func start() {
        guard connectNotification == nil else { return }
        startedAt = Date()
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                         selector: #selector(connected(_:device:)))
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
    }

    @objc private func connected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        device.register(forDisconnectNotification: self, selector: #selector(disconnected(_:device:)))
        // Registration replays devices that are already connected; don't announce those.
        guard Date().timeIntervalSince(startedAt) > 3 else { return }
        onChange?(device.name ?? "Bluetooth device", Self.symbol(for: device), true)
    }

    @objc private func disconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        onChange?(device.name ?? "Bluetooth device", Self.symbol(for: device), false)
    }

    static func symbol(for device: IOBluetoothDevice) -> String {
        let name = (device.name ?? "").lowercased()
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("beats") || name.contains("headphone") || name.contains("buds") { return "headphones" }
        if name.contains("keyboard") { return "keyboard.fill" }
        if name.contains("trackpad") { return "rectangle.and.hand.point.up.left.fill" }
        if name.contains("mouse") { return "computermouse.fill" }
        if name.contains("controller") { return "gamecontroller.fill" }
        if device.deviceClassMajor == UInt32(kBluetoothDeviceClassMajorAudio) { return "headphones" }
        return "dot.radiowaves.left.and.right"
    }
}
