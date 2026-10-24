import AppKit
import Combine
import SwiftUI

/// The dog's coat. The raw values are the stored keys from when the pet was a cat, so a saved
/// choice carries over.
enum CatColor: String, CaseIterable, Identifiable {
    case ginger, midnight, smoke, snow
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ginger: "Golden"
        case .midnight: "Black"
        case .smoke: "Grey"
        case .snow: "White"
        }
    }

    var fur: Color {
        switch self {
        case .ginger: Color(red: 0.93, green: 0.7, blue: 0.38)
        case .midnight: Color(white: 0.17)
        case .smoke: Color(red: 0.6, green: 0.62, blue: 0.66)
        case .snow: Color(white: 0.96)
        }
    }

    /// Ears and tail tip.
    var ear: Color {
        switch self {
        case .ginger: Color(red: 0.76, green: 0.48, blue: 0.2)
        case .midnight: Color(white: 0.09)
        case .smoke: Color(red: 0.42, green: 0.44, blue: 0.5)
        case .snow: Color(red: 0.74, green: 0.52, blue: 0.34)
        }
    }

    /// Snout and chest.
    var muzzle: Color {
        switch self {
        case .ginger: Color(red: 1, green: 0.88, blue: 0.7)
        case .midnight: Color(white: 0.3)
        case .smoke: Color(red: 0.84, green: 0.85, blue: 0.88)
        case .snow: Color.white
        }
    }
}

/// How often a happy pet gets the urge to chase the pointer.
enum Playfulness: String, CaseIterable, Identifiable {
    case off, rarely, sometimes, often
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Time between playful spells, so it is a mood and not a habit.
    var interval: ClosedRange<TimeInterval>? {
        switch self {
        case .off: nil
        case .rarely: 45 * 60...90 * 60
        case .sometimes: 15 * 60...30 * 60
        case .often: 4 * 60...8 * 60
        }
    }
}

/// Where the Feed button is.
enum PetFeeding: String, CaseIterable, Identifiable {
    /// A small card over the pet when the pointer rests on it.
    case hover
    /// The pet's tile in the notch's Widgets tab; nothing pops up on the desktop.
    case notch
    var id: String { rawValue }
    var title: String { self == .hover ? "Hover card" : "The notch" }
}

/// Where the pet lives.
enum CatPlacement: String, CaseIterable, Identifiable {
    /// Along the top of the Dock, free to roam the whole screen when it plays.
    case screen
    /// In the menu bar beside the notch, small enough to fit, and never anywhere else.
    case notch
    var id: String { rawValue }
    var title: String { self == .screen ? "On the screen" : "On the notch" }
}

/// The cat's needs. Fullness drains over about ten hours and affection over six; both survive
/// relaunches. Feeding and petting fill them back up.
final class CatBrain: ObservableObject {
    enum Mood {
        case happy, content, hungry, starving

        var title: String {
            switch self {
            case .happy: "Happy"
            case .content: "Content"
            case .hungry: "Hungry"
            case .starving: "Starving"
            }
        }
    }

    enum Pose: Equatable {
        case walk, sit, sleep, eat
    }

    @Published private(set) var fullness: Double
    @Published private(set) var affection: Double
    @Published var pose: Pose = .sit
    /// When the last hearts started (petting or feeding), for the floating-hearts animation.
    @Published private(set) var heartsAt: Date?

    /// Called once each time the cat gets hungry.
    var onHungry: ((String) -> Void)?

    private let defaults: UserDefaults
    private let settings: AppSettings
    private var updated: Date
    private var timer: Timer?
    private var announcedHunger = false

    static let fullnessPerHour = 0.1
    static let affectionPerHour = 1.0 / 6

