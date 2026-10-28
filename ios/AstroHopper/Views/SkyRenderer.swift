import SwiftUI

struct SkyStyle {
    var cross, constellations, bearing, star, altaz, target, align: Color

    static let day = SkyStyle(cross: .blue, constellations: .yellow, bearing: .green, star: .white,
                              altaz: .red, target: .cyan, align: Color(red: 1, green: 0, blue: 1))
    static let night = SkyStyle(cross: .red, constellations: Color(red: 0x88 / 255.0, green: 0, blue: 0), bearing: .red,
                                star: .red, altaz: .red, target: .red, align: Color(red: 0xAA / 255.0, green: 0, blue: 0))
}

/// CSS millimetres (as used by the web app's font sizes) in points.
let pointsPerMM = 96.0 / 25.4

/// Draws one frame of the sky map; a port of the web app's `plotStars()` family.
@MainActor
struct SkyRenderer {
    let model: AppModel
    let size: CGSize
    let date: Date

    private var style: SkyStyle { model.nightMode ? .night : .day }

    private func font(_ mm: Double) -> Font {
        .system(size: (mm + Double(model.fontBoost)) * pointsPerMM)
    }

    func draw(_ ctx: inout GraphicsContext) {
        let w = size.width, h = size.height
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        guard w > 0, h > 0 else { return }

        let cam = model.cameraRays()
        let camera = Mat3(r0: -cam.left, r1: cam.top, r2: cam.fwd)
        // objects outside the altitude limits stay tappable, so that tapping
        // one selects nothing rather than a neighbor (see AppModel.tap)
        let toCamera = camera * model.equatorialToENU(date)
        let proj = Projection(fovDegrees: model.fov, width: w, height: h)
        let catalog = model.catalog
        let waitingForAlign = model.waitingForAlign
        let targetIndex = model.targetIndex, alignIndex = model.alignIndex
        let suggestion = model.isAligningNextStar ? model.suggestedAlignIndex : nil
        let starMag = Double(model.starMag), dsoMag = Double(model.dsoMag)
        let shown = model.shown
        var targets: [(x: Double, y: Double, index: Int)] = []

        var i = 0
        while i < catalog.count {
            let obj = catalog[i]
            let t = obj.type
            if (t == .star && obj.mag > starMag) || (t != .star && obj.mag > dsoMag) || shown[t] != true {
                i = max(i + 1, catalog.typeEnd[t] ?? catalog.count)
                continue
            }
            let highlight = (i == targetIndex || i == alignIndex || i == suggestion) ? 0 : 1
            if let pos = plot(obj, toCamera: toCamera, proj: proj, highlight: highlight, ctx: &ctx),
               t != .constellation, !waitingForAlign || model.validAlignType(t) {
                targets.append((pos.x, pos.y, i))
            }
            i += 1
        }
        if let a = alignIndex, a != targetIndex {
            _ = plot(catalog[a], toCamera: toCamera, proj: proj, highlight: 2, ctx: &ctx)
        }
        if let ti = targetIndex {
            let star = catalog[ti]
            if suggestion == nil { plotBearing(toCamera * star.eq, proj: proj, ctx: &ctx) }
            // a target fainter than the limit (found by search) is still selectable
            if let pos = plot(star, toCamera: toCamera, proj: proj, highlight: 3, ctx: &ctx),
               model.validAlignType(star.type), !targets.contains(where: { $0.index == ti }) {
                targets.append((pos.x, pos.y, ti))
            }
        }
        if let si = suggestion {
            let star = catalog[si]
            plotBearing(toCamera * star.eq, proj: proj, ctx: &ctx)
            if let pos = plot(star, toCamera: toCamera, proj: proj, highlight: 2, ctx: &ctx),
               !targets.contains(where: { $0.index == si }) {
                targets.append((pos.x, pos.y, si))
            }
        }
        if targetIndex == nil && suggestion == nil && model.aligned {
            plotCross(ctx: &ctx)
        }
        plotFieldCircles(proj: proj, ctx: &ctx)
        if let max = model.maxAltitude {
            plotAltitudeLimit(max, label: "\(Int(max))° maximum", camera: camera, proj: proj, ctx: &ctx)
        }
        if let min = model.minAltitude {
            plotAltitudeLimit(min, label: "\(Int(min))° minimum", camera: camera, proj: proj, ctx: &ctx)
        }
        if let scope = model.telescope.pointingENU {
            plotTelescope(camera * scope, proj: proj, ctx: &ctx)
        }
        plotLines(toCamera: toCamera, proj: proj, ctx: &ctx)
        model.hitTargets.items = targets
    }

