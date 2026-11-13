import CoreLocation
import Foundation
import SwiftUI

// MARK: - Catalog

/// Real stars and constellation lines from the bundled catalog (d3-celestial, BSD-3-Clause; see README).
struct SkyCatalog {
    struct Star { let ra: Double; let dec: Double; let mag: Double; let bv: Double }

    let stars: [Star]
    let lines: [[[Double]]]

    static let shared: SkyCatalog = {
        struct File: Decodable { let stars: [[Double]]; let lines: [String: [[[Double]]]] }
        guard let url = Bundle.main.url(forResource: "sky", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else { return SkyCatalog(stars: [], lines: []) }
        return SkyCatalog(stars: file.stars.map { Star(ra: $0[0], dec: $0[1], mag: $0[2], bv: $0[3]) },
                          lines: file.lines.values.flatMap { $0 })
    }()
}

// MARK: - Astronomy

/// Low-precision formulas, accurate to a fraction of a degree: plenty for drawing the sky.
enum Astronomy {
    static let rad = Double.pi / 180

    /// Days since J2000.0 (2000-01-01 12:00 TT, taken as UTC here).
    static func daysSinceJ2000(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 + 2_440_587.5 - 2_451_545.0
    }

    /// Local sidereal time in degrees.
    static func localSiderealTime(_ date: Date, longitude: Double) -> Double {
        let gmst = 280.46061837 + 360.98564736629 * daysSinceJ2000(date)
        return (gmst + longitude).truncatingRemainder(dividingBy: 360)
    }

    /// Altitude and azimuth (degrees; azimuth from north through east) of a point at RA/Dec.
    static func horizontal(ra: Double, dec: Double, latitude: Double, lst: Double) -> (alt: Double, az: Double) {
        let h = (lst - ra) * rad, d = dec * rad, phi = latitude * rad
        let sinAlt = sin(phi) * sin(d) + cos(phi) * cos(d) * cos(h)
        let alt = asin(max(-1, min(1, sinAlt)))
        let az = atan2(-sin(h) * cos(d), cos(phi) * sin(d) - sin(phi) * cos(d) * cos(h))
        return (alt / rad, (az / rad + 360).truncatingRemainder(dividingBy: 360))
    }

    /// Ecliptic longitude/latitude to RA/Dec (degrees).
    static func equatorial(lambda: Double, beta: Double) -> (ra: Double, dec: Double) {
        let e = 23.4393 * rad, l = lambda * rad, b = beta * rad
        let ra = atan2(sin(l) * cos(e) - tan(b) * sin(e), cos(l))
        let dec = asin(sin(b) * cos(e) + cos(b) * sin(e) * sin(l))
        return ((ra / rad + 360).truncatingRemainder(dividingBy: 360), dec / rad)
    }

    static func sun(_ date: Date) -> (ra: Double, dec: Double, lambda: Double) {
        let d = daysSinceJ2000(date)
        let l0 = 280.460 + 0.9856474 * d
        let g = (357.528 + 0.9856003 * d) * rad
        let lambda = l0 + 1.915 * sin(g) + 0.020 * sin(2 * g)
        let eq = equatorial(lambda: lambda, beta: 0)
        return (eq.ra, eq.dec, lambda)
    }

    /// The Moon's position and how much of it is lit (0 new … 1 full).
    static func moon(_ date: Date) -> (ra: Double, dec: Double, illuminated: Double, waxing: Bool) {
        let d = daysSinceJ2000(date)
        let l = 218.316 + 13.176396 * d
        let m = (134.963 + 13.064993 * d) * rad
        let f = (93.272 + 13.229350 * d) * rad
        let lambda = l + 6.289 * sin(m)
        let beta = 5.128 * sin(f)
        let eq = equatorial(lambda: lambda, beta: beta)
        let elongation = (lambda - sun(date).lambda).truncatingRemainder(dividingBy: 360)
        let e = (elongation + 360).truncatingRemainder(dividingBy: 360)
        return (eq.ra, eq.dec, (1 - cos(e * rad)) / 2, e < 180)
    }
}

// MARK: - Where the sky is seen from

/// The observer: from the Mac's time zone by default (no permission needed), or Location Services if chosen.
@MainActor
final class SkyLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = SkyLocation()

    @Published private(set) var latitude: Double
    @Published private(set) var longitude: Double
    @Published private(set) var source: String
    @AppStorage("skyPreciseLocation") var precise = false {
        didSet { precise ? requestPrecise() : useTimeZone() }
    }

