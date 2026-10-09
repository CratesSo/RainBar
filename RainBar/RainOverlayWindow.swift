import AppKit
import QuartzCore

final class RainOverlayWindow: NSPanel {
    private let rainView: RainEmitterView
    private let snowView = SnowEmitterView()
    private var mode: WeatherMode
    private var fadeStartedAt: TimeInterval?
    private var fadeStartOpacity: CGFloat = 0
    private var fadeTargetOpacity: CGFloat = 0

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
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .ignoresCycle]
        if !ActiveWindowTracker.canPlaceOverlayInSpace {
            collectionBehavior.insert(.canJoinAllSpaces)
        }
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
        if !isVisible {
            alphaValue = 0
            orderFrontRegardless()
            fade(to: 1)
        } else if fadeTargetOpacity != 1 {
            fade(to: 1)
        }
        if mode == .rain { rainView.startAnimation() }
        else { snowView.startAnimation() }
    }

    func hide(animated: Bool = false) {
        if animated, isVisible {
            if fadeTargetOpacity != 0 { fade(to: 0) }
            return
        }
        guard isVisible || fadeStartedAt != nil else { return }
        fadeStartedAt = nil
        fadeTargetOpacity = 0
        alphaValue = 0
        rainView.stopAnimation()
        snowView.stopAnimation()
        orderOut(nil)
    }

    func updateFade() {
        guard let startedAt = fadeStartedAt else { return }
        let duration = fadeTargetOpacity == 0 ? 0.1575 : 0.315
        let progress = min(1, (ProcessInfo.processInfo.systemUptime - startedAt) / duration)
        let remaining = 1 - progress
        let eased = CGFloat(fadeTargetOpacity == 1
                            ? 1 - remaining * remaining * remaining
                            : progress * progress * (3 - 2 * progress))
        alphaValue = fadeStartOpacity + (fadeTargetOpacity - fadeStartOpacity) * eased
        if progress == 1 {
            fadeStartedAt = nil
            if fadeTargetOpacity == 0 { hide() }
        }
    }

    private func fade(to opacity: CGFloat) {
        fadeStartOpacity = alphaValue
        fadeTargetOpacity = opacity
        fadeStartedAt = ProcessInfo.processInfo.systemUptime
    }
}


final class SnowEmitterView: NSView {
    struct Particle {
        var point: CGPoint
        var age: Double
        var rotation: CGFloat
        let spin: CGFloat
        let sizeNoise: CGFloat
        let flakeThreshold: Double
    }