    /// Port of `plotStar()`. highlight: 0 = position only (drawn later),
    /// 1 = normal, 2 = alignment star, 3 = target.
    private func plot(_ star: SkyObject, toCamera: Mat3, proj: Projection, highlight: Int,
                      ctx: inout GraphicsContext) -> CGPoint? {
        guard let p = proj.project(toCamera * star.eq) else { return nil }
        let x = p.x * size.width, y = p.y * size.height
        let result = CGPoint(x: x, y: y)
        if highlight == 0 { return result }

        var sz = star.type == .star ? 6.5 - star.mag : 6
        if sz < 1 { sz = 1 }
        var color: Color
        if highlight >= 2 {
            color = highlight == 3 ? style.target : style.align
            sz = 10
        } else {
            color = style.star
        }
        let fill: Color = star.type == .star ? color : .black

        func circle(_ r: Double) -> Path {
            Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        }
        let dotted = StrokeStyle(lineWidth: 2, dash: [1, 3])

        switch star.type {
        case .constellation:
            break
        case .galaxy:
            let ellipse = Path(ellipseIn: CGRect(x: -sz * 1.5, y: -sz / 1.5, width: sz * 3, height: sz * 2 / 1.5))
                .applying(CGAffineTransform(rotationAngle: .pi / 4).concatenating(CGAffineTransform(translationX: x, y: y)))
            ctx.fill(ellipse, with: .color(fill))
            ctx.stroke(ellipse, with: .color(color), lineWidth: 1)
            ctx.fill(circle(sz / 3), with: .color(color))
        case .globularCluster:
            ctx.stroke(circle(sz), with: .color(color), style: dotted)
            ctx.fill(circle(sz / 3), with: .color(color))
        case .openCluster:
            ctx.stroke(circle(sz), with: .color(color), style: dotted)
            ctx.fill(circle(sz / 3), with: .color(fill))
            ctx.stroke(circle(sz / 3), with: .color(color), style: dotted)
        case .nebula:
            var curve = Path()
            curve.move(to: CGPoint(x: x - sz, y: y - sz))
            curve.addCurve(to: CGPoint(x: x + sz, y: y + sz),
                           control1: CGPoint(x: x + 4 * sz, y: y - sz),
                           control2: CGPoint(x: x - 4 * sz, y: y + sz))
            ctx.stroke(curve, with: .color(color), lineWidth: 1)
            ctx.fill(circle(sz / 3), with: .color(color))
        case .user:
            var diamond = Path()
            diamond.move(to: CGPoint(x: x - sz, y: y))
            diamond.addLine(to: CGPoint(x: x, y: y + sz))
            diamond.addLine(to: CGPoint(x: x + sz, y: y))
            diamond.addLine(to: CGPoint(x: x, y: y - sz))
            diamond.closeSubpath()
            ctx.fill(diamond, with: .color(.black))
            ctx.stroke(diamond, with: .color(color), lineWidth: 2)
        case .star, .planet:
            ctx.fill(circle(sz), with: .color(fill))
            ctx.stroke(circle(sz), with: .color(color), lineWidth: 1)
        }

        guard star.name != nil || highlight >= 2 else { return result }
        if star.type == .constellation {
            ctx.draw(Text(star.name ?? "").font(font(4)).foregroundStyle(style.constellations),
                     at: result, anchor: .center)
            return result
        }
        var text = star.name ?? ""
        if star.type == .star && !model.showStarNames && highlight < 3 { text = "" }
        var extra: [String] = []
        var altNames: [String] = []
        let labelFont = highlight > 1 ? font(6) : font(3)
        if highlight == 3 {
            if star.mag != -1 { extra.append("m=" + String(format: "%.1f", star.mag)) }
            if star.size > 0 { extra.append(Format.size(arcmin: star.size)) }
            altNames = star.altNames
        }
        let lx = x + sz + 1
        if !text.isEmpty {
            ctx.draw(Text(text).font(labelFont).foregroundStyle(color),
                     at: CGPoint(x: lx, y: y - sz - 1), anchor: .bottomLeading)
        }
        if !extra.isEmpty {
            ctx.draw(Text(extra.joined(separator: ", ")).font(labelFont).foregroundStyle(color),
                     at: CGPoint(x: lx, y: y - sz / 2 - 1), anchor: .topLeading)
        }
        if !altNames.isEmpty {
            ctx.draw(Text(altNames.joined(separator: ", ")).font(labelFont).foregroundStyle(color),
                     at: CGPoint(x: lx, y: y + 2 * sz - 1), anchor: .topLeading)
        }
        return result
    }

    private func plotLines(toCamera: Mat3, proj: Projection, ctx: inout GraphicsContext) {
        guard model.shown[.constellation] == true else { return }
        var path = Path()
        for line in model.catalog.lines {
            guard let p1 = proj.project(toCamera * line.eq0, inFOV: false),
                  let p2 = proj.project(toCamera * line.eq1, inFOV: false) else { continue }
            path.move(to: CGPoint(x: p1.x * size.width, y: p1.y * size.height))
            path.addLine(to: CGPoint(x: p2.x * size.width, y: p2.y * size.height))
        }
        ctx.stroke(path, with: .color(style.constellations), lineWidth: 1)
    }

