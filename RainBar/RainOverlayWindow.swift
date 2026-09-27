import AppKit
import QuartzCore

final class RainOverlayWindow: NSPanel {
    private let rainView: RainEmitterView
    private let snowView = SnowEmitterView()
    private var mode: WeatherMode

    init(settings: RainSettings, mode: WeatherMode) {
        self.mode = mode
        rainView = RainEmitterView(settings: settings)

        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = mode == .rain ? rainView : snowView
        snowView.apply(settings: settings)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func apply(settings: RainSettings, mode: WeatherMode) {
        rainView.apply(settings: settings)
        snowView.apply(settings: settings)
        if self.mode != mode {
            rainView.stopAnimation()
            snowView.stopAnimation()
            self.mode = mode
            contentView = mode == .rain ? rainView : snowView
            if isVisible { show() }
        }
    }

    func show() {
        orderFrontRegardless()
        if mode == .rain { rainView.startAnimation() }
        else { snowView.startAnimation() }
    }

    func hide() {
        rainView.stopAnimation()
        snowView.stopAnimation()
        orderOut(nil)
    }
}


private final class SnowEmitterView: NSView {
    private struct Particle {
        var point: CGPoint
        var age: Double
        var rotation: CGFloat
        let spin: CGFloat
        let sizeNoise: CGFloat
        // A stable threshold lets the slider convert existing particles in place.
        let flakeThreshold: Double
    }

    private var settings = RainSettings.defaults
    private var particles: [Particle] = []
    private var frameDisplayLink: CADisplayLink?
    private var lastTick: TimeInterval = 0
    private let dotImage: CGImage? = {
        guard let context = SnowEmitterView.particleContext() else { return nil }
        context.setFillColor(NSColor.white.cgColor)
        context.fillEllipse(in: CGRect(x: 2, y: 2, width: 16, height: 16))
        return context.makeImage()
    }()
    private let flakeImage = SnowEmitterView.snowflakeImage()

    override var isOpaque: Bool { false }

    func apply(settings: RainSettings) {
        guard settings != self.settings else { return }
        let amountChanged = settings.rainAmount != self.settings.rainAmount
        self.settings = settings
        if amountChanged { ensureParticles() }
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldSize = bounds.size
        super.setFrameSize(newSize)
        guard oldSize != newSize else { return }
        if oldSize.width > 0, oldSize.height > 0, newSize.width > 0, newSize.height > 0 {
            let scaleX = (newSize.width + 60) / (oldSize.width + 60)
            let scaleY = (newSize.height + 60) / (oldSize.height + 60)
            for index in particles.indices {
                particles[index].point.x = (particles[index].point.x + 30) * scaleX - 30
                particles[index].point.y = (particles[index].point.y + 30) * scaleY - 30
            }
        }
        ensureParticles()
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopAnimation() }
    }

    func startAnimation() {
        guard frameDisplayLink == nil else { return }
        lastTick = 0
        ensureParticles()
        let link = displayLink(target: self, selector: #selector(advance(_:)))
        let maximumRate = Float(NSScreen.screens.map(\.maximumFramesPerSecond).max() ?? 60)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: maximumRate, preferred: maximumRate)
        link.add(to: .main, forMode: .common)
        frameDisplayLink = link
    }

    func stopAnimation() {
        frameDisplayLink?.invalidate()
        frameDisplayLink = nil
    }

    @objc private func advance(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let delta = lastTick == 0 ? 0 : max(0, min(now - lastTick, 1.0 / 20.0))
        lastTick = now
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }

