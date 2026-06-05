import AppKit

/// A borderless, transparent, click-through floating panel that runs away
/// from the cursor — the "toy" trash can.
///
/// The window is a larger transparent canvas with the small trash icon centered
/// inside it, so the can has room to fall over (倒下) without being clipped by
/// the window edge. While you drag a file toward it, it stops fleeing and turns
/// into a real drop target that moves the file to the system Trash.
final class RunningTrashWindow {

    // MARK: - Tunables

    private enum Const {
        static let size: CGFloat = 80        // the visible icon
        static let canvas: CGFloat = 200     // the (transparent) window — room to fall over
        static let triggerDistance: CGFloat = 200
        static let maxSpeedNormal: CGFloat = 20
        static let maxSpeedDragging: CGFloat = 30
        static let randomWobbleDegrees: CGFloat = 15
        static let edgeMargin: CGFloat = 8
        static let frameInterval: TimeInterval = 1.0 / 60.0

        // "Getting tired" stumbles.
        static let tiredFactor: CGFloat = 0.3
        static let tiredDuration: TimeInterval = 0.5
        static let tiredIntervalMin: TimeInterval = 15
        static let tiredIntervalMax: TimeInterval = 30

        // Caught interaction.
        static let shakeAmplitude: CGFloat = 5
        static let shakeDuration: TimeInterval = 0.3
        static let shakeCycles: CGFloat = 4
        static let subduedDuration: TimeInterval = 8

        // "Focus" / summon: how long it holds still in the corner before it's
        // free to flee again.
        static let summonedDuration: TimeInterval = 6
    }

    /// Inset of the icon inside the canvas.
    private var pad: CGFloat { (Const.canvas - Const.size) / 2 }

    // MARK: - State machine

    private enum State {
        case fleeing
        case shaking(start: TimeInterval, base: CGPoint)
        case subdued(until: TimeInterval)
        /// Summoned to a corner and holding still (won't flee) until this time,
        /// so you can reliably find it and drop files in.
        case summoned(until: TimeInterval)
    }

    private let panel: NSPanel
    private let imageView: NSImageView
    private let faceLabel: NSTextField
    private let speechLabel: NSTextField
    private let dropView: TrashDropView

    private var speechHideWork: DispatchWorkItem?

    /// Sassy one-liners it blurts out when you catch it.
    private static let trashTalk = [
        "抓到又咋样",
        "哎哟，松手啦",
        "你赢了，行吧",
        "别戳啦别戳啦",
        "我裂开了…",
        "就这？还想清空我",
        "今天不收垃圾",
        "你手速也就这样",
        "再点我要满了",
        "555 我认输",
        "我又不咬人",
        "好吧我躺平",
        "你是不是很闲",
        "轻点，易碎品",
        "哼，算你厉害",
        "放开那个废纸篓",
        "本桶拒绝营业",
        "再追我报警了",
    ]

    private var timer: Timer?
    private var globalMonitors: [Any] = []

    private var state: State = .fleeing
    private var isDragging = false
    private var dragResetWorkItem: DispatchWorkItem?

    private var isEmpty = true

    /// The first emptiness report just establishes a baseline — we only animate
    /// state *changes* after that, so launching doesn't trigger a spurious jiggle.
    private var hasEmptinessBaseline = false

    /// When we last swallowed a drop ourselves. External "became full" reactions
    /// are suppressed briefly after this so a local drop animates only once.
    private var lastGulpAt: TimeInterval = 0

    /// Called after files are dropped in, so the app can resync both icons.
    var onRecycled: (() -> Void)?

    // Mouse-button / file-drag tracking.
    private var isMouseDown = false
    private var mouseDownDragSeq = 0
    private var isReceiving = false

    // Tiredness scheduling.
    private var nextTiredAt: TimeInterval = 0
    private var tiredUntil: TimeInterval = 0

    // MARK: - Init

