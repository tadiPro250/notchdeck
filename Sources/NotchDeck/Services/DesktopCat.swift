import AppKit
import Combine
import SwiftUI

enum CatColor: String, CaseIterable, Identifiable {
    case ginger, midnight, smoke, snow
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ginger: "Ginger"
        case .midnight: "Midnight"
        case .smoke: "Smoke"
        case .snow: "Snow"
        }
    }

    var fur: Color {
        switch self {
        case .ginger: Color(red: 0.96, green: 0.6, blue: 0.27)
        case .midnight: Color(white: 0.16)
        case .smoke: Color(red: 0.55, green: 0.58, blue: 0.63)
        case .snow: Color(white: 0.95)
        }
    }

    var stripe: Color {
        switch self {
        case .ginger: Color(red: 0.82, green: 0.42, blue: 0.13)
        case .midnight: Color(white: 0.08)
        case .smoke: Color(red: 0.42, green: 0.45, blue: 0.5)
        case .snow: Color(white: 0.84)
        }
    }

    var eye: Color { self == .midnight ? Color(red: 0.75, green: 0.95, blue: 0.3) : Color(white: 0.1) }
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

/// A side-on cat in a 100 × 72 box, feet on the bottom edge, facing right.
struct CatFigure: View {
    let pose: CatBrain.Pose
    let mood: CatBrain.Mood
    let color: CatColor
    /// Walk cycle phase in radians; also drives the tail and blinking.
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
        let stripe = GraphicsContext.Shading.color(color.stripe)
        let outline = GraphicsContext.Shading.color(.black.opacity(0.28))
        let droop = mood == .starving ? 1.0 : 0
        let t = time

        // Ground shadow.
        context.fill(Path(ellipseIn: CGRect(x: 18, y: 66, width: 66, height: 6)), with: .color(.black.opacity(0.18)))