        let step = delta * settings.speed / RainSettings.defaults.speed
        let radians = settings.angle * .pi / 180
        let horizontal = CGFloat(sin(radians))
        let vertical = CGFloat(cos(radians))
        let wrapWidth = size.width + 60
        for index in particles.indices {
            let distance = CGFloat(16.25625 * (particles[index].age + step / 2) * step)
            particles[index].age += step
            particles[index].point.x += distance * horizontal
            particles[index].point.y -= distance * vertical
            particles[index].rotation += particles[index].spin * CGFloat(step)

            if particles[index].point.y < -30 {
                particles[index] = makeParticle(age: 0, in: size)
            } else if particles[index].point.x < -30 {
                particles[index].point.x += wrapWidth
            } else if particles[index].point.x > size.width + 30 {
                particles[index].point.x -= wrapWidth
            }
        }
        needsDisplay = true
    }

    private func ensureParticles() {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let fallTime = sqrt(2 * Double(size.height + 60) / 16.25625)
        let targetCount = max(0, Int(23 * fallTime * settings.rainAmount / RainSettings.defaults.rainAmount))
        if particles.count < targetCount {
            particles.append(contentsOf: (particles.count..<targetCount).map { _ in
                makeParticle(age: Double.random(in: 0...fallTime), in: size)
            })
        } else if particles.count > targetCount {
            particles.removeLast(particles.count - targetCount)
        }
    }

    private func makeParticle(age: Double, in size: CGSize) -> Particle {
        return Particle(
            point: CGPoint(
                x: CGFloat.random(in: -30...(size.width + 30)),
                y: size.height + 30 - CGFloat(0.5 * 16.25625 * age * age)
            ),
            age: age,
            rotation: CGFloat.random(in: 0...(2 * .pi)),
            spin: CGFloat.random(in: 0...0.4),
            sizeNoise: CGFloat.random(in: 0...1),
            flakeThreshold: Double.random(in: 0..<1)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let top = bounds.height + 30
        let inverseHeight = 1 / (bounds.height + 60)
        let opacity = CGFloat(settings.opacity)
        let fade = CGFloat(settings.snowFade)
        let snowSizeScale = CGFloat(settings.snowSize)
        let flakeSizeScale = CGFloat(settings.snowflakeSize)
        guard opacity > 0 else { return }
        context.setFillColor(NSColor.white.cgColor)
        for particle in particles {
            let isFlake = settings.snowflakesEnabled && particle.flakeThreshold < settings.snowflakeAmount
            let size = isFlake
                ? (7 + particle.sizeNoise) * flakeSizeScale
                : (2 + 2 * particle.sizeNoise) * snowSizeScale
            let radius = size / 2
            let rect = CGRect(x: particle.point.x - radius, y: particle.point.y - radius,
                              width: size, height: size)
            guard rect.intersects(dirtyRect) else { continue }
            let progress = min(1, max(0, (top - particle.point.y) * inverseHeight))
            context.setAlpha(opacity * (1 - fade * progress))
            if isFlake, let flakeImage {
                context.saveGState()
                context.translateBy(x: particle.point.x, y: particle.point.y)
                context.rotate(by: particle.rotation)
                context.draw(flakeImage, in: CGRect(x: -radius, y: -radius,
                                                  width: size, height: size))
                context.restoreGState()
            } else if settings.snowShape == .round {
                context.fillEllipse(in: rect)
            } else if let dotImage {
                context.draw(dotImage, in: rect)
            }
        }
    }

    private static func snowflakeImage() -> CGImage? {
        // Cover the largest flake (24 pt) at Retina resolution without upscaling.
        guard let context = particleContext(scale: 4) else { return nil }
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(2.4)
        context.setLineCap(.round)
        for arm in 0..<6 {
            let angle = CGFloat(arm) * .pi / 3
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            context.move(to: CGPoint(x: 10, y: 10))
            context.addLine(to: CGPoint(x: 10 + 8 * direction.x, y: 10 + 8 * direction.y))
            let branch = CGPoint(x: 10 + 5 * direction.x, y: 10 + 5 * direction.y)
            for offset in [-CGFloat.pi / 4, CGFloat.pi / 4] {
                context.move(to: branch)
                context.addLine(to: CGPoint(
                    x: branch.x + 2.5 * cos(angle + offset),
                    y: branch.y + 2.5 * sin(angle + offset)
                ))
            }
        }
        context.strokePath()
        return context.makeImage()
    }

    private static func particleContext(scale: Int = 1) -> CGContext? {
        let context = CGContext(
            data: nil,
            width: 20 * scale,
            height: 20 * scale,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        return context
    }
}