    init(settings: AppSettings, live: Bool = true) {
        self.settings = settings
        defaults = live ? .standard : UserDefaults(suiteName: "com.premprateek.notchdeck.previews") ?? .standard
        fullness = live ? defaults.object(forKey: "cat.fullness") as? Double ?? 0.8 : 0.62
        affection = live ? defaults.object(forKey: "cat.affection") as? Double ?? 0.6 : 0.8
        updated = live ? defaults.object(forKey: "cat.updated") as? Date ?? Date() : Date()
        guard live else { return }
        decay()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.decay() }
    }

    var happiness: Double { 0.65 * fullness + 0.35 * affection }

    var mood: Mood {
        if fullness < 0.1 { return .starving }
        if fullness < 0.3 { return .hungry }
        return happiness > 0.6 ? .happy : .content
    }

    var isHungry: Bool { fullness < 0.3 }

    var hungerText: String {
        switch fullness {
        case 0.85...: "Full"
        case 0.55...: "Satisfied"
        case 0.3...: "Peckish"
        case 0.1...: "Hungry"
        default: "Starving"
        }
    }

    func feed() {
        decay()
        fullness = min(1, fullness + 0.45)
        affection = min(1, affection + 0.1)
        announcedHunger = false
        pose = .eat
        heartsAt = Date()
        save()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
            if self?.pose == .eat { self?.pose = .sit }
        }
    }

    func pet() {
        decay()
        affection = min(1, affection + 0.2)
        heartsAt = Date()
        if pose == .sleep { pose = .sit }
        save()
    }

    private func decay() {
        let now = Date()
        let hours = now.timeIntervalSince(updated) / 3600
        updated = now
        fullness = max(0, fullness - hours * Self.fullnessPerHour)
        affection = max(0, affection - hours * Self.affectionPerHour)
        save()
        if isHungry, !announcedHunger {
            announcedHunger = true
            onHungry?(settings.catName)
        }
    }

    private func save() {
        defaults.set(fullness, forKey: "cat.fullness")
        defaults.set(affection, forKey: "cat.affection")
        defaults.set(updated, forKey: "cat.updated")
    }
}

// MARK: Drawing

