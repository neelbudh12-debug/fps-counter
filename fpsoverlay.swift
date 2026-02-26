import Cocoa
import IOKit
import IOKit.graphics
import MachO

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!
    var label: NSTextField!

    // FPS tracking
    var lastTime = CACurrentMediaTime()
    var frameTimes: [Double] = []
    let maxSamples = 300

    var displayLink: CVDisplayLink?

    func applicationDidFinishLaunching(_ notification: Notification) {

        // Create overlay window
        let screen = NSScreen.main!.frame
        window = NSWindow(
            contentRect: NSRect(x: 20, y: screen.height - 120, width: 260, height: 90),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true  // click-through
        window.makeKeyAndOrderFront(nil)

        // Label
        label = NSTextField(labelWithString: "Click app to start")
        label.textColor = .green
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        label.backgroundColor = .clear
        label.alignment = .left
        label.frame = window.contentView!.bounds.insetBy(dx: 8, dy: 8)

        window.contentView?.addSubview(label)

        // Start after click
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
            self.startFPS()
        }
    }

    // MARK: — FPS Loop

    func startFPS() {
        guard displayLink == nil else { return }

        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)

        CVDisplayLinkSetOutputCallback(displayLink!) { _, _, _, _, _, userData in
            let app = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
            DispatchQueue.main.async {
                app.frameUpdate()
            }
            return kCVReturnSuccess
        }

        CVDisplayLinkSetCurrentCGDisplay(displayLink!,
                                         CGMainDisplayID())

        CVDisplayLinkSetOutputCallback(displayLink!,
                                       { _,_,_,_,_,userData in
            let app = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
            DispatchQueue.main.async { app.frameUpdate() }
            return kCVReturnSuccess
        },
                                       UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))

        CVDisplayLinkStart(displayLink!)
    }

    func frameUpdate() {
        let now = CACurrentMediaTime()
        let delta = now - lastTime
        lastTime = now

        frameTimes.append(delta)
        if frameTimes.count > maxSamples {
            frameTimes.removeFirst()
        }

        let fps = Int(1.0 / delta)
        let low1 = calc1PercentLow()

        updateLabel(fps: fps, low1: low1)
    }

    func calc1PercentLow() -> Int {
        guard frameTimes.count > 20 else { return 0 }

        let sorted = frameTimes.sorted(by: >)
        let count = max(1, Int(Double(sorted.count) * 0.01))
        let worst = sorted.prefix(count)

        let avg = worst.reduce(0, +) / Double(count)
        return Int(1.0 / avg)
    }

    // MARK: — System Info

    func cpuUsage() -> Double {
        var kr: kern_return_t
        var task_info_count = mach_msg_type_number_t(MemoryLayout<task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
        var tinfo = task_basic_info()

        kr = withUnsafeMutablePointer(to: &tinfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(task_info_count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO), $0, &task_info_count)
            }
        }

        return kr == KERN_SUCCESS ? Double(tinfo.resident_size) / (1024*1024) : 0
    }

    func ramUsage() -> Double {
        let mem = ProcessInfo.processInfo.physicalMemory
        let used = Double(cpuUsage())
        return used / Double(mem) * 100
    }

    func cpuModel() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var cpu = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &cpu, &size, nil, 0)
        return String(cString: cpu)
    }

    func gpuModel() -> String {
        var iterator: io_iterator_t = 0
        IOServiceGetMatchingServices(kIOMasterPortDefault,
                                     IOServiceMatching("IOPCIDevice"),
                                     &iterator)

        var model = "Unknown GPU"

        while case let device = IOIteratorNext(iterator), device != 0 {
            if let name = IORegistryEntryCreateCFProperty(
                device,
                "model" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? Data,
               let str = String(data: name, encoding: .ascii) {
                model = str
                break
            }
            IOObjectRelease(device)
        }

        IOObjectRelease(iterator)
        return model
    }

    // MARK: — UI Update

    func updateLabel(fps: Int, low1: Int) {
        let cpu = cpuModel()
        let gpu = gpuModel()

        label.stringValue =
        """
        FPS: \(fps) | 1% Low: \(low1)
        CPU: \(cpu)
        GPU: \(gpu)
        """
    }
}