    init() {
        let canvasFrame = NSRect(x: 0, y: 0, width: Const.canvas, height: Const.canvas)
        let inset = (Const.canvas - Const.size) / 2
        let iconFrame = NSRect(x: inset, y: inset, width: Const.size, height: Const.size)

        panel = NSPanel(
            contentRect: canvasFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating // NSFloatingWindowLevel
        panel.ignoresMouseEvents = true // click-through; we detect clicks via global monitor
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        let container = NSView(frame: canvasFrame)
        container.wantsLayer = true

        imageView = NSImageView(frame: iconFrame)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.shadow = nil
        container.addSubview(imageView)

        faceLabel = NSTextField(labelWithString: "😵")
        faceLabel.font = .systemFont(ofSize: 30)
        faceLabel.alignment = .center
        faceLabel.frame = iconFrame.insetBy(dx: 0, dy: -2)
        faceLabel.isHidden = true
        container.addSubview(faceLabel)

        // Speech bubble for trash talk, floating above the can.
        speechLabel = NSTextField(labelWithString: "")
        speechLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        speechLabel.alignment = .center
        speechLabel.textColor = .white
        speechLabel.maximumNumberOfLines = 1
        speechLabel.lineBreakMode = .byTruncatingTail
        speechLabel.wantsLayer = true
        speechLabel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        speechLabel.layer?.cornerRadius = 9
        speechLabel.isHidden = true
        container.addSubview(speechLabel)

        // Drop target sits on top of the icon, only over the visible can.
        dropView = TrashDropView(frame: iconFrame)
        container.addSubview(dropView)

        panel.contentView = container

        dropView.onDrop = { [weak self] urls in self?.recycle(urls) }
    }

    // MARK: - Lifecycle

    func show() {
        moveToRandomStart()
        applyTrashImage()
        panel.orderFrontRegardless()
        scheduleNextTired()
        installMonitors()
        startTimer()
    }

    /// Summon the runaway can: flash it into the bottom-right corner of the
    /// screen under the cursor and make it hold still for a few seconds so you
    /// can find it — and drop files in — without the chase.
    func focusToCorner() {
        // Drop any caught/tipped-over pose and stand upright.
        speechHideWork?.cancel()
        hideSpeech()
        faceLabel.isHidden = true
        imageView.layer?.removeAnimation(forKey: "tip")
        imageView.layer?.transform = CATransform3DIdentity

        // Bottom-right of the current screen, respecting the edge margin.
        let b = startBounds()
        panel.setFrameOrigin(CGPoint(x: b.maxX, y: b.minY))
        panel.orderFrontRegardless()

        state = .summoned(until: now() + Const.summonedDuration)
        flashAppear()
    }

    /// A quick "teleport in" pop: fade up while scaling from small with a tiny
    /// overshoot, so the corner arrival reads as a flash rather than a slide.
    private func flashAppear() {
        guard let layer = imageView.layer else { return }

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.45, 1.15, 0.96, 1.0]
        scale.keyTimes = [0, 0.55, 0.8, 1]

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.0, 1.0]
        fade.keyTimes = [0, 1]

        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.4
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(group, forKey: "flash")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for monitor in globalMonitors {
            NSEvent.removeMonitor(monitor)
        }
        globalMonitors.removeAll()
    }

    func setTrashEmpty(_ empty: Bool) {
        let changed = empty != isEmpty
        isEmpty = empty
        applyTrashImage()

        // First report is just the baseline; only real transitions get a reaction.
        guard hasEmptinessBaseline else { hasEmptinessBaseline = true; return }
        guard changed else { return }
        reactToEmptinessChange(nowEmpty: empty)
    }

    /// Visible feedback when the *system* Trash changes from outside the toy
    /// (emptied in Finder, filled by another app, …). A local drag-and-drop
    /// already plays `gulp()`, so we skip the "became full" reaction right after one.
    private func reactToEmptinessChange(nowEmpty empty: Bool) {
        // Only react while upright and free — don't fight the tip-over / shake.
        guard case .fleeing = state, !isReceiving else { return }
        if empty {
            reliefPop()        // someone emptied the Trash — a light, relieved bounce
        } else if now() - lastGulpAt > 0.6 {
            heavyJiggle()      // it just got heavier from outside — a startled wobble
        }
    }

    // MARK: - Appearance

    // The light, full-color Dock-style trash icons shipped with the system.
    private static let emptyIconPath =
        "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/TrashIcon.icns"
    private static let fullIconPath =
        "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/FullTrashIcon.icns"

    private lazy var emptyImage: NSImage =
        loadTrashIcon(path: Self.emptyIconPath, fallback: NSImage.trashEmptyName)
    private lazy var fullImage: NSImage =
        loadTrashIcon(path: Self.fullIconPath, fallback: NSImage.trashFullName)

    private func loadTrashIcon(path: String, fallback: NSImage.Name) -> NSImage {
        let image = NSImage(contentsOfFile: path) ?? NSImage(named: fallback) ?? NSImage()
        image.size = NSSize(width: Const.size, height: Const.size)
        return image
    }

    private func applyTrashImage() {
        imageView.image = isEmpty ? emptyImage : fullImage
    }

    private func moveToRandomStart() {
        let b = startBounds()
        let x = CGFloat.random(in: b.minX...b.maxX)
        let y = CGFloat.random(in: b.minY...b.maxY)
        panel.setFrameOrigin(CGPoint(x: x, y: y))
    }

    // MARK: - Monitors

    private func installMonitors() {
        // Mouse movement (for fleeing) and dragging (for the speed boost).
        let moveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.handleMovement(event)
        }
        if let moveMonitor { globalMonitors.append(moveMonitor) }

        // Clicks (for catching).
        let downMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            self?.handleMouseDown()
        }
        if let downMonitor { globalMonitors.append(downMonitor) }

        // Drag ended — drop the boost.
        let upMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            self?.isDragging = false
            self?.isMouseDown = false
        }
        if let upMonitor { globalMonitors.append(upMonitor) }
    }

    private func handleMovement(_ event: NSEvent) {
        if event.type == .leftMouseDragged {
            isDragging = true
            // Safety net in case we miss the mouse-up (e.g. drag over our own space).
            dragResetWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.isDragging = false }
            dragResetWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
    }

    private func handleMouseDown() {
        isMouseDown = true
        // Remember the drag pasteboard's state so we can tell a *new* file drag apart.
        mouseDownDragSeq = NSPasteboard(name: .drag).changeCount

        guard case .fleeing = state, !isReceiving else { return }
        if iconScreenRect().contains(NSEvent.mouseLocation) {
            // Caught! Start the shake, talk some trash, then accept its fate.
            state = .shaking(start: now(), base: panel.frame.origin)
            blurtTrashTalk()
        }
    }

    // MARK: - Trash talk

    private func blurtTrashTalk() {
        let text = Self.trashTalk.randomElement() ?? "哼。"
        speechLabel.stringValue = text

        // Size the bubble to the text (plus padding) and center it above the can.
        let fit = speechLabel.sizeThatFits(NSSize(width: Const.canvas, height: 40))
        let w = min(Const.canvas - 8, fit.width + 18)
        let h = fit.height + 8
        let x = (Const.canvas - w) / 2
        let y = Const.canvas - h - 6
        speechLabel.frame = NSRect(x: x, y: y, width: w, height: h)

        speechLabel.isHidden = false
        speechLabel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            speechLabel.animator().alphaValue = 1
        }

        // Auto-dismiss so it doesn't linger the whole subdued spell.
        speechHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hideSpeech() }
        speechHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    private func hideSpeech() {
        speechHideWork?.cancel()
        speechHideWork = nil
        guard !speechLabel.isHidden else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            speechLabel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.speechLabel.isHidden = true
        })
    }

    // MARK: - Drag-to-trash

    /// While the user holds the mouse with a fresh file drag in progress, freeze
    /// the can and let it accept the drop instead of running away.
    private func updateDragReceiving() {
        let pb = NSPasteboard(name: .drag)
        let hasFreshFiles = isMouseDown
            && pb.changeCount > mouseDownDragSeq
            && (pb.types?.contains(.fileURL) ?? false)

        if hasFreshFiles && !isReceiving {
            isReceiving = true
            panel.ignoresMouseEvents = false   // become a real drop target
        } else if !hasFreshFiles && isReceiving {
            isReceiving = false
            panel.ignoresMouseEvents = true    // back to playful click-through
        }
    }

    private func recycle(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.recycle(urls) { [weak self] _, _ in
            // Confirm the real Trash state once the move finishes.
            self?.onRecycled?()
        }
        // Instant feedback: it just swallowed something, so it's full now.
        setTrashEmpty(false)
        onRecycled?()
        gulp()
    }

    /// The "om-nom" when it swallows a dropped file: a quick squash-and-stretch
    /// chomp that reads as the can gulping the item down, then settling.
    private func gulp() {
        lastGulpAt = now()
        guard let layer = imageView.layer else { return }

        func scale(_ sx: CGFloat, _ sy: CGFloat) -> CATransform3D {
            CATransform3DMakeScale(sx, sy, 1)
        }

        let anim = CAKeyframeAnimation(keyPath: "transform")
        anim.values = [
            scale(1.00, 1.00),
            scale(1.20, 0.80),   // mouth opens wide / lid pops — squash down
            scale(0.84, 1.18),   // gulp! sucks it in and stretches tall
            scale(1.08, 0.94),   // overshoot back
            scale(0.97, 1.03),
            scale(1.00, 1.00),   // settle
        ].map { NSValue(caTransform3D: $0) }
        anim.keyTimes = [0, 0.18, 0.46, 0.68, 0.85, 1]
        anim.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeOut),
        ]
        anim.duration = 0.5
        layer.add(anim, forKey: "gulp")
    }

    /// A light upward bounce — used when the Trash gets emptied from outside.
    private func reliefPop() {
        guard let layer = imageView.layer else { return }
        let anim = CAKeyframeAnimation(keyPath: "transform.scale")
        anim.values = [1.0, 1.16, 0.94, 1.02, 1.0]
        anim.keyTimes = [0, 0.35, 0.65, 0.85, 1]
        anim.duration = 0.45
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(anim, forKey: "react")
    }

    /// A startled side-to-side wobble — used when the Trash fills up from outside.
    private func heavyJiggle() {
        guard let layer = imageView.layer else { return }
        let a: CGFloat = 0.13
        let anim = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        anim.values = [0, a, -a, a * 0.55, -a * 0.55, 0]
        anim.keyTimes = [0, 0.15, 0.4, 0.6, 0.82, 1]
        anim.duration = 0.5
        layer.add(anim, forKey: "react")
    }

    // MARK: - Animation loop

    private func startTimer() {
        let t = Timer(timeInterval: Const.frameInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        updateDragReceiving()

        switch state {
        case .fleeing:
            if isReceiving { return } // frozen, acting as a drop target
            stepFleeing()
        case .shaking(let start, let base):
            stepShaking(start: start, base: base)
        case .subdued(let until):
            if now() >= until {
                endSubdued()
            }
        case .summoned(let until):
            // Hold still in the corner; resume fleeing once the spell ends.
            if now() >= until {
                state = .fleeing
                scheduleNextTired()
            }
        }
    }

    private func stepFleeing() {
        let t = now()

        // Tiredness bookkeeping.
        if t >= nextTiredAt {
            tiredUntil = t + Const.tiredDuration
            scheduleNextTired()
        }
        let tiredFactor: CGFloat = (t < tiredUntil) ? Const.tiredFactor : 1.0

        let mouse = NSEvent.mouseLocation
        let frame = panel.frame
        let center = CGPoint(x: frame.midX, y: frame.midY)

        // Vector pointing away from the cursor.
        let away = CGVector(dx: center.x - mouse.x, dy: center.y - mouse.y)
        let dist = max(hypot(away.dx, away.dy), 0.0001)

        guard dist < Const.triggerDistance else { return }

        // Closer cursor => faster escape.
        let maxSpeed = isDragging ? Const.maxSpeedDragging : Const.maxSpeedNormal
        let proximity = 1 - (dist / Const.triggerDistance) // 0..1
        let speed = maxSpeed * (0.35 + 0.65 * proximity) * tiredFactor

        // Normalize and add a panicky ±15° wobble.
        var dir = CGVector(dx: away.dx / dist, dy: away.dy / dist)
        dir = rotate(dir, byDegrees: CGFloat.random(in: -Const.randomWobbleDegrees...Const.randomWobbleDegrees))

        var origin = frame.origin
        origin.x += dir.dx * speed
        origin.y += dir.dy * speed

        // Steer away from screen edges before crossing them.
        origin = clampWithinScreen(origin: origin, currentDir: &dir, speed: speed)

        panel.setFrameOrigin(origin)
    }

    private func stepShaking(start: TimeInterval, base: CGPoint) {
        let elapsed = now() - start
        if elapsed >= Const.shakeDuration {
            panel.setFrameOrigin(base)
            enterSubdued()
            return
        }
        let phase = (elapsed / Const.shakeDuration) * Double(Const.shakeCycles) * 2 * .pi
        let offset = sin(phase) * Double(Const.shakeAmplitude)
        panel.setFrameOrigin(CGPoint(x: base.x + CGFloat(offset), y: base.y))
    }

    private func enterSubdued() {
        state = .subdued(until: now() + Const.subduedDuration)
        tipOver(true)
        faceLabel.isHidden = false
    }

    private func endSubdued() {
        faceLabel.isHidden = true
        hideSpeech()
        tipOver(false)
        state = .fleeing
        scheduleNextTired()
    }

    /// Falls over (倒下) onto its side when caught, and springs back up on recovery.
    private func tipOver(_ down: Bool) {
        guard let layer = imageView.layer else { return }
        let angle: CGFloat = down ? (-.pi / 2 * 0.9) : 0 // knock it to the right
        let target = tipTransform(angle)

        if down {
            // Fall with gravity (ease-in) and a small bounce as it lands.
            let anim = CAKeyframeAnimation(keyPath: "transform")
            anim.values = [
                tipTransform(0),
                tipTransform(angle * 1.08),
                tipTransform(angle),
            ].map { NSValue(caTransform3D: $0) }
            anim.keyTimes = [0, 0.82, 1]
            anim.timingFunctions = [
                CAMediaTimingFunction(name: .easeIn),
                CAMediaTimingFunction(name: .easeOut),
            ]
            anim.duration = 0.55
            layer.add(anim, forKey: "tip")
        } else {
            let anim = CABasicAnimation(keyPath: "transform")
            anim.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? layer.transform)
            anim.toValue = NSValue(caTransform3D: target)
            anim.duration = 0.35
            anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(anim, forKey: "tip")
        }
        layer.transform = target
    }

    /// Rotation about the can's bottom-center so it pivots like a falling object.
    private func tipTransform(_ angle: CGFloat) -> CATransform3D {
        let h = Const.size
        let plus = CATransform3DMakeTranslation(0, -h / 2, 0)
        let rot = CATransform3DMakeRotation(angle, 0, 0, 1)
        let minus = CATransform3DMakeTranslation(0, h / 2, 0)
        return CATransform3DConcat(CATransform3DConcat(plus, rot), minus)
    }

    // MARK: - Helpers

    private func scheduleNextTired() {
        nextTiredAt = now() + Double.random(in: Const.tiredIntervalMin...Const.tiredIntervalMax)
    }

    private func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func rotate(_ v: CGVector, byDegrees deg: CGFloat) -> CGVector {
        let r = deg * .pi / 180
        return CGVector(
            dx: v.dx * cos(r) - v.dy * sin(r),
            dy: v.dx * sin(r) + v.dy * cos(r)
        )
    }

    /// Screen-space rect of the *visible* icon (not the whole transparent window).
    private func iconScreenRect() -> NSRect {
        NSRect(x: panel.frame.minX + pad,
               y: panel.frame.minY + pad,
               width: Const.size,
               height: Const.size)
    }

    /// Origin bounds that keep the visible icon on screen (the canvas may hang off).
    private func startBounds() -> (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) {
        let area = currentScreenFrame()
        return (
            minX: area.minX + Const.edgeMargin - pad,
            maxX: area.maxX - Const.size - Const.edgeMargin - pad,
            minY: area.minY + Const.edgeMargin - pad,
            maxY: area.maxY - Const.size - Const.edgeMargin - pad
        )
    }

    /// Keeps the visible icon on screen; bounces the direction off edges so it
    /// veers away instead of stalling in a corner.
    private func clampWithinScreen(origin: CGPoint, currentDir: inout CGVector, speed: CGFloat) -> CGPoint {
        let b = startBounds()
        var p = origin
        if p.x < b.minX { p.x = b.minX; currentDir.dx = abs(currentDir.dx) }
        if p.x > b.maxX { p.x = b.maxX; currentDir.dx = -abs(currentDir.dx) }
        if p.y < b.minY { p.y = b.minY; currentDir.dy = abs(currentDir.dy) }
        if p.y > b.maxY { p.y = b.maxY; currentDir.dy = -abs(currentDir.dy) }
        return p
    }

    private func currentScreenFrame() -> NSRect {
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }
}

// MARK: - Drop target

/// A transparent view over the visible can that accepts file drops and forwards
/// them to be moved into the system Trash.
private final class TrashDropView: NSView {

    var onDrop: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        let objs = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
        return (objs as? [URL]) ?? []
    }

    /// Pick an operation the drag source actually allows.
    private func operation(for sender: NSDraggingInfo) -> NSDragOperation {
        guard !fileURLs(from: sender).isEmpty else { return [] }
        let mask = sender.draggingSourceOperationMask
        for op in [NSDragOperation.move, .copy, .generic, .link] where mask.contains(op) {
            return op
        }
        return mask.isEmpty ? [] : .generic
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        operation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        operation(for: sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !fileURLs(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
}
