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

/// Something about the dog worth telling you once, in the notch.
struct CatAlert {
    var symbol: String
    var title: String
    var detail: String
    var tint: Color
}

/// The dog's body and needs. Time only passes for it while the Mac is awake: system sleep, a
/// sleeping display and a shut-down Mac all stop its clock, so it never comes back from a closed
/// lid starving. It sleeps through the night (bedtime to wake-up, set in Settings), and while it
/// sleeps it gets hungry slowly and doesn't miss you.
///
/// Care has consequences. Fullness and affection each drain over about ten waking hours.
/// Feeding a dog that isn't hungry gives it no love, puts weight on it, and twice in a row makes
/// it throw up; kept full all day it gets fat, then slow, then ill. Left alone it gets lonely and
/// ill too. A sick dog lies down and won't play until good care (or the vet) brings it round.
final class CatBrain: ObservableObject {
    enum Mood {
        case happy, content, hungry, starving, stuffed, lonely, sick

        var title: String {
            switch self {
            case .happy: "Happy"
            case .content: "Content"
            case .hungry: "Hungry"
            case .starving: "Starving"
            case .stuffed: "Too full"
            case .lonely: "Lonely"
            case .sick: "Sick"
            }
        }

        /// Ears down, tail still.
        var isLow: Bool { self == .starving || self == .lonely || self == .sick }
        var isGood: Bool { self == .happy || self == .content }
    }

    enum Pose: Equatable {
        case walk, sit, sleep, eat
        /// Lying down awake, head up.
        case lie
        /// Front down, rear up: the morning stretch.
        case stretch
        /// Walking slowly with the nose to the ground.
        case sniff
        /// Sitting, a hind leg going at an itch.
        case scratch
        case bark
        /// Lying flat, a thermometer in its mouth.
        case sick
        case vomit

        /// Moving along the floor.
        var travels: Bool { self == .walk || self == .sniff }
    }

    @Published fileprivate(set) var fullness: Double
    @Published fileprivate(set) var affection: Double
    /// Body condition: 0 skin and bone, 0.5 just right, 1 obese.
    @Published fileprivate(set) var weight: Double
    @Published fileprivate(set) var health: Double
    /// Food it ate past full and hasn't digested yet. Past 0.5 it comes back up.
    @Published fileprivate(set) var stomach: Double
    /// While it's at the vet.
    @Published private(set) var awayUntil: Date?
    /// What the vet said last time, until the next visit.
    @Published private(set) var vetNote: String?
    @Published var pose: Pose = .sit
    /// When the last hearts started (petting or feeding), for the floating-hearts animation.
    @Published private(set) var heartsAt: Date?

    /// Something worth a card in the notch (hungry, threw up, lonely, sick, back from the vet).
    /// Alerts raised before it's set (while the app launches) wait and are told when it is.
    var onAlert: ((CatAlert) -> Void)? {
        didSet {
            guard let onAlert, !pendingAlerts.isEmpty else { return }
            let waiting = pendingAlerts
            pendingAlerts = []
            waiting.forEach(onAlert)
        }
    }
    private var pendingAlerts: [CatAlert] = []
    /// The dog was woken or interrupted and should stay as it is for this long before deciding
    /// what to do next (DesktopCat moves it).
    var onInterrupt: ((TimeInterval) -> Void)?

    private let defaults: UserDefaults
    private let settings: AppSettings
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    /// Awake-time (seconds of `CLOCK_UPTIME_RAW`) at the last update.
    private var lastUptime: Double
    /// The Mac, or just its display, is asleep. A background wake (Power Nap, a download) wakes
    /// the system but not the display, and the dog stays paused through it.
    private var systemAsleep = false
    private var displayAsleep = false
    private var paused: Bool { systemAsleep || displayAsleep }
    private var announced = Set<String>()
    fileprivate var lastPets: [Date] = []

    static let fullnessPerHour = 0.1
    static let affectionPerHour = 0.1
    static let mealSize = 0.45
    static let vetVisit: TimeInterval = 20 * 60