/// A side-on dog in a 100 × 72 box, feet on the bottom edge, facing right. (The type keeps its
/// old name; the pet was a cat once.)
struct CatFigure: View {
    let pose: CatBrain.Pose
    let mood: CatBrain.Mood
    let color: CatColor
    /// Walk cycle phase in radians; also drives the tail, the tongue and blinking.
    let time: Double

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 100, size.height / 72)
            context.scaleBy(x: scale, y: scale)
            draw(in: &context)
        }
    }

    private func draw(in context: inout GraphicsContext) {
        let fur = GraphicsContext.Shading.color(color.fur)
        let ear = GraphicsContext.Shading.color(color.ear)
        let muzzle = GraphicsContext.Shading.color(color.muzzle)
        let outline = GraphicsContext.Shading.color(.black.opacity(0.28))
        let droop = mood == .starving ? 1.0 : (mood == .hungry ? 0.5 : 0)
        let happy = mood == .happy
        let t = time
        // A happy dog's tail goes faster.
        let wag = sin(t * (happy ? 2.6 : 1.2)) * (happy ? 1 : 0.5)

        context.fill(Path(ellipseIn: CGRect(x: 16, y: 66, width: 70, height: 6)), with: .color(.black.opacity(0.18)))

        switch pose {
        case .sleep:
            // Curled up, tail round the front, chin on the paws.
            var tail = Path()
            tail.move(to: CGPoint(x: 22, y: 60))
            tail.addQuadCurve(to: CGPoint(x: 58, y: 68), control: CGPoint(x: 24, y: 72))
            context.stroke(tail, with: fur, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            let breathe = 1 + 0.03 * sin(t * 1.2)
            let body = Path(ellipseIn: CGRect(x: 14, y: 66 - 28 * breathe, width: 62, height: 28 * breathe))
            context.fill(body, with: fur)
            context.stroke(body, with: outline, lineWidth: 0.8)
            context.fill(Path(ellipseIn: CGRect(x: 60, y: 61, width: 22, height: 7)), with: muzzle)
            head(&context, center: CGPoint(x: 72, y: 52), fur: fur, ear: ear, muzzle: muzzle, outline: outline,
                 eyes: .closed, droop: 1, tongue: false, tilt: 8)
            for i in 0..<3 {
                let phase = (t * 0.5 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
                let text = Text("z").font(.system(size: 7 + CGFloat(i) * 2, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85 * (1 - phase)))
                context.draw(text, at: CGPoint(x: 86 + phase * 10, y: 38 - phase * 30))
            }

        case .sit:
            tail(&context, from: CGPoint(x: 30, y: 54), to: CGPoint(x: 14 + wag * 6, y: 34 - abs(wag) * 3 + droop * 18),
                 control: CGPoint(x: 14, y: 54), fur: fur, ear: ear)
            let haunch = Path(ellipseIn: CGRect(x: 24, y: 38, width: 38, height: 30))
            context.fill(haunch, with: fur)
            context.stroke(haunch, with: outline, lineWidth: 0.8)
            let paw = Path(ellipseIn: CGRect(x: 22, y: 61, width: 18, height: 7))
            context.fill(paw, with: fur)
            context.stroke(paw, with: outline, lineWidth: 0.6)
            let chest = Path(ellipseIn: CGRect(x: 44, y: 24, width: 28, height: 42))
            context.fill(chest, with: fur)
            context.fill(Path(ellipseIn: CGRect(x: 55, y: 32, width: 14, height: 24)), with: muzzle)
            for x in [52.0, 61.0] {
                let leg = Path(roundedRect: CGRect(x: x, y: 46, width: 8, height: 22), cornerRadius: 4)
                context.fill(leg, with: fur)
                context.stroke(leg, with: outline, lineWidth: 0.6)
            }
            head(&context, center: CGPoint(x: 62, y: 20), fur: fur, ear: ear, muzzle: muzzle, outline: outline,
                 eyes: happy ? .happy : (blinking(t) ? .closed : .open), droop: droop, tongue: happy, tilt: 0)

        case .walk, .eat:
            let walking = pose == .walk
            let bob = walking ? abs(sin(t)) * 1.5 : 0
            tail(&context, from: CGPoint(x: 20, y: 36 - bob), to: CGPoint(x: 6 + wag * 5, y: 18 + droop * 20),
                 control: CGPoint(x: 6, y: 34), fur: fur, ear: ear)
            let swing = walking ? sin(t) * 0.45 : 0
            let legs: [(Double, Double)] = [(26, swing), (34, -swing), (60, -swing), (68, swing)]
            for (x, angle) in legs {
                var leg = context
                leg.translateBy(x: x + 4, y: 48 - bob)
                leg.rotate(by: .radians(angle))
                let shape = Path(roundedRect: CGRect(x: -4, y: 0, width: 8, height: 20), cornerRadius: 4)
                leg.fill(shape, with: x == 34 || x == 68 ? .color(color.fur.opacity(0.8)) : fur)
                leg.stroke(shape, with: outline, lineWidth: 0.6)
            }
            let body = Path(roundedRect: CGRect(x: 16, y: 30 - bob, width: 62, height: 24), cornerRadius: 12)
            context.fill(body, with: fur)
            context.stroke(body, with: outline, lineWidth: 0.8)
            context.fill(Path(ellipseIn: CGRect(x: 56, y: 40 - bob, width: 20, height: 13)), with: muzzle)
            if pose == .eat {
                let chomp = sin(t * 3) * 1.5
                head(&context, center: CGPoint(x: 78, y: 48 + chomp), fur: fur, ear: ear, muzzle: muzzle, outline: outline,
                     eyes: .happy, droop: 0, tongue: false, tilt: 14)
                bowl(&context)
            } else {
                head(&context, center: CGPoint(x: 78, y: 24 - bob), fur: fur, ear: ear, muzzle: muzzle, outline: outline,
                     eyes: blinking(t) ? .closed : .open, droop: droop, tongue: happy && walking, tilt: 0)
            }
        }
    }

    private enum Eyes { case open, closed, happy }

    private func tail(_ context: inout GraphicsContext, from: CGPoint, to: CGPoint, control: CGPoint,
                      fur: GraphicsContext.Shading, ear: GraphicsContext.Shading) {
        var tail = Path()
        tail.move(to: from)
        tail.addQuadCurve(to: to, control: control)
        context.stroke(tail, with: fur, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        context.fill(Path(ellipseIn: CGRect(x: to.x - 3, y: to.y - 3, width: 6, height: 6)), with: ear)
    }

    /// Head facing right: round skull, a snout with a black nose, one floppy ear, and a tongue
    /// when it's happy. `tilt` turns the head down (degrees), for sleeping and eating.
    private func head(_ context: inout GraphicsContext, center c: CGPoint, fur: GraphicsContext.Shading,
                      ear: GraphicsContext.Shading, muzzle: GraphicsContext.Shading, outline: GraphicsContext.Shading,
                      eyes: Eyes, droop: Double, tongue: Bool, tilt: Double) {
        var g = context
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .degrees(tilt))
        let skull = Path(ellipseIn: CGRect(x: -12, y: -12, width: 25, height: 23))
        g.fill(skull, with: fur)
        g.stroke(skull, with: outline, lineWidth: 0.8)
        let snout = Path(roundedRect: CGRect(x: 4, y: -1, width: 18, height: 12), cornerRadius: 6)
        g.fill(snout, with: muzzle)
        g.stroke(snout, with: outline, lineWidth: 0.6)
        g.fill(Path(ellipseIn: CGRect(x: 17.5, y: -2.5, width: 6.5, height: 5.5)), with: .color(Color(white: 0.08)))
        g.fill(Path(ellipseIn: CGRect(x: 19, y: -1.8, width: 2, height: 1.4)), with: .color(.white.opacity(0.6)))
        var mouth = Path()
        mouth.move(to: CGPoint(x: 11, y: 8.5))
        mouth.addQuadCurve(to: CGPoint(x: 20, y: 7.5), control: CGPoint(x: 16, y: 11))
        g.stroke(mouth, with: .color(.black.opacity(0.55)), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
        if tongue {
            let lick = 6 + sin(time * 5) * 1.2
            let t = Path(roundedRect: CGRect(x: 13, y: 8.5, width: 5.5, height: lick), cornerRadius: 2.7)
            g.fill(t, with: .color(Color(red: 1, green: 0.45, blue: 0.55)))
        }
        // Eye.
        let p = CGPoint(x: 3, y: -4)
        switch eyes {
        case .open:
            g.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2.4, width: 4, height: 4.8)), with: .color(Color(white: 0.08)))
            g.fill(Path(ellipseIn: CGRect(x: p.x - 0.3, y: p.y - 1.8, width: 1.5, height: 1.5)), with: .color(.white))
        case .closed:
            var lid = Path()
            lid.move(to: CGPoint(x: p.x - 2.5, y: p.y))
            lid.addQuadCurve(to: CGPoint(x: p.x + 2.5, y: p.y), control: CGPoint(x: p.x, y: p.y + 2.2))
            g.stroke(lid, with: .color(.black.opacity(0.75)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        case .happy:
            var arc = Path()
            arc.move(to: CGPoint(x: p.x - 2.5, y: p.y + 1))
            arc.addQuadCurve(to: CGPoint(x: p.x + 2.5, y: p.y + 1), control: CGPoint(x: p.x, y: p.y - 3))
            g.stroke(arc, with: .color(.black.opacity(0.75)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        }
        // The floppy ear, over the back of the head; it hangs lower when the dog is unhappy.
        let fall = droop * 3
        var flap = Path()
        flap.move(to: CGPoint(x: -3, y: -11))
        flap.addQuadCurve(to: CGPoint(x: -13, y: 2 + fall), control: CGPoint(x: -15, y: -11))
        flap.addQuadCurve(to: CGPoint(x: -6, y: 11 + fall), control: CGPoint(x: -15, y: 12 + fall))
        flap.addQuadCurve(to: CGPoint(x: 1, y: -6), control: CGPoint(x: -2, y: 2))
        flap.closeSubpath()
        g.fill(flap, with: ear)
        g.stroke(flap, with: outline, lineWidth: 0.6)
    }

    private func bowl(_ context: inout GraphicsContext) {
        var bowl = Path()
        bowl.move(to: CGPoint(x: 74, y: 60))
        bowl.addLine(to: CGPoint(x: 100, y: 60))
        bowl.addQuadCurve(to: CGPoint(x: 76, y: 60), control: CGPoint(x: 88, y: 76))
        context.fill(bowl, with: .color(Color(red: 0.95, green: 0.35, blue: 0.35)))
        context.fill(Path(ellipseIn: CGRect(x: 78, y: 57, width: 18, height: 5)), with: .color(Color(red: 0.6, green: 0.38, blue: 0.2)))
    }

    private func blinking(_ t: Double) -> Bool {
        (t * 0.35).truncatingRemainder(dividingBy: 4) < 0.08
    }
}

/// Hearts that float up for a moment after petting or feeding.
struct CatHearts: View {
    let since: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: since.map { Date().timeIntervalSince($0) > 1.8 } ?? true)) { context in
            let elapsed = since.map { context.date.timeIntervalSince($0) } ?? 99
            ZStack {
                if elapsed < 1.8 {
                    ForEach(0..<3, id: \.self) { i in
                        let p = min(max((elapsed - Double(i) * 0.25) / 1.3, 0), 1)
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10 + CGFloat(i) * 2))
                            .foregroundStyle(Color(red: 1, green: 0.4, blue: 0.55))
                            .opacity(p > 0 ? 1 - p : 0)
                            .offset(x: CGFloat(i - 1) * 12 + sin(p * 6 + Double(i)) * 4, y: -p * 34)
                    }
                }
            }
        }
    }
}