    private let manager = CLLocationManager()

    override private init() {
        let zone = SkyLocation.timeZoneCoordinate()
        latitude = zone.lat
        longitude = zone.lon
        source = zone.name
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        if precise { requestPrecise() }
    }

    private func useTimeZone() {
        let zone = SkyLocation.timeZoneCoordinate()
        latitude = zone.lat
        longitude = zone.lon
        source = zone.name
    }

    private func requestPrecise() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: source = "\(SkyLocation.timeZoneCoordinate().name) (Location Services is off)"
        default: manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in if self.precise { self.requestPrecise() } }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        Task { @MainActor in
            guard self.precise else { return }
            self.latitude = c.latitude
            self.longitude = c.longitude
            self.source = String(format: "%.1f°, %.1f° (Location Services)", c.latitude, c.longitude)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    /// The reference city for the Mac's time zone, from the system's zone table; local, no network.
    static func timeZoneCoordinate(_ zone: TimeZone = .current) -> (lat: Double, lon: Double, name: String) {
        let city = zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone.identifier
        for path in ["/usr/share/zoneinfo/zone.tab", "/usr/share/zoneinfo/zone1970.tab"] {
            guard let table = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            for line in table.split(separator: "\n") where !line.hasPrefix("#") {
                let cols = line.split(separator: "\t")
                guard cols.count >= 3, cols[2] == zone.identifier, let c = parseISO6709(String(cols[1])) else { continue }
                return (c.lat, c.lon, "\(city) (from your time zone)")
            }
        }
        return (30, Double(zone.secondsFromGMT()) / 240, "\(city) (approximate)")
    }

    /// "+314650+0351326" → (31.78, 35.22)
    static func parseISO6709(_ s: String) -> (lat: Double, lon: Double)? {
        guard let split = s.dropFirst().firstIndex(where: { $0 == "+" || $0 == "-" }) else { return nil }
        func value(_ part: Substring, degreeDigits: Int) -> Double? {
            let sign: Double = part.first == "-" ? -1 : 1
            let digits = part.dropFirst()
            guard digits.count >= degreeDigits + 2,
                  let deg = Double(digits.prefix(degreeDigits)),
                  let min = Double(digits.dropFirst(degreeDigits).prefix(2)) else { return nil }
            let sec = Double(digits.dropFirst(degreeDigits + 2).prefix(2)) ?? 0
            return sign * (deg + min / 60 + sec / 3600)
        }
        guard let lat = value(s[..<split], degreeDigits: 2), let lon = value(s[split...], degreeDigits: 3) else { return nil }
        return (lat, lon)
    }
}

// MARK: - Projection

/// Looking up toward the south (north below the equator), horizon near the bottom. The horizontal field of view
/// is fixed, so the zoom never changes; a taller panel tilts the view up toward the zenith instead.
struct SkyProjection {
    let size: CGSize
    let latitude: Double
    var centerAz: Double { latitude >= 0 ? 180 : 0 }
    /// Where the horizon sits, measured up from the bottom edge (it stays clear of the floating footer).
    let horizonInset: CGFloat = 90
    /// Horizontal field of view, degrees.
    let fieldOfView = 100.0

    private var scale: CGFloat { (size.width / 2) / CGFloat(2 * tan(fieldOfView / 2 * Astronomy.rad / 2)) }

    /// The altitude at the centre of the view that puts the horizon `horizonInset` above the bottom edge.
    var centerAlt: Double {
        let below = max(0, size.height / 2 - horizonInset)
        return min(80, 2 * atan(Double(below / scale) / 2) / Astronomy.rad)
    }

    /// Stereographic projection; nil for points behind the viewer.
    func point(alt: Double, az: Double) -> CGPoint? {
        let a = alt * Astronomy.rad, a0 = centerAlt * Astronomy.rad
        let dAz = (az - centerAz) * Astronomy.rad
        let cosC = sin(a0) * sin(a) + cos(a0) * cos(a) * cos(dAz)
        guard cosC > -0.3 else { return nil }
        let k = 2 / (1 + cosC)
        let x = k * cos(a) * sin(dAz)
        let y = k * (cos(a0) * sin(a) - sin(a0) * cos(a) * cos(dAz))
        // East is to the left when facing south, as on a real sky.
        return CGPoint(x: size.width / 2 - CGFloat(x) * scale, y: size.height / 2 - CGFloat(y) * scale)
    }
}

// MARK: - Drawing

