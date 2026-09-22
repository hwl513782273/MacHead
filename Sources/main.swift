import Cocoa

let arguments = CommandLine.arguments

if arguments.count > 1 {
    let arg = arguments[1]
    
    if arg == "--status" || arg == "-s" || arg == "status" {
        let defaults = UserDefaults.standard
        defaults.synchronize()
        let isHeadless = defaults.bool(forKey: "HeadlessModeEnabled")
        
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.waffle.MacHead")
        if runningApps.isEmpty {
            print("offline (last saved state: \(isHeadless ? "headless" : "normal"))")
        } else {
            print(isHeadless ? "headless" : "normal")
        }
        exit(0)
        
    } else if arg == "--enable" || arg == "-e" || arg == "enable" {
        print("Sending enable command to MacHead daemon...")
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.waffle.MacHead.CLI.enable"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        exit(0)
        
    } else if arg == "--disable" || arg == "-d" || arg == "disable" {
        print("Sending disable command to MacHead daemon...")
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.waffle.MacHead.CLI.disable"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        exit(0)
        
    } else if arg == "--test" {
        HeadlessModeController.runTests()
        exit(0)

    } else if arg == "--inhibit-charging" || arg == "--charge-inhibit" {
        let val = arguments.count > 2 ? arguments[2] : "1"
        let inhibit = (val == "1" || val.lowercased() == "true")
        let success = SMCManager.shared.setChargingInhibited(inhibit)
        if success {
            print(inhibit ? "Charging inhibited (stopped)" : "Charging restored (enabled)")
            exit(0)
        } else {
            print("Failed to set charging inhibit via SMC (requires root privileges)")
            exit(1)
        }

    } else if arg == "--set-bclm" {
        let limit = arguments.count > 2 ? (Int(arguments[2]) ?? 80) : 80
        let success = SMCManager.shared.setBCLMChargeLimit(limit)
        if success {
            print("BCLM charge limit set to \(limit)%")
            exit(0)
        } else {
            print("Failed to set BCLM via SMC (requires root privileges or Apple Silicon doesn't support BCLM)")
            exit(1)
        }
        
    } else if arg == "--help" || arg == "-h" || arg == "help" {
        print("MacHead - MacBook Headless Mode Manager (CLI Client)")
        print("Usage:")
        print("  MacHead [options]")
        print("")
        print("Options:")
        print("  -s, --status   Show current mode status (headless, normal, or offline)")
        print("  -e, --enable   Enable Headless Mode (turns off built-in display, locks sleep)")
        print("  -d, --disable  Disable Headless Mode (restores built-in display)")
        print("  --test         Run unit tests for HeadlessModeController")
        print("  -h, --help     Show this help message")
        exit(0)
        
    } else {
        print("Unknown option: \(arg)")
        print("Use --help to view available commands.")
        exit(1)
    }
} else {
    // Launch the SwiftUI app GUI
    MacHeadApp.main()
}