    private var settings = RainSettings.defaults
    private(set) var particles: [Particle] = []
    private let acceleration = 16.25625
    private var horizontal = sin(RainSettings.defaults.angle * .pi / 180)
    private var vertical = cos(RainSettings.defaults.angle * .pi / 180)
    private var fallTime: Double = 0
    private var frameDisplayLink: CADisplayLink?
    private var lastTick: TimeInterval = 0
    private let dotImage: CGImage? = {
        guard let context = SnowEmitterView.particleContext() else { return nil }
        context.setFillColor(NSColor.white.cgColor)
        context.fillEllipse(in: CGRect(x: 2, y: 2, width: 16, height: 16))
        return context.makeImage()
    }()
    private let flakeImage = SnowEmitterView.snowflakeImage()
    private var particleLayers: [CALayer] = []
    private var animationClock: TimeInterval = 0
    private var rebuildAll = true
    private var dirtyParticles = Set<Int>()

    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.speed = 0
        updateFallTime()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        rebuildAll = true
        needsLayout = true
    }

    func apply(settings: RainSettings) {
        guard settings != self.settings else { return }
        let amountChanged = settings.rainAmount != self.settings.rainAmount
        let angleChanged = settings.angle != self.settings.angle
        let oldVertical = vertical
        self.settings = settings
        if angleChanged {
            let radians = settings.angle * .pi / 180
            horizontal = sin(radians)
            vertical = cos(radians)
            updateFallTime()
            let ageScale = sqrt(oldVertical / vertical)
            for index in particles.indices {
                particles[index].age *= ageScale
            }
        }
        if amountChanged { ensureParticles() }
        rebuildAll = true
        needsLayout = true
        if particles.isEmpty { stopAnimation() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldSize = bounds.size
        super.setFrameSize(newSize)
        guard oldSize != newSize else { return }
        updateFallTime()
        if oldSize.width > 0, oldSize.height > 0, newSize.width > 0, newSize.height > 0 {
            let scaleX = (newSize.width + 60) / (oldSize.width + 60)
            let scaleY = (newSize.height + 60) / (oldSize.height + 60)
            let ageScale = sqrt(Double(scaleY))
            for index in particles.indices {
                particles[index].point.x = (particles[index].point.x + 30) * scaleX - 30
                particles[index].point.y = (particles[index].point.y + 30) * scaleY - 30
                particles[index].age *= ageScale
            }
        }
        ensureParticles()
        rebuildAll = true
        needsLayout = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopAnimation() }
    }

    func startAnimation() {
        guard frameDisplayLink == nil else { return }
        lastTick = 0
        ensureParticles()
        guard !particles.isEmpty else { return }
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
        advance(by: delta)
    }

    func advance(by delta: TimeInterval) {
        guard !particles.isEmpty else {
            stopAnimation()
            return
        }
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }

        animationClock += delta
        if settings.opacity > 0 { layer?.timeOffset = animationClock }
        let step = delta * settings.speed / RainSettings.defaults.speed
        let horizontal = CGFloat(self.horizontal)
        let vertical = CGFloat(self.vertical)
        let wrapWidth = size.width + 60
        let fallTime = self.fallTime
        for index in particles.indices {
            let distance = CGFloat(acceleration * (particles[index].age + step / 2) * step)
            particles[index].age += step
            particles[index].point.x += distance * horizontal
            particles[index].point.y -= distance * vertical
            particles[index].rotation += particles[index].spin * CGFloat(step)

            if particles[index].age >= fallTime {
                let age = particles[index].age.truncatingRemainder(dividingBy: fallTime)
                particles[index] = makeParticle(age: age, in: size)
            } else if particles[index].point.x < -30 {
                particles[index].point.x += wrapWidth
            } else if particles[index].point.x > size.width + 30 {
                particles[index].point.x -= wrapWidth
            } else {
                continue
            }
            if !rebuildAll { dirtyParticles.insert(index) }
        }
        if settings.opacity > 0, rebuildAll || !dirtyParticles.isEmpty { needsLayout = true }
    }

    private func updateFallTime() {
        fallTime = sqrt(2 * Double(bounds.height + 60) / (acceleration * vertical))
    }

    private func ensureParticles() {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let fallTime = self.fallTime
        let targetCount = max(0, Int(23 * fallTime * settings.rainAmount / RainSettings.defaults.rainAmount))
        guard particles.count != targetCount else { return }
        rebuildAll = true
        needsLayout = true
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
                y: size.height + 30 - CGFloat(0.5 * acceleration * vertical * age * age)
            ),
            age: age,
            rotation: CGFloat.random(in: 0...(2 * .pi)),
            spin: CGFloat.random(in: 0...0.4),
            sizeNoise: CGFloat.random(in: 0...1),
            flakeThreshold: Double.random(in: 0..<1)
        )
    }

    override func layout() {
        super.layout()
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        layer.timeOffset = animationClock

        while particleLayers.count > particles.count {
            particleLayers.removeLast().removeFromSuperlayer()
        }
        let scale = window?.backingScaleFactor ?? layer.contentsScale
        let top = bounds.height + 30
        let inverseHeight = 1 / (bounds.height + 60)
        let opacity = CGFloat(settings.opacity)
        let fade = CGFloat(settings.snowFade)
        let snowSizeScale = CGFloat(settings.snowSize)
        let flakeSizeScale = CGFloat(settings.snowflakeSize)
        func updateSprite(at index: Int) {
            let particle = particles[index]
            let isFlake = settings.snowflakesEnabled && particle.flakeThreshold < settings.snowflakeAmount
            let rendersFlake = isFlake && flakeImage != nil
            let isRound = settings.snowShape == .round && !rendersFlake
            if index == particleLayers.count || isRound != (particleLayers[index] is CAShapeLayer) {
                let sprite: CALayer
                if isRound {
                    let shape = CAShapeLayer()
                    shape.fillColor = NSColor.white.cgColor
                    sprite = shape
                } else {
                    sprite = CALayer()
                }
                if index == particleLayers.count {
                    layer.addSublayer(sprite)
                    particleLayers.append(sprite)
                } else {
                    layer.replaceSublayer(particleLayers[index], with: sprite)
                    particleLayers[index] = sprite
                }
            }
            let sprite = particleLayers[index]
            let size = isFlake
                ? (7 + particle.sizeNoise) * flakeSizeScale
                : (2 + 2 * particle.sizeNoise) * snowSizeScale
            let spriteBounds = CGRect(x: 0, y: 0, width: size, height: size)
            if sprite.bounds != spriteBounds {
                sprite.bounds = spriteBounds
                if let shape = sprite as? CAShapeLayer {
                    shape.path = CGPath(ellipseIn: spriteBounds, transform: nil)
                }
            }
            if !isRound { sprite.contents = isFlake ? (flakeImage ?? dotImage) : dotImage }
            sprite.contentsScale = scale
            sprite.position = particle.point
            sprite.setAffineTransform(CGAffineTransform(rotationAngle: rendersFlake ? particle.rotation : 0))
            let progress = min(1, max(0, (top - particle.point.y) * inverseHeight))
            sprite.opacity = Float(opacity * (1 - fade * progress))

            let remaining = max(0.0001, fallTime - particle.age)
            let duration = remaining * RainSettings.defaults.speed / settings.speed
            let distance = CGFloat(acceleration * (particle.age + remaining / 2) * remaining)
            let endpoint = CGPoint(
                x: particle.point.x + distance * CGFloat(horizontal),
                y: particle.point.y - distance * CGFloat(vertical)
            )
            let initialSlope = Float(particle.age / (particle.age + remaining / 2))
            let timing = CAMediaTimingFunction(
                controlPoints: 1 / 3, initialSlope / 3, 2 / 3, (1 + initialSlope) / 3
            )
            func makeAnimation(_ keyPath: String) -> CABasicAnimation {
                let animation = CABasicAnimation(keyPath: keyPath)
                animation.beginTime = animationClock
                animation.duration = duration
                animation.fillMode = .forwards
                animation.isRemovedOnCompletion = false
                return animation
            }
            let position = makeAnimation("position")
            position.fromValue = NSValue(point: particle.point)
            position.toValue = NSValue(point: endpoint)
            position.timingFunction = timing
            sprite.add(position, forKey: "position")

            if rendersFlake {
                let rotation = makeAnimation("transform.rotation.z")
                rotation.fromValue = particle.rotation
                rotation.toValue = particle.rotation + particle.spin * CGFloat(remaining)
                rotation.timingFunction = CAMediaTimingFunction(name: .linear)
                sprite.add(rotation, forKey: "rotation")
            } else {
                sprite.removeAnimation(forKey: "rotation")
            }

            let alpha = makeAnimation("opacity")
            alpha.fromValue = sprite.opacity
            alpha.toValue = Float(opacity * (1 - fade))
            alpha.timingFunction = timing
            sprite.add(alpha, forKey: "opacity")
        }
        if rebuildAll {
            for index in particles.indices { updateSprite(at: index) }
        } else {
            for index in dirtyParticles { updateSprite(at: index) }
        }
        rebuildAll = false
        dirtyParticles.removeAll(keepingCapacity: true)
    }

    private static func snowflakeImage() -> CGImage? {
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
