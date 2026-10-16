// Renders the Panespace app icon: three black glass panes in an i3 layout, with light leaking through the seams
// between them: violet above, blue below, pink to the right, white-hot where they meet. 1024×1024.
// Usage: swift scripts/make-icon.swift <out.png> [small]
// `small` is the variant for 16 and 32 px: wider seams and bolder edges, so it still reads at that size.
import AppKit
import CoreImage

let S = 1024
let W = CGFloat(S)
let args = Array(CommandLine.arguments.dropFirst())
let out = args.first ?? "AppIcon.png"
let small = args.dropFirst().first == "small"
func hex(_ s: String) -> CGColor {
    let v = UInt32(s, radix: 16)!
    return CGColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}
let seamTop = hex("A66BFF"), seamBottom = hex("3D8BFF"), seamRight = hex("FF5E8A")

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func context() -> CGContext {
    CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func gray(_ v: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: v, green: v, blue: v, alpha: a) }
func linear(_ ctx: CGContext, _ colors: [CGColor], _ locations: [CGFloat]? = nil, from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locations)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

/// Apple's continuous-corner rounded rect: flat sides, curvature that eases into each corner.
func continuous(_ rect: CGRect, _ r: CGFloat) -> CGPath {
    let k: [(CGFloat, CGFloat)] = [(1.52866483, 0), (1.08849323, 0), (0.86840689, 0), (0.63149399, 0.07491100),
                                   (0.37282392, 0.16905899), (0.16905899, 0.37282392), (0.07491100, 0.63149399),
                                   (0, 0.86840689), (0, 1.08849323), (0, 1.52866471)]
    let corners: [(CGPoint, CGVector, CGVector)] = [  // corner, incoming edge direction (reversed), outgoing edge
        (CGPoint(x: rect.minX, y: rect.maxY), CGVector(dx: 0, dy: -1), CGVector(dx: 1, dy: 0)),
        (CGPoint(x: rect.maxX, y: rect.maxY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1)),
        (CGPoint(x: rect.maxX, y: rect.minY), CGVector(dx: 0, dy: 1), CGVector(dx: -1, dy: 0)),
        (CGPoint(x: rect.minX, y: rect.minY), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: 1)),
    ]
    let p = CGMutablePath()
    for (i, (o, a, b)) in corners.enumerated() {
        func pt(_ c: (CGFloat, CGFloat)) -> CGPoint {
            CGPoint(x: o.x + a.dx * c.0 * r + b.dx * c.1 * r, y: o.y + a.dy * c.0 * r + b.dy * c.1 * r)
        }
        if i == 0 { p.move(to: pt(k[0])) } else { p.addLine(to: pt(k[0])) }
        p.addCurve(to: pt(k[3]), control1: pt(k[1]), control2: pt(k[2]))
        p.addCurve(to: pt(k[6]), control1: pt(k[4]), control2: pt(k[5]))
        p.addCurve(to: pt(k[9]), control1: pt(k[7]), control2: pt(k[8]))
    }
    p.closeSubpath()
    return p
}

// ── Geometry (y up). Body on Apple's 824 pt icon grid. ─────────────────────
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = continuous(body, 148)
let area = body.insetBy(dx: small ? 120 : 148, dy: small ? 120 : 148)
let gap: CGFloat = small ? 54 : 28
let radius: CGFloat = small ? 56 : 46
let leftW = ((area.width - gap) * 0.56).rounded()
let master = CGRect(x: area.minX, y: area.minY, width: leftW, height: area.height)
let rightX = master.maxX + gap
let halfH = ((area.height - gap) / 2).rounded()
let top = CGRect(x: rightX, y: area.maxY - halfH, width: area.maxX - rightX, height: halfH)
let bottom = CGRect(x: rightX, y: area.minY, width: area.maxX - rightX, height: halfH)
let panes = [master, top, bottom]
let junction = CGPoint(x: master.maxX + gap / 2, y: bottom.maxY + gap / 2)

// ── Base: shadow, black body, black glass panes ───────────────────────────
let base = context()
base.saveGState()
base.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: gray(0, 0.55))
base.addPath(bodyPath); base.setFillColor(gray(0.02)); base.fillPath()
base.restoreGState()

base.saveGState()
base.addPath(bodyPath); base.clip()
linear(base, [gray(0.10), gray(0.035), gray(0.008)], [0, 0.45, 1],
       from: CGPoint(x: 0, y: body.maxY), to: CGPoint(x: 0, y: body.minY))
base.restoreGState()

for r in panes {
    let p = continuous(r, radius)
    // Recessed slab: a dark drop, then a near-black face that lifts toward the top.
    base.saveGState()
    base.setShadow(offset: CGSize(width: 0, height: -5), blur: 16, color: gray(0, 0.85))
    base.addPath(p); base.setFillColor(gray(0.03)); base.fillPath()
    base.restoreGState()
    base.saveGState()
    base.addPath(p); base.clip()
    linear(base, [gray(0.105), gray(0.045), gray(0.022)], [0, 0.5, 1],
           from: CGPoint(x: r.minX, y: r.maxY), to: CGPoint(x: r.minX, y: r.minY))
    // A soft diagonal sheen across the glass.
    linear(base, [gray(1, 0), gray(1, 0.045), gray(1, 0)], [0.35, 0.5, 0.65],
           from: CGPoint(x: r.minX, y: r.maxY), to: CGPoint(x: r.maxX, y: r.minY))
    base.restoreGState()
    // Hairline all round, so the layout reads even away from the light.
    base.saveGState()
    base.addPath(continuous(r.insetBy(dx: 1, dy: 1), radius - 1))
    base.setLineWidth(small ? 4 : 2)
    base.setStrokeColor(gray(1, 0.075))
    base.strokePath()
    base.restoreGState()
    // Lip: the top edge catches light; it fades out before the sides reach halfway.
    base.saveGState()
    base.addPath(continuous(r.insetBy(dx: 1.25, dy: 1.25), radius - 1.25))
    base.setLineWidth(small ? 5 : 2.5)
    base.replacePathWithStrokedPath()
    base.clip()
    linear(base, [gray(1, 0.34), gray(1, 0.07), gray(1, 0)], [0, 0.18, 0.55],
           from: CGPoint(x: r.minX, y: r.maxY), to: CGPoint(x: r.minX, y: r.minY))
    base.restoreGState()
}