/// Everything placed for one minute: recomputed only when the minute, place or size changes.
struct SkyFrame {
    struct Point { let p: CGPoint; let mag: Double; let color: Color }
    let stars: [Point]
    let segments: [(CGPoint, CGPoint)]
    let horizon: [CGPoint]
    let moon: (p: CGPoint, illuminated: Double, waxing: Bool, sunAngle: Double)?
    let sunAlt: Double
    let cardinal: [(String, CGPoint)]

    @MainActor static func make(date: Date, latitude: Double, longitude: Double, size: CGSize) -> SkyFrame {
        let lst = Astronomy.localSiderealTime(date, longitude: longitude)
        let projection = SkyProjection(size: size, latitude: latitude)
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -20, dy: -20)

        func place(_ ra: Double, _ dec: Double) -> (CGPoint, Double)? {
            let h = Astronomy.horizontal(ra: ra, dec: dec, latitude: latitude, lst: lst)
            guard h.alt > -2, let p = projection.point(alt: h.alt, az: h.az), bounds.contains(p) else { return nil }
            return (p, h.alt)
        }

        let catalog = SkyCatalog.shared
        let stars = catalog.stars.compactMap { s -> Point? in
            guard let (p, _) = place(s.ra, s.dec) else { return nil }
            return Point(p: p, mag: s.mag, color: starColor(bv: s.bv))
        }
        var segments: [(CGPoint, CGPoint)] = []
        for line in catalog.lines {
            for pair in zip(line, line.dropFirst()) {
                if let a = place(pair.0[0], pair.0[1]), let b = place(pair.1[0], pair.1[1]) { segments.append((a.0, b.0)) }
            }
        }
        let horizon = stride(from: projection.centerAz - 120, through: projection.centerAz + 120, by: 3)
            .compactMap { projection.point(alt: 0, az: $0) }
        let sun = Astronomy.sun(date)
        let sunH = Astronomy.horizontal(ra: sun.ra, dec: sun.dec, latitude: latitude, lst: lst)
        var moonInfo: (CGPoint, Double, Bool, Double)?
        let m = Astronomy.moon(date)
        if let (mp, _) = place(m.ra, m.dec) {
            // Which way the lit side faces: toward the Sun as projected on this view.
            let sp = projection.point(alt: sunH.alt, az: sunH.az) ?? CGPoint(x: size.width / 2, y: size.height * 2)
            moonInfo = (mp, m.illuminated, m.waxing, atan2(sp.y - mp.y, sp.x - mp.x))
        }
        let south = projection.centerAz
        let cardinal = [(south == 180 ? "S" : "N", south), ("E", 90.0), ("W", 270.0), (south == 180 ? "SE" : "NE", south == 180 ? 135 : 45),
                        (south == 180 ? "SW" : "NW", south == 180 ? 225 : 315)]
            .compactMap { label, az -> (String, CGPoint)? in
                guard let p = projection.point(alt: 0, az: az), p.x > 12, p.x < size.width - 12 else { return nil }
                return (label, p)
            }
        return SkyFrame(stars: stars, segments: segments, horizon: horizon, moon: moonInfo, sunAlt: sunH.alt, cardinal: cardinal)
    }

    /// Star colour from its B-V colour index: blue-white for hot stars, amber for cool ones.
    static func starColor(bv: Double) -> Color {
        switch bv {
        case ..<0.0: return Color(red: 0.74, green: 0.83, blue: 1.0)
        case ..<0.3: return Color(red: 0.88, green: 0.92, blue: 1.0)
        case ..<0.6: return Color(red: 1.0, green: 0.98, blue: 0.95)
        case ..<1.0: return Color(red: 1.0, green: 0.92, blue: 0.78)
        case ..<1.4: return Color(red: 1.0, green: 0.84, blue: 0.64)
        default: return Color(red: 1.0, green: 0.76, blue: 0.56)
        }
    }
}