    /// Finder and eyepiece fields of view around the view center. The map
    /// projection is orthographic, so a circle of angular radius r has a
    /// screen radius proportional to sin(r).
    private func plotFieldCircles(proj: Projection, ctx: inout GraphicsContext) {
        let circles = model.fieldCircles
        let cx = size.width / 2, cy = size.height / 2
        for (diameter, label, inside) in [(circles.finder, "Finder", model.guideInFinder),
                                          (circles.eyepiece, "Eyepiece", model.guideInEyepiece)] {
            guard let diameter else { continue }
            let r = sin(diameter / 2 * deg2rad) / (2 * proj.limX) * size.width
            guard r >= 3 else { continue }
            let path = Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
            let color = inside ? style.bearing : style.cross
            ctx.stroke(path, with: .color(color.opacity(inside ? 1 : 0.8)),
                       style: StrokeStyle(lineWidth: inside ? 3 : 1.5, dash: label == "Finder" ? [6, 4] : []))
            if r > 30 && r < size.width / 2 - 20 {
                ctx.draw(Text(label).font(font(2.5)).foregroundStyle(color),
                         at: CGPoint(x: cx + r * 0.71 + 3, y: cy - r * 0.71 - 3), anchor: .bottomLeading)
            }
        }
    }

    /// An altitude limit: a dashed circle of constant altitude.
    private func plotAltitudeLimit(_ limit: Double, label: String, camera: Mat3, proj: Projection,
                                   ctx: inout GraphicsContext) {
        let h = limit * deg2rad
        var path = Path()
        var penDown = false
        var labelAt: CGPoint?
        for step in 0...120 {
            let a = Double(step) * 3 * deg2rad
            let enu = Vec3(cos(h) * sin(a), cos(h) * cos(a), sin(h))
            guard let p = proj.project(camera * enu, inFOV: false) else {
                penDown = false
                continue
            }
            let pt = CGPoint(x: p.x * size.width, y: p.y * size.height)
            if penDown { path.addLine(to: pt) } else { path.move(to: pt) }
            penDown = true
            if labelAt == nil, pt.x > 40, pt.x < size.width - 120, pt.y > 140, pt.y < size.height - 260 {
                labelAt = pt
            }
        }
        ctx.stroke(path, with: .color(style.altaz.opacity(0.8)), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
        if let labelAt {
            ctx.draw(Text(label).font(font(2.5)).foregroundStyle(style.altaz),
                     at: CGPoint(x: labelAt.x + 4, y: labelAt.y - 4), anchor: .bottomLeading)
        }
    }

    /// Where the connected mount points: a square reticle labelled "Scope".
    private func plotTelescope(_ xyz: Vec3, proj: Projection, ctx: inout GraphicsContext) {
        guard let p = proj.project(xyz) else { return }
        let x = p.x * size.width, y = p.y * size.height
        var path = Path(CGRect(x: x - 9, y: y - 9, width: 18, height: 18))
        for (dx, dy) in [(1.0, 0.0), (0, 1), (-1, 0), (0, -1)] {
            path.move(to: CGPoint(x: x + 9 * dx, y: y + 9 * dy))
            path.addLine(to: CGPoint(x: x + 16 * dx, y: y + 16 * dy))
        }
        ctx.stroke(path, with: .color(style.align), lineWidth: 2)
        ctx.draw(Text("Scope").font(font(2.5)).foregroundStyle(style.align),
                 at: CGPoint(x: x + 18, y: y + 18), anchor: .topLeading)
    }

    private func plotCross(ctx: inout GraphicsContext) {
        let cx = size.width / 2, cy = size.height / 2
        var path = Path()
        for (dx, dy) in [(1.0, 0.0), (0, 1), (-1, 0), (0, -1)] {
            path.move(to: CGPoint(x: cx + 10 * dx, y: cy + 10 * dy))
            path.addLine(to: CGPoint(x: cx + 50 * dx, y: cy + 50 * dy))
        }
        ctx.stroke(path, with: .color(style.cross), lineWidth: 3)
    }

    /// Port of `plotBearing()`: a line from the center toward the target. The
    /// angles still to move are shown on the target card.
    private func plotBearing(_ xyz: Vec3, proj: Projection, ctx: inout GraphicsContext) {
        let cx = size.width / 2, cy = size.height / 2
        var path = Path(ellipseIn: CGRect(x: cx - 10, y: cy - 10, width: 20, height: 20))
        var dx = xyz.x, dy = -xyz.y
        let norm = (dx * dx + dy * dy).squareRoot()
        if norm > 0 {
            dx /= norm
            dy /= norm
            var len = 100.0
            if let pos = proj.project(xyz) {
                let px = size.width * (pos.x - 0.5), py = size.height * (pos.y - 0.5)
                len = min(len, (px * px + py * py).squareRoot())
            }
            path.move(to: CGPoint(x: cx, y: cy))
            path.addLine(to: CGPoint(x: cx + dx * len, y: cy + dy * len))
        }
        ctx.stroke(path, with: .color(style.bearing), lineWidth: 5)
    }
}