// Body rim: a hairline catching light along the top.
base.saveGState()
base.addPath(continuous(body.insetBy(dx: 1.5, dy: 1.5), 146.5))
base.setLineWidth(3)
base.replacePathWithStrokedPath()
base.clip()
linear(base, [gray(1, 0.26), gray(1, 0.05), gray(1, 0.015)], [0, 0.3, 1],
       from: CGPoint(x: 0, y: body.maxY), to: CGPoint(x: 0, y: body.minY))
base.restoreGState()

// ── Light: colour along each seam, white at the junction, fading to the ends ──
let light = context()
let core: CGFloat = small ? 34 : 14
let vSeam = CGRect(x: junction.x - core / 2, y: area.minY, width: core, height: area.height)
let hSeam = CGRect(x: junction.x, y: junction.y - core / 2, width: area.maxX - junction.x, height: core)
let jt = (junction.y - area.minY) / area.height
light.saveGState()
light.clip(to: vSeam)
linear(light, [seamTop, gray(1), seamBottom], [0, 1 - jt, 1], from: CGPoint(x: 0, y: area.maxY), to: CGPoint(x: 0, y: area.minY))
light.restoreGState()
light.saveGState()
light.clip(to: hSeam)
linear(light, [gray(1), seamRight], [0, 0.85], from: CGPoint(x: junction.x, y: 0), to: CGPoint(x: area.maxX, y: 0))
light.restoreGState()
// Falloff from the junction.
light.setBlendMode(.destinationIn)
let reach: CGFloat = small ? 420 : 330
let falloff = CGGradient(colorsSpace: sRGB, colors: [gray(1), gray(1, 0.85), gray(1, 0.4), gray(1, 0.1), gray(1, 0)] as CFArray,
                         locations: [0, 0.12, 0.45, 0.8, 1])!
light.drawRadialGradient(falloff, startCenter: junction, startRadius: 0, endCenter: junction, endRadius: reach,
                         options: [.drawsAfterEndLocation])

let mask = context()
mask.addPath(bodyPath); mask.setFillColor(gray(1)); mask.fillPath()
// Pane edges: the light catches these in its own colour.
let edgeMask = context()
for r in panes { edgeMask.addPath(continuous(r.insetBy(dx: 1.5, dy: 1.5), radius - 1.5)) }
edgeMask.setLineWidth(small ? 7 : 3.5)
edgeMask.setStrokeColor(gray(1)); edgeMask.strokePath()
let paneMask = context()
for r in panes { paneMask.addPath(continuous(r, radius)) }
paneMask.setFillColor(gray(1)); paneMask.fillPath()

// ── Composite in linear light: white-hot core, coloured bloom, wide halo ──
let ci = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!])
let extent = CGRect(x: 0, y: 0, width: W, height: W)
let lightImage = CIImage(cgImage: light.makeImage()!)
func blur(_ img: CIImage, _ r: Double) -> CIImage {
    img.clampedToExtent().applyingGaussianBlur(sigma: r).cropped(to: extent)
}
func scaled(_ img: CIImage, _ k: CGFloat, white: CGFloat = 0) -> CIImage {
    // k = brightness; white mixes the colour toward white (0…1) for the hot core.
    let c = k * (1 - white), w = k * white
    return img.applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: c, y: 0, z: 0, w: w), "inputGVector": CIVector(x: 0, y: c, z: 0, w: w),
        "inputBVector": CIVector(x: 0, y: 0, z: c, w: w), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: k),
    ])
}
func add(_ a: CIImage, _ b: CIImage) -> CIImage { b.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: a]) }
func masked(_ img: CIImage, _ m: CGContext, invert: Bool = false) -> CIImage {
    var mi = CIImage(cgImage: m.makeImage()!)
    if invert { mi = mi.applyingFilter("CIColorInvert").applyingFilter("CIMaskToAlpha") }
    return img.applyingFilter("CIBlendWithMask", parameters: [
        kCIInputBackgroundImageKey: CIImage.empty().cropped(to: extent), kCIInputMaskImageKey: mi,
    ])
}

let s: Double = small ? 1.6 : 1
// The core sits in the gaps only: panes occlude it.
var glow = masked(scaled(blur(lightImage, 1.0 * s), 1.25, white: 0.85), paneMask, invert: true)
glow = add(glow, scaled(blur(lightImage, 6 * s), 1.2))      // tight glow, spills onto the glass edges
glow = add(glow, scaled(blur(lightImage, 24 * s), 0.8))     // bloom across the panes
glow = add(glow, scaled(blur(lightImage, 85 * s), 0.9))     // wide halo in the body
// Rim light: pane edges lit by the seam they face, fading with distance.
let rim = scaled(blur(lightImage, 55 * s), 9).applyingFilter("CIMultiplyCompositing", parameters: [
    kCIInputBackgroundImageKey: CIImage(cgImage: edgeMask.makeImage()!),
])
glow = add(glow, rim)
glow = masked(glow, mask)
let final = add(CIImage(cgImage: base.makeImage()!), glow).cropped(to: extent)
let cg = ci.createCGImage(final, from: extent, format: .RGBA8, colorSpace: sRGB)!
try! NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