// MARK: The desktop window

/// Moves the cat around: along the top of the Dock, or in the menu bar beside the notch. It
/// wanders, sits, naps and comes to eat, and when it's in a playful mood it chases the pointer.
final class DesktopCat {
    private let brain: CatBrain
    private let settings: AppSettings
    private var window: NSPanel?
    private var timer: Timer?
    private var bag = Set<AnyCancellable>()
    private let state = DesktopCatState()

    /// Where the cat's feet are: `x` is the middle of the cat, `feet` its bottom edge. A nil
    /// `feet` means on the floor (the Dock, or the menu bar in notch mode).
    private var x: CGFloat = 200
    private var feet: CGFloat?
    private var targetX: CGFloat?
    private var poseUntil = Date()
    private var playUntil: Date?
    /// The earliest the next playful spell may start.
    private var nextPlay = Date()
    private var lastTick = Date()
    private var lastMouse = CGPoint.zero
    /// When the pointer was last MOVED onto the pet; the card waits for it to rest there.
    private var hoverSince: Date?

    /// The window around the cat in screen mode, at size 1: room for the card above it.
    static let base = CGSize(width: 180, height: 150)
    /// The cat drawing's own box.
    static let figure = CGSize(width: 100, height: 72)

    init(brain: CatBrain, settings: AppSettings) {
        self.brain = brain
        self.settings = settings
        settings.$catEnabled.removeDuplicates()
            .sink { [weak self] on in DispatchQueue.main.async { on ? self?.start() : self?.stop() } }
            .store(in: &bag)
        settings.$catSize.dropFirst().removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.relayout() } }
            .store(in: &bag)
        settings.$catPlacement.dropFirst().removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.relayout(moveHome: true) } }
            .store(in: &bag)
        // Feeding from the notch needs the dog's tile there to feed it from.
        settings.$catFeeding.removeDuplicates().filter { $0 == .notch }
            .sink { _ in
                DispatchQueue.main.async {
                    if !settings.widgets.contains(where: { $0.kind == .cat }) {
                        settings.widgets.append(WidgetItem(kind: .cat))
                    }
                }
            }
            .store(in: &bag)
        settings.$catPlayfulness.removeDuplicates()
            .sink { [weak self] level in
                DispatchQueue.main.async {
                    if level == .off { self?.endPlay() }
                    self?.scheduleNextPlay(level)
                }
            }
            .store(in: &bag)
    }

    private var onNotch: Bool { settings.catPlacement == .notch }

    /// The screen the cat lives on: the one with the notch in notch mode, else the main one.
    private var screen: NSScreen? {
        onNotch ? (NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main) : NSScreen.main
    }

    /// Height of the band beside the notch the cat sits in.
    private func barHeight(_ screen: NSScreen) -> CGFloat { NotchGeometry.of(screen, island: false).notchSize.height }

    /// The cat's drawing scale.
    private func catScale(_ screen: NSScreen) -> CGFloat {
        onNotch ? (barHeight(screen) - 3) / Self.figure.height : CGFloat(settings.catSize)
    }

    private func windowSize(_ screen: NSScreen) -> CGSize {
        let s = catScale(screen)
        if onNotch {
            // The cat on top, the card hanging below it into the desktop when hovered.
            return CGSize(width: 250, height: Self.figure.height * s + 82)
        }
        return CGSize(width: Self.base.width * s, height: Self.base.height * s)
    }

    /// The x range the cat may walk in. On the notch: from a little left of it to a little right,
    /// passing behind it (it disappears into the notch and comes out the other side).
    private func walkRange(_ screen: NSScreen) -> ClosedRange<CGFloat> {
        let frame = screen.frame
        if onNotch {
            let notch = NotchGeometry.of(screen, island: false).notchSize.width
            let reach = notch / 2 + 110
            return (frame.midX - reach)...(frame.midX + reach)
        }
        let half = windowSize(screen).width / 2
        return (screen.visibleFrame.minX + half)...(screen.visibleFrame.maxX - half)
    }

    private func floor(_ screen: NSScreen) -> CGFloat {
        onNotch ? screen.frame.maxY - barHeight(screen) + 1 : screen.visibleFrame.minY
    }

    private func start() {
        guard window == nil, let screen else { return }
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: windowSize(screen)),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        let hosting = FirstMouseHostingView(rootView: DesktopCatView(brain: brain, settings: settings, state: state))
        hosting.sizingOptions = []
        panel.contentView = hosting
        window = panel
        relayout(moveHome: true)
        panel.orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window = nil
    }

    /// Re-applies size, level and layout after a settings change.
    private func relayout(moveHome: Bool = false) {
        guard let window, let screen else { return }
        // Notch mode sits in the menu bar, so it has to be above it; still under NotchDeck's own
        // panel (main menu + 3), which covers it when the notch opens.
        window.level = onNotch ? NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
                               : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        state.scale = catScale(screen)
        state.cardBelow = onNotch
        window.setContentSize(windowSize(screen))
        if moveHome {
            feet = nil
            targetX = nil
            let range = walkRange(screen)
            x = onNotch ? range.upperBound - 20 : screen.visibleFrame.midX + 260
        }
        x = min(max(x, walkRange(screen).lowerBound), walkRange(screen).upperBound)
        place()
    }

    private func place() {
        guard let window, let screen else { return }
        let size = windowSize(screen)
        let s = catScale(screen)
        let bottom = feet ?? floor(screen)
        if onNotch {
            // The cat is at the top of the window, the card below it.
            let top = bottom + Self.figure.height * s
            window.setFrameOrigin(CGPoint(x: x - size.width / 2, y: top - size.height))
        } else {
            window.setFrameOrigin(CGPoint(x: x - size.width / 2, y: bottom - 4 * s))
        }
    }

    /// Where the drawn cat is on screen, for hit-testing the pointer.
    private func catRect(_ screen: NSScreen) -> CGRect {
        let s = catScale(screen)
        let bottom = feet ?? floor(screen)
        return CGRect(x: x - Self.figure.width * s / 2 + 8 * s, y: bottom, width: (Self.figure.width - 16) * s,
                      height: Self.figure.height * s)
    }

    private func tick() {
        guard let window, let screen else { return }
        let now = Date()
        let dt = min(now.timeIntervalSince(lastTick), 0.1)
        lastTick = now

        // Let the mouse through except over the pet itself, or the card while it's open.
        let mouse = NSEvent.mouseLocation
        let movedPointer = mouse != lastMouse
        lastMouse = mouse
        let over = catRect(screen).contains(mouse) || (state.showCard && window.frame.contains(mouse))
        if window.ignoresMouseEvents == over { window.ignoresMouseEvents = !over }
        // The card is for a pointer YOU put on the pet and leave there: never when the pet walks
        // up to a still pointer, never while it plays, and not at all when feeding is in the notch.
        if !over {
            hoverSince = nil
        } else if hoverSince == nil, movedPointer, playUntil == nil {
            hoverSince = now
        }
        let wantsCard = settings.catFeeding == .hover && playUntil == nil
            && (state.showCard ? over : (hoverSince.map { now.timeIntervalSince($0) > 0.5 } ?? false))
        if wantsCard != state.hovering { state.hovering = wantsCard }

        if let until = playUntil {
            if now >= until || settings.catPlayfulness == .off { endPlay() } else { chase(mouse, screen: screen, dt: dt); return }
        }
        if state.hovering || brain.pose == .eat { return }

        // After playing on the screen it walks back down to the Dock.
        if let current = feet {
            let home = floor(screen)
            let step = 160 * catScale(screen) * CGFloat(dt)
            brain.pose = .walk
            feet = current - home <= step ? nil : current - step
            place()
            return
        }

        let speed: CGFloat = (brain.isHungry ? 24 : 42) * (onNotch ? 0.8 : catScale(screen))
        switch brain.pose {
        case .walk:
            guard let target = targetX else { decide(screen: screen); return }
            let step = min(abs(target - x), speed * CGFloat(dt))
            x += target > x ? step : -step
            state.facingRight = target > x
            place()
            if abs(target - x) < 1 { targetX = nil; decide(screen: screen) }
        case .sit, .sleep, .eat:
            if now >= poseUntil { decide(screen: screen) }
        }
    }

    /// Runs toward the pointer and stops just beside it, facing it. On the notch it only moves
    /// sideways; on the screen it leaves the Dock and follows anywhere.
    private func chase(_ mouse: CGPoint, screen: NSScreen, dt: Double) {
        let s = catScale(screen)
        let range = walkRange(screen)
        let side: CGFloat = mouse.x >= x ? -1 : 1
        let goalX = min(max(mouse.x + side * 34 * max(s, 0.6), range.lowerBound), range.upperBound)
        var goalFeet = feet ?? floor(screen)
        if !onNotch {
            let visible = screen.visibleFrame
            goalFeet = min(max(mouse.y - Self.figure.height * s * 0.45, visible.minY),
                           visible.maxY - Self.figure.height * s)
        }
        let currentFeet = feet ?? floor(screen)
        let dx = goalX - x, dy = goalFeet - currentFeet
        let distance = (dx * dx + dy * dy).squareRoot()
        state.facingRight = mouse.x > x
        if distance < 6 {
            if brain.pose != .sit { brain.pose = .sit }
            return
        }
        let step = min(distance, 170 * max(s, 0.6) * CGFloat(dt))
        x += dx / distance * step
        if !onNotch {
            let next = currentFeet + dy / distance * step
            feet = next - floor(screen) < 0.5 ? nil : next
        }
        if brain.pose != .walk { brain.pose = .walk }
        place()
    }

    private func beginPlay() {
        playUntil = Date().addingTimeInterval(.random(in: 18...40))
        targetX = nil
        state.playfulSince = Date()
        brain.pose = .walk
    }

    private func scheduleNextPlay(_ level: Playfulness? = nil) {
        guard let interval = (level ?? settings.catPlayfulness).interval else { return }
        nextPlay = Date().addingTimeInterval(.random(in: interval))
    }

    private func endPlay() {
        guard playUntil != nil else { return }
        playUntil = nil
        hoverSince = nil
        scheduleNextPlay()
        state.playfulSince = nil
        brain.pose = .sit
        poseUntil = Date().addingTimeInterval(.random(in: 3...6))
    }

    private func decide(screen: NSScreen) {
        let hour = Calendar.current.component(.hour, from: Date())
        let night = hour >= 23 || hour < 7
        // In the mood: a happy, awake cat now and then decides the pointer is prey.
        if settings.catPlayfulness != .off, !night, brain.mood == .happy, Date() >= nextPlay {
            beginPlay()
            return
        }
        let roll = Double.random(in: 0..<1)
        if brain.pose == .walk || roll < (night ? 0.55 : 0.25) {
            // Rest: a nap, or a sit.
            let nap = roll < (night ? 0.45 : 0.12) || brain.happiness < 0.2
            brain.pose = nap ? .sleep : .sit
            poseUntil = Date().addingTimeInterval(nap ? .random(in: 40...120) : .random(in: 4...12))
        } else {
            brain.pose = .walk
            targetX = CGFloat.random(in: walkRange(screen))
        }
    }
}

