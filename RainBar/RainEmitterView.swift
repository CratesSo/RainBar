import AppKit

final class RainEmitterView: NSView {
    private struct Particle {
        var point: CGPoint
        var lengthNoise: CGFloat
    }

    private struct SplashParticle {
        var point: CGPoint
        var velocity: CGSize
        var age: TimeInterval
        var lifetime: TimeInterval
        var radius: CGFloat
    }

    private struct RainMetrics {
        let motionVector: CGSize
        let streakVector: CGSize

        init(settings: RainSettings) {
            let radians = settings.angle * .pi / 180
            let speed = CGFloat(380 * settings.speed)
            motionVector = CGSize(
                width: CGFloat(sin(radians)) * speed,
                height: CGFloat(cos(radians)) * speed
            )

            let length = CGFloat(settings.trailLength)
            let magnitude = max(hypot(motionVector.width, motionVector.height), 1)
            streakVector = CGSize(
                width: motionVector.width / magnitude * length,
                height: motionVector.height / magnitude * length
            )
        }
    }

    private var settings: RainSettings
    private var metrics: RainMetrics
    private var particles: [Particle] = []
    private var splashes: [SplashParticle] = []
    private var timer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    init(settings: RainSettings) {
        self.settings = settings
        metrics = RainMetrics(settings: settings)
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            stopAnimation()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        ensureParticles()
    }

    func apply(settings: RainSettings) {
        guard settings != self.settings else {
            return
        }

        let amountChanged = settings.rainAmount != self.settings.rainAmount
        self.settings = settings
        metrics = RainMetrics(settings: settings)
        if amountChanged { ensureParticles() }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if !particles.isEmpty {
            NSColor(
                calibratedRed: settings.rainColor.red,
                green: settings.rainColor.green,
                blue: settings.rainColor.blue,
                alpha: CGFloat(settings.opacity)
            ).setStroke()

            let path = NSBezierPath()
            path.lineWidth = CGFloat(settings.trailThickness)
            path.lineCapStyle = .round

            for particle in particles {
                let lengthScale = max(0.2, 1 + particle.lengthNoise * CGFloat(settings.trailLengthVariation))
                let streakVector = CGSize(
                    width: metrics.streakVector.width * lengthScale,
                    height: metrics.streakVector.height * lengthScale
                )

                path.move(to: NSPoint(
                    x: particle.point.x - streakVector.width / 2,
                    y: particle.point.y - streakVector.height / 2
                ))
                path.line(to: NSPoint(
                    x: particle.point.x + streakVector.width / 2,
                    y: particle.point.y + streakVector.height / 2
                ))
            }

            path.stroke()
        }

        guard !splashes.isEmpty, let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        for splash in splashes {
            let fade = max(0, 1 - splash.age / splash.lifetime)
            context.setFillColor(
                red: settings.rainColor.red,
                green: settings.rainColor.green,
                blue: settings.rainColor.blue,
                alpha: CGFloat(settings.splashOpacity) * CGFloat(fade)
            )
            context.fillEllipse(in: CGRect(
                x: splash.point.x - splash.radius,
                y: splash.point.y - splash.radius,
                width: splash.radius * 2,
                height: splash.radius * 2
            ))
        }
    }

    func startAnimation() {
        guard timer == nil else {
            return
        }

        lastTick = ProcessInfo.processInfo.systemUptime
        ensureParticles()

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.advance()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }

    private func advance() {
        let now = ProcessInfo.processInfo.systemUptime
        let delta = max(0, min(now - lastTick, 1.0 / 20.0))
        lastTick = now

        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        let margins = spawnMargins()

        for index in particles.indices {
            particles[index].point.x += metrics.motionVector.width * delta
            particles[index].point.y += metrics.motionVector.height * delta

            if particles[index].point.y > bounds.height {
                addSplash(at: CGPoint(
                    x: particles[index].point.x,
                    y: bounds.height - 2
                ))
                particles[index] = spawnParticle(margins: margins)
            } else if particles[index].point.x < -margins.left
                || particles[index].point.x > bounds.width + margins.right {
                particles[index] = spawnParticle(margins: margins)
            }
        }

        for index in splashes.indices {
            splashes[index].age += delta
            splashes[index].point.x += splashes[index].velocity.width * delta
            splashes[index].point.y += splashes[index].velocity.height * delta
            splashes[index].velocity.height += 180 * delta
        }
        splashes.removeAll { $0.age >= $0.lifetime }

        needsDisplay = true
    }

    private func addSplash(at point: CGPoint) {
        guard settings.splashOpacity > 0,
              point.x >= 0,
              point.x <= bounds.width else {
            return
        }

        for _ in 0..<3 {
            splashes.append(SplashParticle(
                point: point,
                velocity: CGSize(
                    width: CGFloat.random(in: -42...42),
                    height: CGFloat.random(in: -72 ... -24)
                ),
                age: 0,
                lifetime: TimeInterval.random(in: 0.18...0.34),
                radius: CGFloat.random(in: 1.3...2.8)
            ))
        }

        if splashes.count > 240 {
            splashes.removeFirst(splashes.count - 240)
        }
    }

    private func ensureParticles() {
        guard bounds.width > 0, bounds.height > 0 else {
            particles.removeAll()
            return
        }

        let targetCount: Int
        if settings.rainAmount <= 0 {
            targetCount = 0
        } else {
            let baseCount = max(80, Int(bounds.width * bounds.height / 4_500))
            let rainMultiplier: Double
            if settings.rainAmount <= 0.5 {
                rainMultiplier = 0.05 + settings.rainAmount / 0.5 * 0.95
            } else {
                rainMultiplier = 1.0 + (settings.rainAmount - 0.5) / 0.5 * 0.25
            }
            targetCount = max(4, Int(Double(baseCount) * rainMultiplier))
        }

        if particles.count < targetCount {
            particles.append(contentsOf: (particles.count..<targetCount).map { _ in
                Particle(point: CGPoint(
                    x: CGFloat.random(in: 0...bounds.width),
                    y: CGFloat.random(in: 0...bounds.height)
                ), lengthNoise: CGFloat.random(in: -1...1))
            })
        } else if particles.count > targetCount {
            particles.removeLast(particles.count - targetCount)
        }
    }

    private func spawnParticle(margins: (left: CGFloat, right: CGFloat)) -> Particle {
        Particle(
            point: CGPoint(
                x: CGFloat.random(in: -margins.left...(bounds.width + margins.right)),
                y: CGFloat.random(in: -90...0)
            ),
            lengthNoise: CGFloat.random(in: -1...1)
        )
    }

    private func spawnMargins() -> (left: CGFloat, right: CGFloat) {
        let verticalSpeed = max(abs(metrics.motionVector.height), 1)
        let horizontalTravel = abs(metrics.motionVector.width / verticalSpeed * bounds.height)
        let baseMargin: CGFloat = 36
        let leftMargin = metrics.motionVector.width > 0 ? horizontalTravel + baseMargin : baseMargin
        let rightMargin = metrics.motionVector.width < 0 ? horizontalTravel + baseMargin : baseMargin
        return (leftMargin, rightMargin)
    }
}
