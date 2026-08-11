import Cocoa

@Observable
class DriverSettings: Codable {
    enum TrackingMode: String, Codable {
        case absolute = "Absolute"
        case relative = "Relative"
    }

    @Observable
    class Rectangle: Codable {
        var low: NSPoint
        var up: NSPoint

        init(low: NSPoint, up: NSPoint) {
            self.low = low
            self.up = up
        }

        init?(from string: String) {
            if DriverSettings.Rectangle.stringIsValid(string: string) {
                let compoenents = string.components(separatedBy: ",")
                    .map { CGFloat(Float($0)!) }
                low = NSPoint(x: compoenents[0], y: compoenents[1])
                up = NSPoint(x: compoenents[0] + compoenents[2], y: compoenents[1] + compoenents[3])
            } else {
                return nil
            }
        }

        func toString() -> String {
            return "\(low.x),\(low.y),\(up.x-low.x),\(up.y-low.y)"// WE NOW USE XYWH
        }

        static func stringIsValid(string: String, name: String = "") -> Bool {
            let components = string.components(separatedBy: ",")
                .map({ (s: String) -> Bool in
                    let f = Float(s)
                    return f != nil && (0.0...1.0).contains(f!)
                })
            let isValid = components.count == 4 && components.reduce(true) { $0 && $1 }
            if !isValid && name != "" {
                print(name + " range not valid")
            }
            return isValid
        }
    }

    var trackpadArea: Rectangle? = nil
    var screenArea: Rectangle? = nil
    var emitMouseEvent: Bool = true
    var trackingMode: TrackingMode = .absolute
    var displayId: Int = 0
    var enabled: Bool = false
    var smoothingFactor: Double = 0.9
    var jitterThreshold: Double = 1.0
    var trackingSensitivity: Double = 1.0
    var lockAspectRatio: Bool = false
    
    var lastSaved: Date? = nil

    init() {
        trackpadArea = Rectangle(from: UserDefaults.standard.string(forKey: "trackpadArea") ?? "0.5,0.25,0.5,0.5")
        screenArea = Rectangle(from: UserDefaults.standard.string(forKey: "screenArea") ?? "0,0,1,1")
        emitMouseEvent = UserDefaults.standard.object(forKey: "emitMouseEvent") == nil ? true : UserDefaults.standard.bool(forKey: "emitMouseEvent")
        trackingMode = UserDefaults.standard.string(forKey: "trackingMode") == "Absolute" ? .absolute : .relative
        if (UserDefaults.standard.object(forKey: "displayId") != nil) {
            displayId = UserDefaults.standard.integer(forKey: "displayId")
        } else {
            displayId = Int(NSScreen.main?.cgDirectDisplayID ?? 0)
            UserDefaults.standard.set(displayId, forKey: "displayId")
        }
        enabled = UserDefaults.standard.bool(forKey: "enabled")
        smoothingFactor = max(getNumOrDefault(key: "smoothingFactor", defaultValue: 1.0), 0.1)
        jitterThreshold = getNumOrDefault(key: "jitterThreshold", defaultValue: 0.0)
        trackingSensitivity = getNumOrDefault(key: "trackingSensitivity", defaultValue: 1.0)
        lockAspectRatio = UserDefaults.standard.bool(forKey: "lockAspectRatio")
    }

    private func getNumOrDefault(key: String, defaultValue: Double) -> Double {
        if UserDefaults.standard.object(forKey: key) != nil {
            return UserDefaults.standard.double(forKey: key)
        } else {
            UserDefaults.standard.set(defaultValue, forKey: key)
            return defaultValue
        }
    }

    func save() {
        UserDefaults.standard.set(trackpadArea?.toString(), forKey: "trackpadArea")
        UserDefaults.standard.set(screenArea?.toString(), forKey: "screenArea")
        UserDefaults.standard.set(emitMouseEvent, forKey: "emitMouseEvent")
        UserDefaults.standard.set(trackingMode.rawValue, forKey: "trackingMode")
        UserDefaults.standard.set(displayId, forKey: "displayId")
        UserDefaults.standard.set(enabled, forKey: "enabled")
        UserDefaults.standard.set(smoothingFactor, forKey: "smoothingFactor")
        UserDefaults.standard.set(jitterThreshold, forKey: "jitterThreshold")
        UserDefaults.standard.set(trackingSensitivity, forKey: "trackingSensitivity")
        UserDefaults.standard.set(lockAspectRatio, forKey: "lockAspectRatio")
        print("[main] saved settings")
        lastSaved = Date()
    }

    func toArgs() -> [String] {
        var args: [String] = []
        if let trackpadArea = trackpadArea {
            args.append("-i")
            args.append(trackpadArea.toString())
        }
        if let screenArea = screenArea {
            args.append("-o")
            args.append(screenArea.toString())
        }
        if emitMouseEvent {
            args.append("-e")
        }
        args.append("-m")
        args.append(trackingMode.rawValue)
        args.append("-d")
        args.append(String(displayId))
        args.append("-s")
        args.append(String(smoothingFactor))
        args.append("-j")
        args.append(String(jitterThreshold))
        args.append("-t")
        args.append(String(trackingSensitivity))
        return args
    }
}
