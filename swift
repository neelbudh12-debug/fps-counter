import Cocoa
import IOKit
import QuartzCore

@main
class FPSOverlayApp: NSObject, NSApplicationDelegate {

    var window: NSWindow!
    var label: NSTextField!

    var lastTime = CACurrentMediaTime()
    var frameTimes: [Double] = []
    let maxSamples = 300

    var displayLink: CVDisplayLink?

    func applicationDidFinishLaunching(_ notification: Notification) {

        let screen = NSScreen.main!.frame

        window = NSWindow(
            contentRect: NSRect(x: 20, y: screen.height - 120, width: 280, height: 100),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = NSColor.black.withAlphaComponent(0.4)
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true
        window.makeKeyAndOrderFront(nil)

        label = NSTextField(labelWithString: "Click to start")
        label.textColor = .systemGreen
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        label.frame = window.contentView!.bounds.insetBy(dx: 10, dy: 10)

        window.contentView?.addSubview(label)

        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
            self.startFPS()
        }
    }

    func startFPS() {
        guard displayLink == nil else { return }

        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)

        CVDisplayLinkSetOutputCallback(displayLink!) { _,_,_,_,_,userData in
            let app = Unmanaged<FPSOverlayApp>
                .fromOpaque(userData!)
                .takeUnretainedValue()

            DispatchQueue.main.async { app.frameUpdate() }
            return kCVReturnSuccess
        }

        CVDisplayLinkSetOutputCallback(
            displayLink!,
            { _,_,_,_,_,userData in
                let app = Unmanaged<FPSOverlayApp>
                    .fromOpaque(userData!)
                    .takeUnretainedValue()

                DispatchQueue.main.async { app.frameUpdate() }
                return kCVReturnSuccess
            },
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

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

        label.stringValue = """
        FPS: \(fps)
        1% Low: \(low1)
        """
    }

    func calc1PercentLow() -> Int {

        guard frameTimes.count > 20 else { return 0 }

        let sorted = frameTimes.sorted(by: >)
        let count = max(1, Int(Double(sorted.count) * 0.01))
        let worst = sorted.prefix(count)

        let avg = worst.reduce(0, +) / Double(count)
        return Int(1.0 / avg)
    }
}
