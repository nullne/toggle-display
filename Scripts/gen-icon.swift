#!/usr/bin/env swift
import AppKit

// Generate a clean, modern display-toggle icon
func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext
    let s = size  // shorthand

    // --- Background: rounded rect with subtle gradient ---
    let bgRect = CGRect(x: s * 0.04, y: s * 0.04, width: s * 0.92, height: s * 0.92)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    // Gradient: deep blue to darker blue
    let colors = [
        CGColor(red: 0.15, green: 0.45, blue: 0.95, alpha: 1.0),
        CGColor(red: 0.08, green: 0.25, blue: 0.70, alpha: 1.0)
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    ctx.resetClip()

    // --- Monitor body ---
    let monW = s * 0.58
    let monH = s * 0.40
    let monX = (s - monW) / 2
    let monY = s * 0.38

    // Monitor bezel (white, rounded)
    let bezelRect = CGRect(x: monX, y: monY, width: monW, height: monH)
    let bezelPath = CGPath(roundedRect: bezelRect, cornerWidth: s * 0.04, cornerHeight: s * 0.04, transform: nil)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.addPath(bezelPath)
    ctx.fillPath()

    // Screen (dark, inside the bezel)
    let screenInset = s * 0.03
    let screenRect = CGRect(
        x: monX + screenInset,
        y: monY + screenInset,
        width: monW - screenInset * 2,
        height: monH - screenInset * 2 - s * 0.01)
    let screenPath = CGPath(roundedRect: screenRect, cornerWidth: s * 0.02, cornerHeight: s * 0.02, transform: nil)
    ctx.setFillColor(CGColor(red: 0.05, green: 0.15, blue: 0.35, alpha: 1.0))
    ctx.addPath(screenPath)
    ctx.fillPath()

    // --- Stand ---
    let standW = s * 0.12
    let standH = s * 0.08
    let standX = (s - standW) / 2
    let standY = monY - standH
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
    ctx.fill(CGRect(x: standX, y: standY, width: standW, height: standH))

    // Base
    let baseW = s * 0.24
    let baseH = s * 0.025
    let baseX = (s - baseW) / 2
    let baseY = standY - baseH
    let basePath = CGPath(roundedRect: CGRect(x: baseX, y: baseY, width: baseW, height: baseH),
                          cornerWidth: s * 0.01, cornerHeight: s * 0.01, transform: nil)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
    ctx.addPath(basePath)
    ctx.fillPath()

    // --- Power symbol on screen ---
    let centerX = s / 2
    let centerY = monY + monH / 2 - s * 0.005
    let powerR = s * 0.09

    // Power circle (arc, open at top)
    ctx.setStrokeColor(CGColor(red: 0.3, green: 0.85, blue: 1.0, alpha: 1.0))
    ctx.setLineWidth(s * 0.025)
    ctx.setLineCap(.round)
    // Draw arc from ~60° to ~300° (open at top)
    ctx.addArc(center: CGPoint(x: centerX, y: centerY), radius: powerR,
               startAngle: .pi * 1.17, endAngle: .pi * -0.17, clockwise: true)
    ctx.strokePath()

    // Power line (vertical bar at top)
    ctx.move(to: CGPoint(x: centerX, y: centerY + powerR + s * 0.01))
    ctx.addLine(to: CGPoint(x: centerX, y: centerY + powerR * 0.35))
    ctx.strokePath()

    image.unlockFocus()
    return image
}

// Generate all required sizes for .iconset
let iconsetPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/DisplayToggle.iconset"

let fm = FileManager.default
try? fm.removeItem(atPath: iconsetPath)
try! fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes: [(String, CGFloat, CGFloat)] = [
    ("icon_16x16", 16, 1),
    ("icon_16x16@2x", 16, 2),
    ("icon_32x32", 32, 1),
    ("icon_32x32@2x", 32, 2),
    ("icon_128x128", 128, 1),
    ("icon_128x128@2x", 128, 2),
    ("icon_256x256", 256, 1),
    ("icon_256x256@2x", 256, 2),
    ("icon_512x512", 512, 1),
    ("icon_512x512@2x", 512, 2),
]

for (name, ptSize, scale) in sizes {
    let px = ptSize * scale
    let image = drawIcon(size: px)

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to generate \(name)")
    }

    let path = "\(iconsetPath)/\(name).png"
    try! png.write(to: URL(fileURLWithPath: path))
    print("  \(name).png  (\(Int(px))px)")
}

print("Done: \(iconsetPath)")