/// The real sky over the observer, right now: stars, constellation lines, the Moon and a twilight glow.
struct RealSky: View {
    @ObservedObject private var location = SkyLocation.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.skyDate) private var fixedDate
    @Environment(\.frozenTime) private var frozenTime
    @AppStorage("animatedSky") private var animatedSky = true
    @AppStorage("constellationLines") private var constellationLines = true

    var body: some View {
        GeometryReader { geo in
            TimelineView(.everyMinute) { minute in
                let date = fixedDate ?? minute.date
                let frame = SkyFrame.make(date: date, latitude: location.latitude, longitude: location.longitude, size: geo.size)
                ZStack {
                    twilight(frame.sunAlt)
                    Canvas { ctx, _ in drawStatic(frame, in: &ctx) }
                    if reduceMotion || !animatedSky || frozenTime != nil {
                        Canvas { ctx, _ in drawBright(frame, time: frozenTime ?? 0, in: &ctx) }
                    } else {
                        TimelineView(.animation(minimumInterval: 1 / 12)) { tick in
                            Canvas { ctx, _ in drawBright(frame, time: tick.date.timeIntervalSinceReferenceDate, in: &ctx) }
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var night: Bool { scheme == .dark }

    /// A faint glow on the horizon that follows the real Sun: blue twilight, deeper after dusk.
    @ViewBuilder
    private func twilight(_ sunAlt: Double) -> some View {
        let strength = max(0, min(1, (sunAlt + 18) / 18))
        LinearGradient(colors: [.clear, Color(red: 0.35, green: 0.48, blue: 0.75).opacity(night ? 0.10 + 0.28 * strength : 0.25)],
                       startPoint: .center, endPoint: .bottom)
    }

    private func drawStatic(_ frame: SkyFrame, in ctx: inout GraphicsContext) {
        let ink: Color = night ? .white : Color(red: 0.25, green: 0.33, blue: 0.5)
        if constellationLines {
            var path = Path()
            for (a, b) in frame.segments { path.move(to: a); path.addLine(to: b) }
            ctx.stroke(path, with: .color(ink.opacity(night ? 0.065 : 0.10)), lineWidth: 0.6)
        }
        // Ground below the horizon, so the sky reads as a sky.
        if let first = frame.horizon.first, let last = frame.horizon.last {
            var ground = Path()
            ground.move(to: CGPoint(x: first.x, y: first.y))
            for p in frame.horizon { ground.addLine(to: p) }
            ground.addLine(to: CGPoint(x: last.x, y: 4000))
            ground.addLine(to: CGPoint(x: first.x, y: 4000))
            ground.closeSubpath()
            ctx.fill(ground, with: .color((night ? Color.black : Color(red: 0.86, green: 0.9, blue: 0.96)).opacity(night ? 0.45 : 0.6)))
            var line = Path()
            line.addLines(frame.horizon)
            ctx.stroke(line, with: .color(ink.opacity(0.14)), lineWidth: 0.75)
        }
        for (label, p) in frame.cardinal {
            ctx.draw(Text(label).font(.system(size: 9, weight: .semibold)).foregroundColor(ink.opacity(0.35)),
                     at: CGPoint(x: p.x, y: p.y + 9))
        }
        for star in frame.stars where star.mag >= 2.6 {
            let r = max(0.45, 1.95 - 0.28 * star.mag)
            let opacity = max(0.18, min(0.95, 1.15 - 0.14 * star.mag))
            ctx.fill(Path(ellipseIn: CGRect(x: star.p.x - r, y: star.p.y - r, width: r * 2, height: r * 2)),
                     with: .color(night ? star.color.opacity(opacity) : ink.opacity(opacity * 0.5)))
        }
        if let moon = frame.moon { drawMoon(moon, in: &ctx) }
    }

    /// The brightest stars, with a soft glow and a gentle twinkle.
    private func drawBright(_ frame: SkyFrame, time: TimeInterval, in ctx: inout GraphicsContext) {
        let ink: Color = night ? .white : Color(red: 0.25, green: 0.33, blue: 0.5)
        for (i, star) in frame.stars.enumerated() where star.mag < 2.6 {
            let twinkle = 0.82 + 0.18 * sin(time * 1.7 + Double(i) * 1.37)
            let r = max(1.0, 2.2 - 0.32 * star.mag)
            if night {
                var glow = ctx
                glow.addFilter(.blur(radius: r * 1.6))
                glow.fill(Path(ellipseIn: CGRect(x: star.p.x - r * 1.6, y: star.p.y - r * 1.6, width: r * 3.2, height: r * 3.2)),
                          with: .color(star.color.opacity(0.35 * twinkle)))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: star.p.x - r, y: star.p.y - r, width: r * 2, height: r * 2)),
                     with: .color(night ? star.color.opacity(twinkle) : ink.opacity(0.55 * twinkle)))
        }
    }

    private func drawMoon(_ moon: (p: CGPoint, illuminated: Double, waxing: Bool, sunAngle: Double), in ctx: inout GraphicsContext) {
        let r: CGFloat = 7
        let rect = CGRect(x: moon.p.x - r, y: moon.p.y - r, width: r * 2, height: r * 2)
        var glow = ctx
        glow.addFilter(.blur(radius: 9))
        glow.fill(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)),
                  with: .color(Color(red: 0.85, green: 0.9, blue: 1).opacity(0.25 + 0.35 * moon.illuminated)))
        ctx.fill(Path(ellipseIn: rect), with: .color(Color(red: 0.25, green: 0.28, blue: 0.35).opacity(0.9)))
        // Lit part: a half-disc toward the Sun plus (or minus) an ellipse for the terminator.
        var lit = ctx
        lit.translateBy(x: moon.p.x, y: moon.p.y)
        lit.rotate(by: .radians(moon.sunAngle))
        let k = moon.illuminated
        var half = Path()
        half.addArc(center: .zero, radius: r, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        let w = r * CGFloat(abs(1 - 2 * k))
        let terminator = Path(ellipseIn: CGRect(x: -w, y: -r, width: w * 2, height: r * 2))
        let light = Color(red: 0.94, green: 0.95, blue: 0.98)
        let dark = Color(red: 0.25, green: 0.28, blue: 0.35)
        lit.fill(half, with: .color(light))
        // Gibbous: the terminator bulges into the dark half. Crescent: it eats into the lit half.
        lit.fill(terminator, with: .color(k >= 0.5 ? light : dark))
    }
}

private struct SkyDateKey: EnvironmentKey { static let defaultValue: Date? = nil }

extension EnvironmentValues {
    /// A fixed moment for the sky, used by snapshot renders.
    var skyDate: Date? {
        get { self[SkyDateKey.self] }
        set { self[SkyDateKey.self] = newValue }
    }
}

// MARK: - Moon phase

/// Tonight's real Moon phase, for the empty and welcome states.
struct MoonPhaseView: View {
    var size: CGFloat = 44
    @Environment(\.skyDate) private var fixedDate

    var body: some View {
        let moon = Astronomy.moon(fixedDate ?? Date())
        let phase = MoonPhaseView.name(illuminated: moon.illuminated, waxing: moon.waxing)
        VStack(spacing: 6) {
            MoonDisc(illuminated: moon.illuminated, waxing: moon.waxing)
                .frame(width: size, height: size)
                .shadow(color: Color(red: 0.8, green: 0.87, blue: 1).opacity(0.35 + 0.3 * moon.illuminated), radius: 14)
            Text("\(phase.name) · \(Int((moon.illuminated * 100).rounded()))% lit")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.tertiaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tonight's Moon: \(phase.name)")
    }

    static func name(illuminated k: Double, waxing: Bool) -> (name: String, symbol: String) {
        switch k {
        case ..<0.03: return ("New moon", "moonphase.new.moon")
        case ..<0.40: return waxing ? ("Waxing crescent", "moonphase.waxing.crescent") : ("Waning crescent", "moonphase.waning.crescent")
        case ..<0.60: return waxing ? ("First quarter", "moonphase.first.quarter") : ("Last quarter", "moonphase.last.quarter")
        case ..<0.97: return waxing ? ("Waxing gibbous", "moonphase.waxing.gibbous") : ("Waning gibbous", "moonphase.waning.gibbous")
        default: return ("Full moon", "moonphase.full.moon")
        }
    }
}

/// A Moon drawn from its illuminated fraction: lit on the right while waxing, on the left while waning
/// (as seen from the northern hemisphere).
struct MoonDisc: View {
    let illuminated: Double
    let waxing: Bool

    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            let light = Color(red: 0.95, green: 0.96, blue: 0.99)
            let dark = Color(red: 0.22, green: 0.25, blue: 0.32)
            ctx.fill(disc, with: .color(dark))
            var lit = ctx
            lit.clip(to: disc)
            lit.translateBy(x: c.x, y: c.y)
            if !waxing { lit.scaleBy(x: -1, y: 1) }
            var half = Path()
            half.addArc(center: .zero, radius: r, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            half.closeSubpath()
            lit.fill(half, with: .color(light))
            let w = r * CGFloat(abs(1 - 2 * illuminated))
            let terminator = Path(ellipseIn: CGRect(x: -w, y: -r, width: w * 2, height: r * 2))
            lit.fill(terminator, with: .color(illuminated >= 0.5 ? light : dark))
            ctx.stroke(disc, with: .color(.white.opacity(0.25)), lineWidth: 0.75)
        }
    }
}
