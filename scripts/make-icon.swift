#!/usr/bin/env swift
//
// Renders the app icon to a 1024×1024 PNG.
//
//     swift scripts/make-icon.swift App/Assets.xcassets/AppIcon.appiconset/icon-1024.png
//
// Drawn in code rather than committed as an opaque binary, so the icon is
// reproducible and reviewable like everything else here. CoreGraphics only —
// no image library, in keeping with the project's zero-dependency rule.
//
// The mark: a glasshouse seen head-on, its panes drawn as an open grid. Every
// pane is empty except one, which is lit. You are inside; something can see in;
// most of what is visible looks like nothing until one part of it is
// illuminated. That is the whole app in a shape.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024.0
let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon-1024.png"

guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(
          data: nil, width: Int(size), height: Int(size),
          bitsPerComponent: 8, bytesPerRow: 0, space: space,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
else { fatalError("could not create the drawing context") }

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r / 255, g / 255, b / 255, a])!
}

// A cool slate ground, matching the project's documents. Deliberately not pure
// black: a slight blue bias reads as chosen rather than inherited.
let top = rgb(31, 41, 55)
let bottom = rgb(11, 15, 20)
let glass = rgb(226, 232, 240)
let lit = rgb(217, 166, 72)

ctx.setFillColor(bottom)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

if let gradient = CGGradient(
    colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1]
) {
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0),
        options: []
    )
}

// MARK: - Geometry
//
// CoreGraphics has the origin at bottom-left, so the roof apex is the largest y.

let apex = CGPoint(x: 512, y: 812)
let eaveY = 520.0
let floorY = 232.0
let left = 196.0
let right = 828.0
let roofLeft = CGPoint(x: 164, y: eaveY)
let roofRight = CGPoint(x: 860, y: eaveY)

// The one lit pane: lower wall, left of centre. Off-centre on purpose — dead
// centre would read as a decorative motif rather than as one pane among many.
let litPane = CGRect(x: left, y: floorY, width: (right - left) / 3, height: (eaveY - floorY) / 2)
ctx.setFillColor(lit.copy(alpha: 0.92)!)
ctx.fill(litPane)

// A soft bloom, so the lit pane reads as illuminated rather than merely filled.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 90, color: lit.copy(alpha: 0.55))
ctx.setFillColor(lit.copy(alpha: 0.5)!)
ctx.fill(litPane.insetBy(dx: 18, dy: 18))
ctx.restoreGState()

// MARK: - Structure

ctx.setStrokeColor(glass)
ctx.setLineWidth(22)
ctx.setLineJoin(.round)
ctx.setLineCap(.round)

// Walls.
ctx.addRect(CGRect(x: left, y: floorY, width: right - left, height: eaveY - floorY))
ctx.strokePath()

// Roof.
ctx.move(to: roofLeft)
ctx.addLine(to: apex)
ctx.addLine(to: roofRight)
ctx.addLine(to: CGPoint(x: right, y: eaveY))
ctx.addLine(to: CGPoint(x: left, y: eaveY))
ctx.closePath()
ctx.strokePath()

// Mullions — the glazing bars that make it a glasshouse rather than a shed.
ctx.setLineWidth(15)

let thirds = (right - left) / 3
for i in 1...2 {
    let x = left + thirds * Double(i)
    ctx.move(to: CGPoint(x: x, y: floorY))
    ctx.addLine(to: CGPoint(x: x, y: eaveY))
}
let midWall = floorY + (eaveY - floorY) / 2
ctx.move(to: CGPoint(x: left, y: midWall))
ctx.addLine(to: CGPoint(x: right, y: midWall))

// Roof glazing: ribs from the apex down to the eaves.
ctx.move(to: apex)
ctx.addLine(to: CGPoint(x: 512, y: eaveY))
for fraction in [0.42, 0.72] {
    let lx = apex.x - (apex.x - roofLeft.x) * fraction
    let ly = apex.y - (apex.y - eaveY) * fraction
    ctx.move(to: CGPoint(x: lx, y: ly))
    ctx.addLine(to: CGPoint(x: lx, y: eaveY))

    let rx = apex.x + (roofRight.x - apex.x) * fraction
    ctx.move(to: CGPoint(x: rx, y: ly))
    ctx.addLine(to: CGPoint(x: rx, y: eaveY))
}
ctx.strokePath()

// MARK: - Write

guard let image = ctx.makeImage() else { fatalError("could not render") }
let url = URL(fileURLWithPath: output)
guard let destination = CGImageDestinationCreateWithURL(
    url as CFURL, UTType.png.identifier as CFString, 1, nil
) else { fatalError("could not open \(output) for writing") }

CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(output)") }

print("Wrote \(output) (\(Int(size))×\(Int(size)))")