/// What the cat window's view needs from the controller.
final class DesktopCatState: ObservableObject {
    @Published var hovering = false
    @Published var facingRight = true
    @Published var showCard = false
    @Published var scale: CGFloat = 1
    /// On the notch the card hangs below the cat instead of above it.
    @Published var cardBelow = false
    /// When the current playful spell began, for the little sparkle; nil when not playing.
    @Published var playfulSince: Date?
}

private struct DesktopCatView: View {
    @ObservedObject var brain: CatBrain
    @ObservedObject var settings: AppSettings
    @ObservedObject var state: DesktopCatState

    var body: some View {
        let scale = state.scale
        VStack(spacing: 4 * max(scale, 0.6)) {
            if state.cardBelow {
                cat(scale)
                card(scale: 1)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                card(scale: scale)
                cat(scale)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: state.cardBelow ? .top : .bottom)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: state.hovering)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func card(scale: CGFloat) -> some View {
        if state.hovering {
            CatCard(brain: brain, name: settings.catName, compact: true)
                .scaleEffect(scale)
                .frame(height: 56 * scale)
                .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: state.cardBelow ? .top : .bottom)))
                .onAppear { state.showCard = true }
                .onDisappear { state.showCard = false }
        } else if brain.isHungry, brain.pose != .eat, !state.cardBelow {
            // A thought bubble with a bone in it.
            Text("🦴")
                .font(.system(size: 12 * scale))
                .padding(6 * scale)
                .background(Circle().fill(.white.opacity(0.9)))
                .offset(x: 26 * scale)
        }
    }

    private func cat(_ scale: CGFloat) -> some View {
        ZStack(alignment: .top) {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                let playing = state.playfulSince != nil
                let t = context.date.timeIntervalSinceReferenceDate * (brain.pose == .walk ? (playing ? 10 : 7) : 2)
                CatFigure(pose: brain.pose, mood: brain.mood, color: settings.catColor, time: t)
                    .scaleEffect(x: state.facingRight ? 1 : -1, y: 1)
                    .overlay(alignment: .topTrailing) {
                        // A short sparkle when the playful mood starts.
                        if let since = state.playfulSince, context.date.timeIntervalSince(since) < 2.5 {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14 * max(scale, 0.7), weight: .bold))
                                .foregroundStyle(Color(red: 1, green: 0.85, blue: 0.35))
                                .opacity(1 - context.date.timeIntervalSince(since) / 2.5)
                                .offset(x: 6 * scale, y: -8 * scale)
                        }
                    }
            }
            .frame(width: 100 * scale, height: 72 * scale)
            CatHearts(since: brain.heartsAt).offset(y: 6 * scale)
        }
        .contentShape(Rectangle())
        .onTapGesture { brain.pet() }
        .help("Click to pet \(settings.catName)")
    }
}