    init(settings: AppSettings, live: Bool = true) {
        self.settings = settings
        let store = live ? UserDefaults.standard : UserDefaults(suiteName: "com.premprateek.notchdeck.previews") ?? .standard
        defaults = store
        // Everything is saved as one record, so a save cut short can't leave half of it behind.
        // (Older versions kept a key each; read those once.)
        let saved = live ? store.dictionary(forKey: "cat.state") : nil
        func stored(_ key: String, _ fallback: Double, preview: Double) -> Double {
            guard live else { return preview }
            return saved?[key] as? Double ?? store.object(forKey: "cat." + key) as? Double ?? fallback
        }
        fullness = stored("fullness", 0.8, preview: 0.62)
        affection = stored("affection", 0.6, preview: 0.8)
        weight = stored("weight", 0.5, preview: 0.5)
        health = stored("health", 1, preview: 1)
        stomach = stored("stomach", 0, preview: 0)
        awayUntil = live ? (saved.map { $0["awayUntil"] as? Date } ?? store.object(forKey: "cat.awayUntil") as? Date) : nil
        vetNote = live ? (saved.map { $0["vetNote"] as? String } ?? store.string(forKey: "cat.vetNote")) : nil
        // Time only passes for the dog while NotchDeck runs and the Mac is awake: whatever
        // happened while the app was closed (asleep, display off, shut down, or awake) doesn't
        // count, so there is never a catch-up to get wrong.
        lastUptime = Self.uptime()
        guard live else { return }
        announced = Set(defaults.stringArray(forKey: "cat.announced") ?? [])
        decay()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.decay() }
        let center = NSWorkspace.shared.notificationCenter
        func observe(_ name: Notification.Name, _ change: @escaping (CatBrain) -> Void) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                // Count up to now, change state, and start counting again from now.
                self.decay()
                change(self)
                self.lastUptime = Self.uptime()
                self.save()
            })
        }
        observe(NSWorkspace.willSleepNotification) { $0.systemAsleep = true }
        observe(NSWorkspace.didWakeNotification) { $0.systemAsleep = false }
        observe(NSWorkspace.screensDidSleepNotification) { $0.displayAsleep = true }
        observe(NSWorkspace.screensDidWakeNotification) { $0.displayAsleep = false }
    }

    // MARK: Reading the dog

    var happiness: Double { 0.65 * fullness + 0.35 * affection }

    var mood: Mood {
        if isSick { return .sick }
        if fullness < 0.1 { return .starving }
        if stomach > 0.05 { return .stuffed }
        if fullness < 0.3 { return .hungry }
        if affection < 0.15 { return .lonely }
        return happiness > 0.6 && affection > 0.45 ? .happy : .content
    }

    var isHungry: Bool { fullness < 0.3 }
    var isSick: Bool { health < 0.35 }
    var isAway: Bool { awayUntil.map { $0 > Date() } ?? false }
    var isOverweight: Bool { weight > 0.68 }
    var isObese: Bool { weight > 0.84 }
    var isNight: Bool { Self.isNight(Date(), bedtime: settings.catBedtime, wake: settings.catWakeTime) }

    /// Fit enough to chase the pointer.
    var canPlay: Bool { mood == .happy && !isOverweight && health > 0.6 }

    /// How fast it walks, against a fit and fed dog.
    var pace: Double {
        if isSick { return 0.35 }
        var pace = 1.0
        if isObese { pace *= 0.45 } else if isOverweight { pace *= 0.7 }
        if isHungry || mood == .lonely { pace *= 0.65 }
        return pace
    }

    /// How round it's drawn: 1 at a healthy weight, up to about 1.5 when obese, thinner when starved.
    var girth: Double {
        if weight > 0.58 { return 1 + (weight - 0.58) * 1.2 }
        if weight < 0.3 { return 1 - (0.3 - weight) * 0.6 }
        return 1
    }

    var hungerText: String {
        if stomach > 0.05 { return "Stuffed" }
        switch fullness {
        case 0.85...: return "Full"
        case 0.55...: return "Satisfied"
        case 0.3...: return "Peckish"
        case 0.1...: return "Hungry"
        default: return "Starving"
        }
    }

    var weightText: String {
        switch weight {
        case ..<0.22: "Underweight"
        case ..<0.68: "Healthy weight"
        case ..<0.84: "Overweight"
        default: "Obese"
        }
    }

    var healthText: String {
        switch health {
        case 0.8...: "Healthy"
        case 0.55...: "A bit off"
        case 0.35...: "Unwell"
        default: "Sick"
        }
    }

    static func isNight(_ date: Date, bedtime: Int, wake: Int) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        if bedtime == wake { return false }
        return bedtime > wake ? (hour >= bedtime || hour < wake) : (hour >= bedtime && hour < wake)
    }

    // MARK: Caring for it

    func feed() {
        guard !isAway else { return }
        decay()
        let before = fullness
        let overflow = max(0, before + Self.mealSize - 1)
        fullness = min(1, before + Self.mealSize)
        if overflow > 0 {
            // Food past full: no thanks for it, weight on the hips, and a stomach that complains.
            stomach += overflow
            weight = min(1, weight + overflow * 0.12)
        } else {
            affection = min(1, affection + 0.1)
            heartsAt = Date()
        }
        if stomach > 0.5 {
            throwUp()
        } else {
            pose = .eat
            save()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
                guard let self, self.pose == .eat else { return }
                self.pose = self.stomach > 0.05 ? .lie : .sit
                self.onInterrupt?(self.isNight ? 6 : .random(in: 4...8))
            }
        }
        if !isHungry { announced.remove("hungry") }
        if overflow > 0, !isOverweight {
            alertOnce("stuffed", CatAlert(symbol: "exclamationmark.triangle.fill", title: "\(settings.catName) wasn't hungry",
                                          detail: "Food past full puts weight on, and too much makes it sick", tint: .orange))
        }
    }

    func pet() {
        guard !isAway else { return }
        decay()
        // Each pet in quick succession counts for less: a scratch is lovely, the fortieth isn't.
        let now = Date()
        lastPets = lastPets.filter { now.timeIntervalSince($0) < 90 } + [now]
        affection = min(1, affection + 0.25 / Double(lastPets.count))
        heartsAt = now
        if affection >= 0.15 { announced.remove("lonely") }
        if pose == .sleep {
            // Woken: it sits up, groggy, and at night settles straight back down.
            pose = .sit
            onInterrupt?(isNight ? 10 : 5)
        }
        save()
    }

    /// The vet keeps it for twenty minutes and sends it home better, with advice.
    func takeToVet() {
        guard !isAway else { return }
        decay()
        awayUntil = Date().addingTimeInterval(Self.vetVisit)
        save()
    }

    /// A spell of chasing the pointer: it loved it, and it works off extra weight (only extra:
    /// a playful dog that's fed properly stays at its healthy weight, it doesn't waste away).
    func exercised() {
        if weight > 0.5 { weight = max(0.5, weight - 0.008) }
        affection = min(1, affection + 0.05)
        save()
    }

    private func throwUp() {
        stomach = 0
        fullness = 0.55
        health = max(0, health - 0.08)
        affection = max(0, affection - 0.05)
        pose = .vomit
        save()
        alertOnce("vomit", CatAlert(symbol: "exclamationmark.triangle.fill", title: "\(settings.catName) threw up",
                                    detail: "It was fed too much. Wait until it's hungry", tint: .red))
        announced.remove("vomit")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.pose == .vomit else { return }
            self.pose = .lie
            self.onInterrupt?(30)
        }
    }

    private func comeHome() {
        awayUntil = nil
        health = max(health, 0.8)
        stomach = 0
        affection = min(1, affection + 0.15)
        var advice: [String] = []
        if isOverweight { advice.append("feed it only when it's hungry") }
        if affection < 0.4 { advice.append("give it more attention") }
        if fullness < 0.3 { advice.append("don't let it go hungry") }
        vetNote = advice.isEmpty ? nil : "The vet says: " + advice.joined(separator: ", ") + "."
        announced.subtract(["sick"])
        emit(CatAlert(symbol: "cross.case.fill", title: "\(settings.catName) is back from the vet",
                      detail: vetNote ?? "All better", tint: .green))
        save()
    }

    // MARK: Time

    private func decay() {
        let now = Self.uptime()
        // Seconds the Mac was awake since the last update (the clock stops in system sleep).
        let hours = paused ? 0 : max(0, now - lastUptime) / 3600
        lastUptime = now
        if let back = awayUntil, back <= Date() { comeHome() }
        if hours > 0, !isAway {
            // In steps of at most a quarter hour, each at its own time of day, so getting hungry
            // or nightfall partway through changes only what comes after it.
            var remaining = hours
            while remaining > 1e-9 {
                let step = min(remaining, 0.25)
                remaining -= step
                live(hours: step, at: Date().addingTimeInterval(-remaining * 3600))
            }
        }
        save()
        announce()
    }

    fileprivate func live(hours h: Double, at date: Date = Date()) {
        let asleep = Self.isNight(date, bedtime: settings.catBedtime, wake: settings.catWakeTime) || pose == .sleep
        fullness = max(0, fullness - h * Self.fullnessPerHour * (asleep ? 0.4 : 1))
        affection = max(0, affection - h * Self.affectionPerHour * (asleep ? 0.1 : 1))
        // Digesting what it overate.
        stomach = max(0, stomach - h * 0.5)

        // Weight follows the bowl: kept full it fattens, kept hungry it thins, and otherwise it
        // drifts slowly back to normal. Losing weight is slower than gaining it.
        if fullness > 0.88 {
            weight = min(1, weight + h * 0.012)
        } else if fullness < 0.15 {
            weight = max(0, weight - h * 0.01)
        } else {
            // Back towards normal: about half the way in a waking day.
            weight += (0.5 - weight) * min(1, h * 0.045)
        }

        var harm = 0.0
        if isObese { harm += 0.012 } else if isOverweight { harm += 0.004 }
        if weight < 0.22 { harm += 0.01 }
        if fullness <= 0 { harm += 0.04 } else if fullness < 0.1 { harm += 0.012 }
        if affection < 0.1 { harm += 0.012 }
        if harm > 0 {
            health = max(0, health - h * harm)
        } else {
            health = min(1, health + h * (asleep ? 0.03 : 0.02))
        }
    }

    /// Each bad turn is told once, until it's over.
    private func announce() {
        let name = settings.catName
        if isHungry {
            alertOnce("hungry", CatAlert(symbol: "dog.fill", title: "\(name) is hungry",
                                         detail: settings.catFeeding == .hover
                                             ? "Rest the pointer on \(name) and press Feed"
                                             : "Open the notch → Widgets and press Feed", tint: .orange))
        } else {
            announced.remove("hungry")
        }
        if stomach <= 0.05 { announced.remove("stuffed") }
        // Each warning re-arms once the dog is clearly over it (a little past the line, so it
        // doesn't repeat while hovering at the edge).
        if affection < 0.15 {
            alertOnce("lonely", CatAlert(symbol: "heart.slash.fill", title: "\(name) misses you",
                                         detail: "Click it to pet it; a lonely dog gets ill", tint: .pink))
        } else if affection >= 0.25 {
            announced.remove("lonely")
        }
        if isOverweight {
            alertOnce("heavy", CatAlert(symbol: "scalemass.fill", title: "\(name) is getting heavy",
                                        detail: "Feed it only when it's hungry and let it play", tint: .orange))
        } else if weight < 0.62 {
            announced.remove("heavy")
        }
        if isSick {
            alertOnce("sick", CatAlert(symbol: "cross.case.fill", title: "\(name) is sick",
                                       detail: "Take it to the vet from its card", tint: .red))
        } else if health > 0.5 {
            announced.remove("sick")
        }
        defaults.set(Array(announced), forKey: "cat.announced")
    }

    private func alertOnce(_ key: String, _ alert: CatAlert) {
        guard !announced.contains(key) else { return }
        announced.insert(key)
        defaults.set(Array(announced), forKey: "cat.announced")
        emit(alert)
    }

    private func emit(_ alert: CatAlert) {
        if let onAlert { onAlert(alert) } else { pendingAlerts.append(alert) }
    }

    private func save() {
        var state: [String: Any] = ["fullness": fullness, "affection": affection, "weight": weight,
                                    "health": health, "stomach": stomach]
        if let awayUntil { state["awayUntil"] = awayUntil }
        if let vetNote { state["vetNote"] = vetNote }
        defaults.set(state, forKey: "cat.state")
    }

    /// The next wake-up time after `date`, when the dog gets up.
    func nextWake(after date: Date = Date()) -> Date {
        Calendar.current.nextDate(after: date, matching: DateComponents(hour: settings.catWakeTime, minute: 0),
                                  matchingPolicy: .nextTime) ?? date.addingTimeInterval(600)
    }

    /// `--test-dog`: lives through some days of care and neglect and prints how the dog ends up.
    static func selfTest() {
        func run(_ name: String, days: Int, expect: (CatBrain) -> Bool, care: (CatBrain, Int) -> Void) {
            let settings = AppSettings(defaults: UserDefaults(suiteName: "notchdeck.test-dog") ?? .standard)
            // Bedtime equal to wake-up: never night, so the run doesn't depend on the clock.
            settings.catBedtime = 0
            settings.catWakeTime = 0
            let brain = CatBrain(settings: settings, live: false)
            brain.fullness = 0.8; brain.affection = 0.6; brain.weight = 0.5; brain.health = 1; brain.stomach = 0
            for hour in 0..<(days * 16) {
                brain.lastPets = []
                care(brain, hour % 16)
                brain.live(hours: 1)
            }
            let verdict = String(format: "food %.2f love %.2f weight %.2f (%@) health %.2f (%@) mood %@",
                                 brain.fullness, brain.affection, brain.weight, brain.weightText, brain.health,
                                 brain.healthText, brain.mood.title)
            print("\(SelfTest.mark(expect(brain))) \(name) after \(days) days: \(verdict)")
        }
        // A waking day is 16 hours here.
        run("fed when hungry, petted every 2 h", days: 14, expect: { !$0.isSick && !$0.isOverweight && $0.mood.isGood }) { b, h in
            if b.isHungry { b.feed() }
            if h % 2 == 0 { b.pet() }
        }
        run("fed when hungry, petted, plays three times an hour", days: 14,
            expect: { abs($0.weight - 0.5) < 0.08 && !$0.isSick && $0.mood.isGood }) { b, h in
            if b.isHungry { b.feed() }
            if h % 2 == 0 { b.pet() }
            b.exercised(); b.exercised(); b.exercised()
        }
        run("overweight, then fed properly and played with", days: 10,
            expect: { (0.35...0.65).contains($0.weight) && !$0.isSick }) { b, h in
            if h == 0, b.weight == 0.5 { b.weight = 0.8 }
            if b.isHungry { b.feed() }
            if h % 2 == 0 { b.pet() }
            b.exercised(); b.exercised()
        }
        run("fed every hour", days: 7, expect: { $0.isOverweight || $0.isSick }) { b, h in
            b.feed()
            if h % 3 == 0 { b.pet() }
        }
        run("never petted", days: 4, expect: { $0.mood == .lonely || $0.isSick }) { b, _ in
            if b.isHungry { b.feed() }
        }
        run("never fed", days: 3, expect: { $0.isSick }) { b, h in
            if h % 3 == 0 { b.pet() }
        }
        let b = CatBrain(settings: AppSettings(defaults: UserDefaults(suiteName: "notchdeck.test-dog") ?? .standard), live: false)
        b.fullness = 0.9; b.stomach = 0
        b.feed(); b.feed()
        print("\(SelfTest.mark(b.stomach == 0 && b.health < 1)) two meals on a full stomach: threw up (health \(String(format: "%.2f", b.health)))")
        let night = Calendar.current.date(bySettingHour: 2, minute: 0, second: 0, of: Date())!
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        print("\(SelfTest.mark(isNight(night, bedtime: 23, wake: 7) && !isNight(noon, bedtime: 23, wake: 7))) 02:00 is night, 12:00 isn't")
    }

    /// Seconds the Mac has been awake since boot (stops while it sleeps).
    static func uptime() -> Double { Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9 }
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
    /// How round the body is: 1 normal, about 1.5 obese, under 1 when starved.
    var girth: Double = 1

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
        let droop = mood.isLow ? 1.0 : (mood == .hungry || mood == .stuffed ? 0.5 : 0)
        let happy = mood == .happy
        let t = time
        // A happy dog's tail goes faster; a sad or sick one barely moves it.
        let wag = sin(t * (happy ? 2.6 : 1.2)) * (happy ? 1 : (mood.isLow ? 0.12 : 0.5))
        // Extra belly, in drawing points.
        let belly = (girth - 1) * 16

        context.fill(Path(ellipseIn: CGRect(x: 16 - belly / 2, y: 66, width: 70 + belly, height: 6)),
                     with: .color(.black.opacity(0.18)))

        switch pose {
        case .sleep:
            // Curled up, tail round the front, chin on the paws.
            var tail = Path()
            tail.move(to: CGPoint(x: 22, y: 60))
            tail.addQuadCurve(to: CGPoint(x: 58, y: 68), control: CGPoint(x: 24, y: 72))
            context.stroke(tail, with: fur, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            let breathe = 1 + 0.03 * sin(t * 1.2)
            let h = (28 + belly * 0.6) * breathe
            let body = Path(ellipseIn: CGRect(x: 14 - belly / 2, y: 66 - h, width: 62 + belly, height: h))
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

        case .lie, .sick, .vomit:
            // Lying down, front paws out. Awake it holds its head up; ill, the head sinks.
            let ill = pose != .lie
            tail(&context, from: CGPoint(x: 18, y: 58), to: CGPoint(x: 4 + wag * 4, y: 62 - abs(wag) * 5),
                 control: CGPoint(x: 8, y: 54), fur: fur, ear: ear)
            let h = 22 + belly * 0.7
            let body = Path(ellipseIn: CGRect(x: 14 - belly / 2, y: 67 - h, width: 60 + belly, height: h))
            context.fill(body, with: fur)
            context.stroke(body, with: outline, lineWidth: 0.8)
            let paws = Path(roundedRect: CGRect(x: 56, y: 61, width: 28, height: 7), cornerRadius: 3.5)
            context.fill(paws, with: fur)
            context.stroke(paws, with: outline, lineWidth: 0.6)
            if pose == .vomit {
                context.fill(Path(ellipseIn: CGRect(x: 83, y: 63.5, width: 17, height: 5)),
                             with: .color(Color(red: 0.78, green: 0.75, blue: 0.35).opacity(0.9)))
            }
            let center = pose == .vomit ? CGPoint(x: 80, y: 52 + sin(t * 4) * 1.2)
                : (ill ? CGPoint(x: 74, y: 50) : CGPoint(x: 72, y: 38))
            head(&context, center: center, fur: fur, ear: ear, muzzle: muzzle, outline: outline,
                 eyes: ill ? .closed : (blinking(t) ? .closed : .open), droop: ill ? 1 : droop,
                 tongue: !ill && happy, tilt: pose == .vomit ? 24 : (ill ? 10 : 0))
            if pose == .sick { thermometer(&context, at: CGPoint(x: 98, y: 64)) }

        case .sit, .scratch, .bark:
            let scratching = pose == .scratch
            tail(&context, from: CGPoint(x: 30, y: 54), to: CGPoint(x: 14 + wag * 6, y: 34 - abs(wag) * 3 + droop * 18),
                 control: CGPoint(x: 14, y: 54), fur: fur, ear: ear)
            let haunch = Path(ellipseIn: CGRect(x: 24 - belly / 2, y: 38 - belly / 3, width: 38 + belly, height: 30 + belly / 3))
            context.fill(haunch, with: fur)
            context.stroke(haunch, with: outline, lineWidth: 0.8)
            if scratching {
                // The hind leg kicks up at the neck, fast.
                var leg = context
                leg.translateBy(x: 36, y: 58)
                leg.rotate(by: .radians(-2.45 + sin(t * 14) * 0.22))
                let shape = Path(roundedRect: CGRect(x: -4, y: 0, width: 8, height: 26), cornerRadius: 4)
                leg.fill(shape, with: .color(color.fur.opacity(0.85)))
                leg.stroke(shape, with: outline, lineWidth: 0.6)
            } else {
                let paw = Path(ellipseIn: CGRect(x: 22, y: 61, width: 18, height: 7))
                context.fill(paw, with: fur)
                context.stroke(paw, with: outline, lineWidth: 0.6)
            }
            let chest = Path(ellipseIn: CGRect(x: 44 - belly / 3, y: 24, width: 28 + belly * 0.6, height: 42))
            context.fill(chest, with: fur)
            context.fill(Path(ellipseIn: CGRect(x: 55, y: 32, width: 14, height: 24)), with: muzzle)
            for x in [52.0, 61.0] {
                let leg = Path(roundedRect: CGRect(x: x, y: 46, width: 8, height: 22), cornerRadius: 4)
                context.fill(leg, with: fur)
                context.stroke(leg, with: outline, lineWidth: 0.6)
            }
            let barking = pose == .bark
            let woof = barking ? max(0, sin(t * 3)) : 0
            head(&context, center: CGPoint(x: 62, y: 20 - woof * 2), fur: fur, ear: ear, muzzle: muzzle, outline: outline,
                 eyes: scratching ? .closed : (happy || barking ? .happy : (blinking(t) ? .closed : .open)),
                 droop: droop, tongue: happy && !barking && !scratching, tilt: scratching ? 12 : -woof * 8,
                 open: woof)
            if barking, woof > 0.3 {
                let text = Text("woof!").font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(min(1, woof * 1.4)))
                context.draw(text, at: CGPoint(x: 88, y: 6 - woof * 3))
            }

        case .stretch:
            // The play bow: elbows on the floor, rear in the air, tail up.
            let ease = 0.5 + 0.5 * sin(t * 0.8)
            tail(&context, from: CGPoint(x: 22, y: 28), to: CGPoint(x: 10 + wag * 5, y: 8),
                 control: CGPoint(x: 10, y: 26), fur: fur, ear: ear)
            for x in [22.0, 30.0] {
                let leg = Path(roundedRect: CGRect(x: x, y: 36, width: 8, height: 32), cornerRadius: 4)
                context.fill(leg, with: fur)
                context.stroke(leg, with: outline, lineWidth: 0.6)
            }
            var torso = context
            torso.translateBy(x: 48, y: 40)
            torso.rotate(by: .degrees(14 + ease * 4))
            let body = Path(roundedRect: CGRect(x: -32, y: -12 - belly / 3, width: 62, height: 24 + belly * 0.7), cornerRadius: 12)
            torso.fill(body, with: fur)
            torso.stroke(body, with: outline, lineWidth: 0.8)
            let paws = Path(roundedRect: CGRect(x: 62, y: 61, width: 30, height: 7), cornerRadius: 3.5)
            context.fill(paws, with: fur)
            context.stroke(paws, with: outline, lineWidth: 0.6)
            head(&context, center: CGPoint(x: 82, y: 50), fur: fur, ear: ear, muzzle: muzzle, outline: outline,
                 eyes: .closed, droop: 0, tongue: false, tilt: -6, open: ease * 0.8)

        case .walk, .eat, .sniff:
            let walking = pose.travels
            let sniffing = pose == .sniff
            let bob = walking ? abs(sin(t)) * (sniffing ? 0.6 : 1.5) : 0
            tail(&context, from: CGPoint(x: 20, y: 36 - bob), to: CGPoint(x: 6 + wag * 5, y: 18 + droop * 20),
                 control: CGPoint(x: 6, y: 34), fur: fur, ear: ear)
            let swing = walking ? sin(t) * (sniffing ? 0.25 : 0.45) : 0
            let legs: [(Double, Double)] = [(26, swing), (34, -swing), (60, -swing), (68, swing)]
            for (x, angle) in legs {
                var leg = context
                leg.translateBy(x: x + 4, y: 48 - bob)
                leg.rotate(by: .radians(angle))
                let shape = Path(roundedRect: CGRect(x: -4, y: 0, width: 8, height: 20), cornerRadius: 4)
                leg.fill(shape, with: x == 34 || x == 68 ? .color(color.fur.opacity(0.8)) : fur)
                leg.stroke(shape, with: outline, lineWidth: 0.6)
            }
            let body = Path(roundedRect: CGRect(x: 16 - belly * 0.3, y: 30 - bob - belly * 0.3,
                                                width: 62 + belly * 0.6, height: 24 + belly), cornerRadius: 12 + belly / 2)
            context.fill(body, with: fur)
            context.stroke(body, with: outline, lineWidth: 0.8)
            context.fill(Path(ellipseIn: CGRect(x: 56, y: 40 - bob, width: 20, height: 13)), with: muzzle)
            if pose == .eat {
                let chomp = sin(t * 3) * 1.5
                head(&context, center: CGPoint(x: 78, y: 48 + chomp), fur: fur, ear: ear, muzzle: muzzle, outline: outline,
                     eyes: .happy, droop: 0, tongue: false, tilt: 14)
                bowl(&context)
            } else if sniffing {
                // Nose to the ground, twitching.
                head(&context, center: CGPoint(x: 82, y: 44 - bob + sin(t * 6) * 0.8), fur: fur, ear: ear, muzzle: muzzle,
                     outline: outline, eyes: .open, droop: droop, tongue: false, tilt: 26)
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
    /// when it's happy. `tilt` turns the head down (degrees), for sleeping and eating; `open`
    /// (0–1) drops the jaw, for barking and yawning.
    private func head(_ context: inout GraphicsContext, center c: CGPoint, fur: GraphicsContext.Shading,
                      ear: GraphicsContext.Shading, muzzle: GraphicsContext.Shading, outline: GraphicsContext.Shading,
                      eyes: Eyes, droop: Double, tongue: Bool, tilt: Double, open: Double = 0) {
        var g = context
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .degrees(tilt))
        let skull = Path(ellipseIn: CGRect(x: -12, y: -12, width: 25, height: 23))
        g.fill(skull, with: fur)
        g.stroke(skull, with: outline, lineWidth: 0.8)
        if open > 0.05 {
            // The open mouth behind the snout, and the lower jaw below it.
            g.fill(Path(roundedRect: CGRect(x: 8, y: 5, width: 13, height: 4 + open * 6), cornerRadius: 3),
                   with: .color(Color(red: 0.45, green: 0.12, blue: 0.16)))
            let jaw = Path(roundedRect: CGRect(x: 6, y: 7 + open * 6, width: 14, height: 4), cornerRadius: 2)
            g.fill(jaw, with: muzzle)
            g.stroke(jaw, with: outline, lineWidth: 0.5)
        }
        let snout = Path(roundedRect: CGRect(x: 4, y: -1, width: 18, height: open > 0.05 ? 8 : 12), cornerRadius: 6)
        g.fill(snout, with: muzzle)
        g.stroke(snout, with: outline, lineWidth: 0.6)
        g.fill(Path(ellipseIn: CGRect(x: 17.5, y: -2.5, width: 6.5, height: 5.5)), with: .color(Color(white: 0.08)))
        g.fill(Path(ellipseIn: CGRect(x: 19, y: -1.8, width: 2, height: 1.4)), with: .color(.white.opacity(0.6)))
        if open <= 0.05 {
            var mouth = Path()
            mouth.move(to: CGPoint(x: 11, y: 8.5))
            mouth.addQuadCurve(to: CGPoint(x: 20, y: 7.5), control: CGPoint(x: 16, y: 11))
            g.stroke(mouth, with: .color(.black.opacity(0.55)), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
        }
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

    /// A thermometer sticking out of the mouth, bulb outward.
    private func thermometer(_ context: inout GraphicsContext, at p: CGPoint) {
        var stick = Path()
        stick.move(to: CGPoint(x: p.x - 10, y: p.y - 5))
        stick.addLine(to: p)
        context.stroke(stick, with: .color(.white.opacity(0.95)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        context.fill(Path(ellipseIn: CGRect(x: p.x - 1.8, y: p.y - 1.8, width: 3.6, height: 3.6)),
                     with: .color(Color(red: 0.95, green: 0.25, blue: 0.25)))
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
    /// Whether the last decision was made at night, to wake up with a stretch.
    private var sleptTonight = false
    private var unlockObserver: NSObjectProtocol?
    private var screenObservers: [NSObjectProtocol] = []

    /// The window around the cat in screen mode, at size 1: room for the card above it.
    static let base = CGSize(width: 180, height: 168)
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
        brain.onInterrupt = { [weak self] seconds in
            guard let self else { return }
            self.targetX = nil
            self.poseUntil = Date().addingTimeInterval(seconds)
        }
        // Coming back to the Mac (in the day): it trots over and says hello.
        // Nobody sees it while the display sleeps: stop ticking until it wakes.
        let workspace = NSWorkspace.shared.notificationCenter
        screenObservers.append(workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil,
                                                     queue: .main) { [weak self] _ in
            self?.timer?.invalidate()
            self?.timer = nil
        })
        screenObservers.append(workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil,
                                                     queue: .main) { [weak self] _ in
            guard let self, self.window != nil else { return }
            self.lastTick = Date()
            self.schedule(fast: true)
        })
        unlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in self?.greet() }
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
            return CGSize(width: 250, height: Self.figure.height * s + 98)
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
        schedule(fast: true)
    }

    /// 30 checks a second while it moves, plays or has the pointer on it; 8 while it just sits
    /// or sleeps, which is plenty to notice a pointer arriving and saves the wake-ups.
    private func schedule(fast: Bool) {
        let interval: TimeInterval = fast ? 1 / 30 : 1 / 8
        if let timer, abs(timer.timeInterval - interval) < 0.001 { return }
        timer?.invalidate()
        let next = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(next, forMode: .common)
        timer = next
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
        // The cat is at the top of the window on the notch (the card below it), at the bottom
        // on the screen.
        let origin = onNotch ? CGPoint(x: x - size.width / 2, y: bottom + Self.figure.height * s - size.height)
                             : CGPoint(x: x - size.width / 2, y: bottom - 4 * s)
        // Moving a window costs the window server a redraw: only when it actually moved.
        let current = window.frame.origin
        guard abs(current.x - origin.x) > 0.25 || abs(current.y - origin.y) > 0.25 else { return }
        window.setFrameOrigin(origin)
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
        defer {
            let near = catRect(screen).insetBy(dx: -60, dy: -60).contains(NSEvent.mouseLocation)
            schedule(fast: brain.pose.travels || playUntil != nil || feet != nil || near || state.hovering
                || state.showCard || [.eat, .vomit].contains(brain.pose))
        }
        // At the vet: off the screen until it's back, then it walks in from the edge.
        if brain.isAway {
            if window.isVisible { window.orderOut(nil); endPlay() }
            return
        } else if !window.isVisible {
            let range = walkRange(screen)
            x = range.upperBound
            feet = nil
            brain.pose = .walk
            targetX = range.upperBound - 160
            window.orderFrontRegardless()
            place()
        }
        let now = Date()
        // (Up to an eighth of a second between ticks while it rests.)
        let dt = min(now.timeIntervalSince(lastTick), 0.15)
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
        if state.hovering || [.eat, .vomit].contains(brain.pose) { return }

        // After playing on the screen it walks back down to the Dock.
        if let current = feet {
            let home = floor(screen)
            let step = 160 * catScale(screen) * CGFloat(dt)
            brain.pose = .walk
            feet = current - home <= step ? nil : current - step
            place()
            return
        }

        let speed: CGFloat = 42 * CGFloat(brain.pace) * (brain.pose == .sniff ? 0.45 : 1)
            * (onNotch ? 0.8 : catScale(screen))
        switch brain.pose {
        case .walk, .sniff:
            guard let target = targetX else { decide(screen: screen); return }
            let step = min(abs(target - x), speed * CGFloat(dt))
            x += target > x ? step : -step
            state.facingRight = target > x
            place()
            if abs(target - x) < 1 { targetX = nil; decide(screen: screen) }
        default:
            // Awake and resting, it turns to look at a pointer that comes near.
            if [.sit, .lie, .bark].contains(brain.pose), abs(mouse.x - x) < 220, abs(mouse.x - x) > 12,
               abs(mouse.y - (feet ?? floor(screen))) < 240 {
                let facing = mouse.x > x
                if state.facingRight != facing { state.facingRight = facing }
            }
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
        let step = min(distance, 170 * max(s, 0.6) * CGFloat(brain.pace) * CGFloat(dt))
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
        brain.exercised()
        hoverSince = nil
        scheduleNextPlay()
        state.playfulSince = nil
        brain.pose = .sit
        poseUntil = Date().addingTimeInterval(.random(in: 3...6))
    }

    /// Back at the Mac after a lock: a healthy dog runs over to the pointer and barks hello.
    private func greet() {
        guard window != nil, !brain.isNight, !brain.isAway, !brain.isSick, brain.mood != .lonely,
              settings.catPlayfulness != .off, playUntil == nil else { return }
        playUntil = Date().addingTimeInterval(6)
        targetX = nil
        state.playfulSince = Date()
        brain.pose = .walk
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.2) { [weak self] in
            guard let self, self.playUntil == nil, self.brain.pose == .sit else { return }
            self.brain.pose = .bark
            self.poseUntil = Date().addingTimeInterval(2.5)
        }
    }

    private func decide(screen: NSScreen) {
        let now = Date()
        func rest(_ pose: CatBrain.Pose, _ seconds: ClosedRange<TimeInterval>) {
            brain.pose = pose
            targetX = nil
            poseUntil = now.addingTimeInterval(.random(in: seconds))
        }
        func walk(_ pose: CatBrain.Pose = .walk) {
            brain.pose = pose
            let range = walkRange(screen)
            // Sniffing is pottering about nearby; walking goes somewhere.
            let reach: CGFloat = pose == .sniff ? 140 : .greatestFiniteMagnitude
            targetX = CGFloat.random(in: max(range.lowerBound, x - reach)...min(range.upperBound, x + reach))
        }

        // Bedtime to wake-up it sleeps, right through. Woken, it settles straight back down.
        if brain.isNight {
            sleptTonight = true
            rest(.sleep, 600...600)
            // Not past wake-up time, so it gets up on the hour, not up to ten minutes late.
            poseUntil = min(poseUntil, brain.nextWake())
            return
        }
        // Morning: a long stretch before anything else.
        if sleptTonight {
            sleptTonight = false
            rest(.stretch, 3...4)
            return
        }
        if brain.isSick {
            rest(.sick, 60...120)
            return
        }
        // In the mood: a happy, fit dog now and then decides the pointer is prey.
        if settings.catPlayfulness != .off, brain.canPlay, now >= nextPlay {
            beginPlay()
            return
        }
        let after = brain.pose
        // After a nap it stretches.
        if after == .sleep { rest(.stretch, 2.5...3.5); return }

        // What it feels like doing, weighted by how it is.
        var options: [(weight: Double, act: () -> Void)] = []
        switch brain.mood {
        case .lonely:
            options = [(4, { rest(.lie, 30...90) }), (3, { rest(.sleep, 120...300) }), (2, { rest(.sit, 10...20) }),
                       (1, { walk(.sniff) })]
        case .stuffed:
            options = [(6, { rest(.lie, 40...90) }), (2, { rest(.sleep, 120...240) }), (1, { rest(.sit, 8...15) })]
        default:
            let heavy = brain.isObese ? 3.0 : (brain.isOverweight ? 1.8 : 1)
            let hungry = brain.isHungry
            options = [
                (after.travels ? 1 : 4 / heavy, { walk() }),
                (after.travels ? 0.5 : 1.6, { walk(.sniff) }),
                (2, { rest(.sit, 4...12) }),
                (1.4 * heavy, { rest(.lie, 15...45) }),
                (0.6, { rest(.scratch, 1.6...2.6) }),
                (0.5 * heavy, { rest(.sleep, 180...480) }),
                (hungry ? 1.5 : (brain.mood == .happy ? 0.35 : 0), { rest(.bark, 1.8...2.8) }),
            ]
        }
        let total = options.reduce(0) { $0 + $1.weight }
        var roll = Double.random(in: 0..<total)
        for option in options {
            roll -= option.weight
            if roll < 0 { option.act(); return }
        }
        rest(.sit, 4...8)
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
                .frame(height: 90 * scale)
                .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: state.cardBelow ? .top : .bottom)))
                .onAppear { state.showCard = true }
                .onDisappear { state.showCard = false }
        } else if let thought, brain.pose != .eat, brain.pose != .sleep, !state.cardBelow {
            // A thought bubble: a bone when hungry, a broken heart when lonely, a fever when sick.
            Text(thought)
                .font(.system(size: 12 * scale))
                .padding(6 * scale)
                .background(Circle().fill(.white.opacity(0.9)))
                .offset(x: 26 * scale)
        }
    }

    private var thought: String? {
        switch brain.mood {
        case .sick: "🤒"
        case .hungry, .starving: "🦴"
        case .lonely: "💔"
        case .stuffed: "😣"
        default: nil
        }
    }

    private func cat(_ scale: CGFloat) -> some View {
        ZStack(alignment: .top) {
            // Smooth while it moves; a sitting or sleeping dog (breathing, wagging, blinking) looks
            // the same at 12 frames a second and costs half as much.
            TimelineView(.animation(minimumInterval: brain.pose.travels || state.playfulSince != nil ? 1 / 24 : 1 / 12)) { context in
                let playing = state.playfulSince != nil
                let t = context.date.timeIntervalSinceReferenceDate
                    * (brain.pose.travels ? (playing ? 10 : 7) * brain.pace : 2)
                CatFigure(pose: brain.pose, mood: brain.mood, color: settings.catColor, time: t, girth: brain.girth)
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

/// Name, mood, food, love and health, with Feed (and Vet when it's ill). Used over the desktop
/// pet and in the Widgets tab.
struct CatCard: View {
    @ObservedObject var brain: CatBrain
    let name: String
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(name).font(.system(size: 12, weight: .bold))
                        Text(brain.isAway ? "At the vet" : (brain.isNight && brain.pose == .sleep ? "Asleep" : brain.mood.title))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(moodTint)
                    }
                    meter(symbol: "fork.knife", value: brain.fullness,
                          tint: brain.mood == .stuffed ? .red : (brain.isHungry ? .orange : .green),
                          help: brain.hungerText)
                    meter(symbol: "heart.fill", value: brain.affection, tint: Color(red: 1, green: 0.4, blue: 0.55),
                          help: brain.mood == .lonely ? "Lonely: pet it" : "Love")
                    meter(symbol: "cross.fill", value: brain.health, tint: brain.health < 0.55 ? .red : .mint,
                          help: brain.healthText)
                    Text(status)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                if brain.isAway {
                    Image(systemName: "cross.case.fill").font(.system(size: 18)).foregroundStyle(.green).frame(width: 58)
                } else if brain.isSick {
                    Button { brain.takeToVet() } label: {
                        Label("Vet", systemImage: "cross.case.fill").font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(CatButtonStyle(fill: Color(red: 0.95, green: 0.35, blue: 0.4)))
                    .help("The vet keeps \(name) for 20 minutes and sends it home better")
                } else {
                    // Feed only: petting is a click on the pet itself.
                    Button { brain.feed() } label: {
                        Label("Feed", systemImage: "fork.knife").font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(CatButtonStyle(fill: brain.fullness > 0.55 || brain.stomach > 0.05
                        ? Color(white: 0.4) : Color(red: 0.35, green: 0.62, blue: 1)))
                    .help(brain.fullness > 0.55 ? "\(name) isn't hungry: extra food puts weight on" : "Feed \(name)")
                }
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

    private var moodTint: Color {
        if brain.isAway { return .green }
        switch brain.mood {
        case .happy, .content: return .green
        case .hungry, .stuffed: return .orange
        case .starving, .sick: return .red
        case .lonely: return .pink
        }
    }

    /// One line on the thing most worth knowing.
    private var status: String {
        if let back = brain.awayUntil, brain.isAway {
            return "Back at \(back.formatted(date: .omitted, time: .shortened))"
        }
        if brain.isSick { return "Needs the vet, or rest and care" }
        if brain.mood == .stuffed { return "Overfed: no food for a while" }
        if brain.isOverweight { return "\(brain.weightText): feed only when hungry" }
        if brain.weight < 0.22 { return "Underweight: feed it more often" }
        if let note = brain.vetNote, brain.health < 0.95 { return note }
        return brain.weightText
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
