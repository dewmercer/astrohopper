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

    private func font(_ mm: Double, serif: Bool = false) -> Font {
        .system(size: (mm + Double(model.fontBoost)) * pointsPerMM, design: serif ? .serif : .default)
    }

    func draw(_ ctx: inout GraphicsContext) {
        let w = size.width, h = size.height
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        guard w > 0, h > 0 else { return }

        let cam = model.cameraRays()
        let camera = Mat3(r0: -cam.left, r1: cam.top, r2: cam.fwd)
        let toCamera = camera * model.equatorialToENU(date)
        let proj = Projection(fovDegrees: model.fov, width: w, height: h)
        let catalog = model.catalog
        let waitingForAlign = model.waitingForAlign
        let targetIndex = model.targetIndex, alignIndex = model.alignIndex
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
            let highlight = (i == targetIndex || i == alignIndex) ? 0 : 1
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
            plotBearing(toCamera * star.eq, proj: proj, ctx: &ctx)
            // a target fainter than the limit (found by search) is still selectable
            if let pos = plot(star, toCamera: toCamera, proj: proj, highlight: 3, ctx: &ctx),
               model.validAlignType(star.type), !targets.contains(where: { $0.index == ti }) {
                targets.append((pos.x, pos.y, ti))
            }
        } else if model.aligned {
            plotCross(ctx: &ctx)
        }
        plotLines(toCamera: toCamera, proj: proj, ctx: &ctx)
        plotAltAz(cam, ctx: &ctx)
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

    private func plotCross(ctx: inout GraphicsContext) {
        let cx = size.width / 2, cy = size.height / 2
        var path = Path()
        for (dx, dy) in [(1.0, 0.0), (0, 1), (-1, 0), (0, -1)] {
            path.move(to: CGPoint(x: cx + 10 * dx, y: cy + 10 * dy))
            path.addLine(to: CGPoint(x: cx + 50 * dx, y: cy + 50 * dy))
        }
        ctx.stroke(path, with: .color(style.cross), lineWidth: 3)
    }

    /// Port of `plotBearing()`: a line from the center toward the target plus
    /// the up/down and left/right angles still to move.
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

        let updn = (dy > 0 ? "Down" : "Up") + " " + String(format: "%.1f°", abs(atan2(-xyz.y, xyz.z) * rad2deg))
        let left = (dx > 0 ? "Right" : "Left") + " " + String(format: "%.1f°", abs(atan2(xyz.x, xyz.z) * rad2deg))
        let f = font(6, serif: true)
        ctx.draw(Text(updn).font(f).foregroundStyle(style.bearing), at: CGPoint(x: size.width - 5, y: cy), anchor: .trailing)
        ctx.draw(Text(left).font(f).foregroundStyle(style.bearing), at: CGPoint(x: cx, y: size.height - 5), anchor: .bottom)
    }

    private func plotAltAz(_ cam: CameraRays, ctx: inout GraphicsContext) {
        let (alt, az) = cam.altAz
        let f = font(5)
        ctx.draw(Text("Alt:" + String(format: "%.1f", alt)).font(f).foregroundStyle(style.altaz),
                 at: CGPoint(x: size.width - 5, y: size.height - 5), anchor: .bottomTrailing)
        ctx.draw(Text("Az:" + String(format: "%.1f", az)).font(f).foregroundStyle(style.altaz),
                 at: CGPoint(x: 5, y: size.height - 5), anchor: .bottomLeading)
    }
}