/// Name, mood, fullness and happiness, with Feed. Used over the desktop pet and in the Widgets tab.
struct CatCard: View {
    @ObservedObject var brain: CatBrain
    let name: String
    var compact = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(name).font(.system(size: 12, weight: .bold))
                    Text(brain.mood.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(brain.isHungry ? .orange : .green)
                }
                meter(symbol: "fork.knife", value: brain.fullness, tint: brain.isHungry ? .orange : .green,
                      help: brain.hungerText)
                meter(symbol: "heart.fill", value: brain.happiness, tint: Color(red: 1, green: 0.4, blue: 0.55),
                      help: "Happiness")
            }
            // Feed only: petting is a click on the pet itself.
            Button { brain.feed() } label: {
                Label("Feed", systemImage: "fork.knife").font(.system(size: 10.5, weight: .semibold))
            }
            .buttonStyle(CatButtonStyle(fill: Color(red: 0.35, green: 0.62, blue: 1)))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 10 : 0)
        .padding(.vertical, compact ? 7 : 0)
        .background {
            if compact {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.35)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.15)))
            }
        }
        .fixedSize()
    }

    private func meter(symbol: String, value: Double, tint: Color, help: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 8, weight: .bold)).foregroundStyle(tint).frame(width: 10)
            LevelBar(level: value, color: tint).frame(width: compact ? 70 : 56, height: 4)
        }
        .help(help)
    }
}

private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 9, weight: .bold))
            configuration.title
        }
    }
}

private struct CatButtonStyle: ButtonStyle {
    let fill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(TightLabelStyle())
            .frame(width: 58, height: 20)
            .background(Capsule().fill(fill.opacity(configuration.isPressed ? 0.7 : 1)))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}