        switch pose {
        case .sleep:
            // A loaf, tail wrapped round, head tucked in.
            var tail = Path()
            tail.move(to: CGPoint(x: 24, y: 62))
            tail.addQuadCurve(to: CGPoint(x: 70, y: 68), control: CGPoint(x: 30, y: 74))
            context.stroke(tail, with: stripe, style: StrokeStyle(lineWidth: 7, lineCap: .round))
            let breathe = 1 + 0.03 * sin(t * 1.2)
            let body = Path(ellipseIn: CGRect(x: 18, y: 66 - 30 * breathe, width: 62, height: 30 * breathe))
            context.fill(body, with: fur)
            context.stroke(body, with: outline, lineWidth: 0.8)
            stripes(&context, stripe, x: 34, y: 66 - 28 * breathe, count: 3, height: 9)
            head(&context, center: CGPoint(x: 76, y: 52), fur: fur, stripe: stripe, outline: outline,
                 eyes: .closed, earDroop: 0.5)
            // Floating Zs.
            for i in 0..<3 {
                let phase = (t * 0.5 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
                let text = Text("z").font(.system(size: 7 + CGFloat(i) * 2, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85 * (1 - phase)))
                context.draw(text, at: CGPoint(x: 84 + phase * 10, y: 38 - phase * 30))
            }
        case .walk, .sit, .eat:
            let walking = pose == .walk
            let sitting = pose == .sit
            let bob = walking ? abs(sin(t)) * 1.5 : 0
            // Tail.
            var tail = Path()
            let sway = sin(t * (walking ? 1 : 0.6)) * 6
            if sitting {
                tail.move(to: CGPoint(x: 40, y: 62))
                tail.addQuadCurve(to: CGPoint(x: 16 + sway * 0.4, y: 64), control: CGPoint(x: 20, y: 72))
                tail.addQuadCurve(to: CGPoint(x: 10, y: 52 + sway * 0.6), control: CGPoint(x: 8, y: 62))
            } else {
                tail.move(to: CGPoint(x: 22, y: 40 - bob))
                tail.addQuadCurve(to: CGPoint(x: 8 + sway, y: 14 + droop * 22),
                                  control: CGPoint(x: 4, y: 36 + droop * 10))
            }
            context.stroke(tail, with: stripe, style: StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round))

            if sitting {
                // Haunch and chest, upright.
                let haunch = Path(ellipseIn: CGRect(x: 30, y: 38, width: 40, height: 30))
                let chest = Path(ellipseIn: CGRect(x: 50, y: 28, width: 24, height: 38))
                context.fill(haunch, with: fur)
                context.stroke(haunch, with: outline, lineWidth: 0.8)
                context.fill(chest, with: fur)
                stripes(&context, stripe, x: 36, y: 40, count: 3, height: 10)
                for x in [56.0, 64.0] {
                    let leg = Path(roundedRect: CGRect(x: x, y: 52, width: 7, height: 16), cornerRadius: 3.5)
                    context.fill(leg, with: fur)
                    context.stroke(leg, with: outline, lineWidth: 0.6)
                }
                let blink = blinking(t)
                head(&context, center: CGPoint(x: 66, y: 22), fur: fur, stripe: stripe, outline: outline,
                     eyes: mood == .happy ? .happy : (blink ? .closed : .open), earDroop: droop)
            } else {
                // Legs first so the body overlaps them.
                let swing = walking ? sin(t) * 0.45 : 0
                let legs: [(Double, Double)] = [(28, swing), (36, -swing), (60, -swing), (68, swing)]
                for (x, angle) in legs {
                    var leg = context
                    leg.translateBy(x: x + 3.5, y: 50 - bob)
                    leg.rotate(by: .radians(angle))
                    let shape = Path(roundedRect: CGRect(x: -3.5, y: 0, width: 7, height: 18), cornerRadius: 3.5)
                    leg.fill(shape, with: x == 36 || x == 68 ? stripe : fur)
                    leg.stroke(shape, with: outline, lineWidth: 0.6)
                }
                let body = Path(roundedRect: CGRect(x: 18, y: 32 - bob, width: 60, height: 26), cornerRadius: 13)
                context.fill(body, with: fur)
                context.stroke(body, with: outline, lineWidth: 0.8)
                stripes(&context, stripe, x: 30, y: 33 - bob, count: 4, height: 9)
                if pose == .eat {
                    // Head down in the bowl, chomping.
                    let chomp = sin(t * 3) * 1.5
                    head(&context, center: CGPoint(x: 82, y: 50 + chomp), fur: fur, stripe: stripe, outline: outline,
                         eyes: .happy, earDroop: 0)
                    bowl(&context)
                } else {
                    head(&context, center: CGPoint(x: 80, y: 28 - bob), fur: fur, stripe: stripe, outline: outline,
                         eyes: blinking(t) ? .closed : .open, earDroop: droop)
                }
            }
        }
    }

    private enum Eyes { case open, closed, happy }

    private func head(_ context: inout GraphicsContext, center c: CGPoint, fur: GraphicsContext.Shading,
                      stripe: GraphicsContext.Shading, outline: GraphicsContext.Shading, eyes: Eyes, earDroop: Double) {
        // Ears, flattening when the cat is unhappy.
        let drop = earDroop * 5
        for side in [-1.0, 1.0] {
            var ear = Path()
            ear.move(to: CGPoint(x: c.x + side * 4, y: c.y - 10))
            ear.addLine(to: CGPoint(x: c.x + side * 8 + side * drop, y: c.y - 21 + drop * 1.4))
            ear.addLine(to: CGPoint(x: c.x + side * 13, y: c.y - 7))
            ear.closeSubpath()
            context.fill(ear, with: fur)
            context.stroke(ear, with: outline, lineWidth: 0.7)
            var inner = Path()
            inner.move(to: CGPoint(x: c.x + side * 6, y: c.y - 10))
            inner.addLine(to: CGPoint(x: c.x + side * 8.5 + side * drop, y: c.y - 17 + drop * 1.2))
            inner.addLine(to: CGPoint(x: c.x + side * 11, y: c.y - 9))
            inner.closeSubpath()
            context.fill(inner, with: .color(Color(red: 1, green: 0.7, blue: 0.75).opacity(0.85)))
        }
        let face = Path(ellipseIn: CGRect(x: c.x - 14, y: c.y - 12, width: 28, height: 24))
        context.fill(face, with: fur)
        context.stroke(face, with: outline, lineWidth: 0.8)
        // Forehead stripes.
        for dx in [-3.0, 0, 3] {
            var mark = Path()
            mark.move(to: CGPoint(x: c.x + dx, y: c.y - 11))
            mark.addLine(to: CGPoint(x: c.x + dx * 0.7, y: c.y - 6))
            context.stroke(mark, with: stripe, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
        // Eyes.
        for dx in [-5.5, 5.5] {
            let p = CGPoint(x: c.x + dx + 2, y: c.y - 1)
            switch eyes {
            case .open:
                context.fill(Path(ellipseIn: CGRect(x: p.x - 2.2, y: p.y - 3, width: 4.4, height: 6)),
                             with: .color(color.eye))
                context.fill(Path(ellipseIn: CGRect(x: p.x - 0.4, y: p.y - 2.2, width: 1.6, height: 1.8)),
                             with: .color(.white))
            case .closed:
                var lid = Path()
                lid.move(to: CGPoint(x: p.x - 2.5, y: p.y))
                lid.addQuadCurve(to: CGPoint(x: p.x + 2.5, y: p.y), control: CGPoint(x: p.x, y: p.y + 2.2))
                context.stroke(lid, with: .color(.black.opacity(0.75)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            case .happy:
                var arc = Path()
                arc.move(to: CGPoint(x: p.x - 2.5, y: p.y + 1))
                arc.addQuadCurve(to: CGPoint(x: p.x + 2.5, y: p.y + 1), control: CGPoint(x: p.x, y: p.y - 3))
                context.stroke(arc, with: .color(.black.opacity(0.75)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            }
        }
        // Nose, mouth, cheeks, whiskers.
        var nose = Path()
        nose.move(to: CGPoint(x: c.x + 0.5, y: c.y + 4))
        nose.addLine(to: CGPoint(x: c.x + 4.5, y: c.y + 4))
        nose.addLine(to: CGPoint(x: c.x + 2.5, y: c.y + 6.5))
        nose.closeSubpath()
        context.fill(nose, with: .color(Color(red: 0.95, green: 0.45, blue: 0.55)))
        context.fill(Path(ellipseIn: CGRect(x: c.x - 11, y: c.y + 3, width: 5, height: 3)),
                     with: .color(Color(red: 1, green: 0.5, blue: 0.6).opacity(0.35)))
        context.fill(Path(ellipseIn: CGRect(x: c.x + 8, y: c.y + 3, width: 5, height: 3)),
                     with: .color(Color(red: 1, green: 0.5, blue: 0.6).opacity(0.35)))
        for dy in [-1.0, 1.5] {
            var whisker = Path()
            whisker.move(to: CGPoint(x: c.x + 8, y: c.y + 6))
            whisker.addLine(to: CGPoint(x: c.x + 19, y: c.y + 5 + dy * 2))
            whisker.move(to: CGPoint(x: c.x - 4, y: c.y + 6))
            whisker.addLine(to: CGPoint(x: c.x - 15, y: c.y + 5 + dy * 2))
            context.stroke(whisker, with: .color(.white.opacity(0.7)), lineWidth: 0.6)
        }
    }

    private func stripes(_ context: inout GraphicsContext, _ stripe: GraphicsContext.Shading, x: Double, y: Double,
                         count: Int, height: Double) {
        for i in 0..<count {
            var mark = Path()
            let sx = x + Double(i) * 9
            mark.move(to: CGPoint(x: sx, y: y + 1))
            mark.addQuadCurve(to: CGPoint(x: sx + 2, y: y + height), control: CGPoint(x: sx + 4, y: y + height * 0.4))
            context.stroke(mark, with: stripe, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        }
    }

    private func bowl(_ context: inout GraphicsContext) {
        var bowl = Path()
        bowl.move(to: CGPoint(x: 72, y: 60))
        bowl.addLine(to: CGPoint(x: 98, y: 60))
        bowl.addQuadCurve(to: CGPoint(x: 74, y: 60), control: CGPoint(x: 86, y: 76))
        context.fill(bowl, with: .color(Color(red: 0.3, green: 0.55, blue: 0.95)))
        context.fill(Path(ellipseIn: CGRect(x: 76, y: 57, width: 18, height: 5)), with: .color(Color(red: 0.75, green: 0.5, blue: 0.3)))
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

/// Moves the cat along the top of the Dock: it wanders, sits, naps, and comes to eat.
final class DesktopCat {
    private let brain: CatBrain
    private let settings: AppSettings
    private var window: NSPanel?
    private var timer: Timer?
    private var bag = Set<AnyCancellable>()
    private let state = DesktopCatState()

    private var x: CGFloat = 200
    private var targetX: CGFloat?
    private var poseUntil = Date()
    private var lastTick = Date()

    static let base = CGSize(width: 180, height: 150)

    init(brain: CatBrain, settings: AppSettings) {
        self.brain = brain
        self.settings = settings
        settings.$catEnabled.removeDuplicates()
            .sink { [weak self] on in DispatchQueue.main.async { on ? self?.start() : self?.stop() } }
            .store(in: &bag)
        settings.$catSize.dropFirst().removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.resize() } }
            .store(in: &bag)
    }

    private var scale: CGFloat { CGFloat(settings.catSize) }
    private var size: CGSize { CGSize(width: Self.base.width * scale, height: Self.base.height * scale) }

    private func start() {
        guard window == nil else { return }
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        let hosting = FirstMouseHostingView(rootView: DesktopCatView(brain: brain, settings: settings, state: state))
        hosting.sizingOptions = []
        panel.contentView = hosting
        window = panel
        if let screen = NSScreen.main { x = screen.visibleFrame.midX + 260 }
        place()
        panel.orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window = nil
    }

    private func resize() {
        guard let window else { return }
        window.setContentSize(size)
        place()
    }

    /// Feet on the top edge of the Dock (or the bottom of the screen when the Dock hides).
    private func place() {
        guard let window, let screen = NSScreen.main else { return }
        let floor = screen.visibleFrame.minY
        window.setFrameOrigin(CGPoint(x: x - size.width / 2, y: floor - 4 * scale))
    }

    private func tick() {
        guard let window, let screen = NSScreen.main else { return }
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now

        // Let the mouse through except over the cat itself, or the card while it's open.
        let mouse = NSEvent.mouseLocation
        let frame = window.frame
        let catRect = CGRect(x: frame.minX + 30 * scale, y: frame.minY, width: frame.width - 60 * scale, height: 80 * scale)
        let over = catRect.contains(mouse) || (state.showCard && frame.contains(mouse))
        if window.ignoresMouseEvents == over { window.ignoresMouseEvents = !over }
        if over != state.hovering { state.hovering = over }
        if state.hovering || brain.pose == .eat { return }

        let speed: CGFloat = (brain.isHungry ? 24 : 42) * scale
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

    private func decide(screen: NSScreen) {
        let hour = Calendar.current.component(.hour, from: Date())
        let night = hour >= 23 || hour < 7
        let roll = Double.random(in: 0..<1)
        let range = (screen.visibleFrame.minX + size.width / 2)...(screen.visibleFrame.maxX - size.width / 2)
        if brain.pose == .walk || roll < (night ? 0.55 : 0.25) {
            // Rest: a nap, or a sit.
            let nap = roll < (night ? 0.45 : 0.12) || brain.happiness < 0.2
            brain.pose = nap ? .sleep : .sit
            poseUntil = Date().addingTimeInterval(nap ? .random(in: 40...120) : .random(in: 4...12))
        } else {
            brain.pose = .walk
            targetX = CGFloat.random(in: range)
        }
    }
}

/// What the cat window's view needs from the controller.
final class DesktopCatState: ObservableObject {
    @Published var hovering = false
    @Published var facingRight = true
    @Published var showCard = false
}

private struct DesktopCatView: View {
    @ObservedObject var brain: CatBrain
    @ObservedObject var settings: AppSettings
    @ObservedObject var state: DesktopCatState

    var body: some View {
        let scale = CGFloat(settings.catSize)
        VStack(spacing: 4 * scale) {
            Spacer(minLength: 0)
            if state.hovering {
                CatCard(brain: brain, name: settings.catName, compact: true)
                    .scaleEffect(scale)
                    .frame(height: 56 * scale)
                    .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .bottom)))
                    .onAppear { state.showCard = true }
                    .onDisappear { state.showCard = false }
            } else if brain.isHungry, brain.pose != .eat {
                // A thought bubble with a fish in it.
                Image(systemName: "fish.fill")
                    .font(.system(size: 12 * scale))
                    .foregroundStyle(Color(red: 0.4, green: 0.7, blue: 1))
                    .padding(6 * scale)
                    .background(Circle().fill(.white.opacity(0.9)))
                    .offset(x: 26 * scale)
            }
            ZStack(alignment: .top) {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate * (brain.pose == .walk ? 7 : 2)
                    CatFigure(pose: brain.pose, mood: brain.mood, color: settings.catColor, time: t)
                        .scaleEffect(x: state.facingRight ? 1 : -1, y: 1)
                }
                .frame(width: 100 * scale, height: 72 * scale)
                CatHearts(since: brain.heartsAt).offset(y: 6 * scale)
            }
            .contentShape(Rectangle())
            .onTapGesture { brain.pet() }
            .help("Click to pet \(settings.catName)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: state.hovering)
        .environment(\.colorScheme, .dark)
    }
}

/// Name, mood, fullness and happiness, with Feed and Pet. Used over the desktop cat and in the
/// Widgets tab.
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
            VStack(spacing: 4) {
                Button { brain.feed() } label: {
                    Label("Feed", systemImage: "fish.fill").font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(CatButtonStyle(fill: Color(red: 0.35, green: 0.62, blue: 1)))
                Button { brain.pet() } label: {
                    Label("Pet", systemImage: "hand.raised.fill").font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(CatButtonStyle(fill: Color.white.opacity(0.16)))
            }
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
