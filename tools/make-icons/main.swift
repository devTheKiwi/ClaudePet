import Cocoa

// 앱 아이콘과 메뉴바 아이콘 그림을 만드는 도구 (앱 빌드에는 들어가지 않는다).
// PetView.draw 를 그대로 불러 기본형 펫(기본 스킨·기본 색, 장식·뱃지 없음)을 뽑아 쓰므로
// 펫 그림이 바뀌면 다시 돌리기만 하면 된다.
//
// 빌드·실행 (저장소 루트에서):
//   swiftc -O $(ls Sources/ClaudePet/*.swift | grep -v /main.swift) tools/make-icons/main.swift -o /tmp/make-icons
//   /tmp/make-icons /tmp/icons
// 나오는 것: icon-<시안>-1024.png (앱 아이콘 시안 A·B·C), menubar-<시안>-18[@2x].png (메뉴바 시안 M1·M2·M3),
//           preview.png · preview-menubar.png (비교용)
// Resources/ 에 든 것은 C(크림)와 M1(단색)이다.
//
// 1024 PNG → .icns:
//   mkdir AppIcon.iconset
//   for s in 16 32 128 256 512; do
//     sips -z $s $s icon.png --out AppIcon.iconset/icon_${s}x${s}.png
//     sips -z $((s*2)) $((s*2)) icon.png --out AppIcon.iconset/icon_${s}x${s}@2x.png
//   done
//   iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
_ = NSApplication.shared

func bitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep {
    return NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}

func draw(into rep: NSBitmapImageRep, _ body: (CGContext) -> Void) {
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    body(ctx.cgContext)
    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
}

func save(_ rep: NSBitmapImageRep, _ name: String) {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

// 1) 펫: 기본 스킨·기본 색(palette[0])·코드 모드·작업 표시 없음·뱃지 없음, 첫 프레임(흔들림 0)
let petSize = NSSize(width: 96, height: 64)
let scale: CGFloat = 24
let view = PetView(frame: NSRect(origin: .zero, size: petSize), color: PetColor.palette[0])
view.skin = .basic
view.petMode = .code
view.claudeStatus = .notRunning
view.workingSeconds = 0
view.showTimer = false

let petRep = bitmap(Int(petSize.width * scale), Int(petSize.height * scale))
draw(into: petRep) { cg in
    cg.scaleBy(x: scale, y: scale)
    view.draw(view.bounds)
}

// 그려진 부분만 잘라 낸다
var minX = petRep.pixelsWide, minY = petRep.pixelsHigh, maxX = -1, maxY = -1
let data = petRep.bitmapData!
for y in 0..<petRep.pixelsHigh {
    for x in 0..<petRep.pixelsWide where data[y * petRep.bytesPerRow + x * 4 + 3] > 0 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    }
}
let crop = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
let pet = petRep.cgImage!.cropping(to: crop)!
print("pet bbox (pt):", crop.width / scale, "x", crop.height / scale)
let petOnly = NSBitmapImageRep(cgImage: pet)
save(petOnly, "pet-basic.png")

// 2) 아이콘: 1024 캔버스, 824 둥근 사각 바탕(모서리 185.4), 아래로 떨어지는 그림자
struct Variant { let name: String; let top: NSColor; let bottom: NSColor; let petWidth: CGFloat; let shadow: Bool }
func rgb(_ hex: Int) -> NSColor {
    return NSColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                   blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
let variants = [
    Variant(name: "A-navy",       top: rgb(0x1A1A2E), bottom: rgb(0x1A1A2E), petWidth: 0.50, shadow: false),
    Variant(name: "B-navy-large", top: rgb(0x1A1A2E), bottom: rgb(0x1A1A2E), petWidth: 0.64, shadow: false),
    Variant(name: "C-cream",      top: rgb(0xFBF3E7), bottom: rgb(0xF1E2CF), petWidth: 0.58, shadow: true),
]

func icon(_ v: Variant) -> NSBitmapImageRep {
    let rep = bitmap(1024, 1024)
    draw(into: rep) { cg in
        let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
        let path = CGPath(roundedRect: plate, cornerWidth: 185.4, cornerHeight: 185.4, transform: nil)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -12), blur: 28,
                     color: NSColor.black.withAlphaComponent(0.30).cgColor)
        cg.addPath(path); cg.setFillColor(v.bottom.cgColor); cg.fillPath()
        cg.restoreGState()
        cg.saveGState()
        cg.addPath(path); cg.clip()
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [v.top.cgColor, v.bottom.cgColor] as CFArray, locations: [0, 1])!
        cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: plate.maxY), end: CGPoint(x: 0, y: plate.minY), options: [])
        cg.restoreGState()

        let w = plate.width * v.petWidth
        let h = w * CGFloat(pet.height) / CGFloat(pet.width)
        let rect = CGRect(x: plate.midX - w / 2, y: plate.midY - h / 2, width: w, height: h)
        if v.shadow {   // 밝은 바탕에서는 바닥 그림자를 옅게 깐다 (펫 그림 자체는 건드리지 않는다)
            cg.setFillColor(NSColor.black.withAlphaComponent(0.10).cgColor)
            cg.fillEllipse(in: CGRect(x: rect.midX - w * 0.36, y: rect.minY - h * 0.045, width: w * 0.72, height: h * 0.09))
        }
        cg.interpolationQuality = .high
        cg.draw(pet, in: rect)
    }
    return rep
}

var icons: [(Variant, NSBitmapImageRep)] = []
for v in variants {
    let rep = icon(v)
    save(rep, "icon-\(v.name)-1024.png")
    icons.append((v, rep))
}

// 3) 비교용 미리보기 한 장: 위는 밝은 바탕, 아래는 어두운 바탕. 큰 크기와 64·32·16.
let colW = 420, rowH = 400
let preview = bitmap(colW * icons.count, rowH * 2)
draw(into: preview) { cg in
    for (row, bg) in [rgb(0x2B2B2F), rgb(0xECECEC)].enumerated() {   // row 0 = 아래
        cg.setFillColor(bg.cgColor)
        cg.fill(CGRect(x: 0, y: row * rowH, width: preview.pixelsWide, height: rowH))
        let textColor = row == 0 ? NSColor.white : NSColor.black
        for (i, item) in icons.enumerated() {
            let img = item.1.cgImage!
            let x0 = CGFloat(i * colW), y0 = CGFloat(row * rowH)
            cg.interpolationQuality = .high
            cg.draw(img, in: CGRect(x: x0 + 30, y: y0 + 110, width: 256, height: 256))
            var sy = y0 + 110
            for s in [64, 32, 16] as [CGFloat] {
                cg.draw(img, in: CGRect(x: x0 + 310, y: sy, width: s, height: s))
                sy += s + 18
            }
            let label = NSAttributedString(string: item.0.name, attributes: [
                .font: NSFont.boldSystemFont(ofSize: 22), .foregroundColor: textColor])
            label.draw(at: NSPoint(x: x0 + 30, y: y0 + 50))
        }
    }
}
save(preview, "preview.png")

// 4) 메뉴바용 단색 템플릿: 뽑아 낸 펫 그림의 픽셀에서 만든다 (다시 그리지 않는다).
//    검정 + 알파만 쓰는 템플릿 이미지라 밝은·어두운 메뉴바에 시스템이 알아서 색을 입힌다.
enum EyeStyle { case none, holes, holesWithPupils }
func template(_ style: EyeStyle) -> CGImage {
    let src = NSBitmapImageRep(cgImage: pet)
    let w = src.pixelsWide, h = src.pixelsHigh
    let out = bitmap(w, h)
    let sp = src.bitmapData!, dp = out.bitmapData!
    let spp = src.samplesPerPixel
    for y in 0..<h {
        for x in 0..<w {
            let i = y * src.bytesPerRow + x * spp
            let a = CGFloat(sp[i + 3]) / 255
            var alpha = a
            if a > 0 {
                let r = CGFloat(sp[i]) / 255 / a, g = CGFloat(sp[i + 1]) / 255 / a, b = CGFloat(sp[i + 2]) / 255 / a
                let lum = (r + g + b) / 3
                let gray = abs(r - g) < 0.08 && abs(g - b) < 0.08   // 눈 흰자·동공은 무채색, 몸은 주황
                if gray && style != .none {
                    // 흰자(밝음)는 뚫고, 동공(어두움)은 holesWithPupils 일 때만 채운다
                    let white = min(1, max(0, (lum - 0.15) / 0.7))
                    alpha = style == .holes ? 0 : a * (1 - white)
                }
            }
            let o = y * out.bytesPerRow + x * 4
            dp[o] = 0; dp[o + 1] = 0; dp[o + 2] = 0; dp[o + 3] = UInt8(alpha * 255)
        }
    }
    return out.cgImage!
}

func scaled(_ img: CGImage, height: Int) -> NSBitmapImageRep {
    let width = Int((CGFloat(height) * CGFloat(img.width) / CGFloat(img.height)).rounded())
    let rep = bitmap(width, height)
    draw(into: rep) { cg in
        cg.interpolationQuality = .high
        cg.draw(img, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return rep
}

let menus: [(String, CGImage)] = [
    ("M1-solid", template(.none)),
    ("M2-eye-holes", template(.holes)),
    ("M3-eyes", template(.holesWithPupils)),
]
for (name, img) in menus {
    for pt in [16, 18] {
        save(scaled(img, height: pt), "menubar-\(name)-\(pt).png")
        save(scaled(img, height: pt * 2), "menubar-\(name)-\(pt)@2x.png")
    }
}

// 메뉴바 미리보기: 밝은·어두운 메뉴바(높이 24pt)를 2배 화면 기준 실제 크기와 4배 확대로.
func tinted(_ img: CGImage, _ color: NSColor, height: Int) -> CGImage {
    let base = scaled(img, height: height)
    let rep = bitmap(base.pixelsWide, base.pixelsHigh)
    draw(into: rep) { cg in
        let r = CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh)
        cg.clip(to: r, mask: base.cgImage!)
        cg.setFillColor(color.cgColor); cg.fill(r)
    }
    return rep.cgImage!
}
let mbW = 900, mbRow = 330
let mb = bitmap(mbW, mbRow * 2)
draw(into: mb) { cg in
    let rows: [(NSColor, NSColor, NSColor)] = [
        (rgb(0x1E1E20), rgb(0x2C2C2E), .white),          // 아래: 어두운 메뉴바
        (rgb(0xF2F2F2), rgb(0xE4E4E6), rgb(0x1D1D1F)),   // 위: 밝은 메뉴바
    ]
    for (row, (pageBg, barBg, ink)) in rows.enumerated() {
        let y0 = CGFloat(row * mbRow)
        cg.setFillColor(pageBg.cgColor); cg.fill(CGRect(x: 0, y: y0, width: CGFloat(mbW), height: CGFloat(mbRow)))
        // 실제 크기 (2배 화면): 메뉴바 24pt = 48px, 아이콘 18pt = 36px
        cg.setFillColor(barBg.cgColor); cg.fill(CGRect(x: 0, y: y0 + 250, width: CGFloat(mbW), height: 48))
        // 4배 확대
        cg.setFillColor(barBg.cgColor); cg.fill(CGRect(x: 0, y: y0 + 30, width: CGFloat(mbW), height: 192))
        let emoji = NSAttributedString(string: "🐛", attributes: [.font: NSFont.systemFont(ofSize: 28)])
        emoji.draw(at: NSPoint(x: 60, y: y0 + 256))
        let emojiBig = NSAttributedString(string: "🐛", attributes: [.font: NSFont.systemFont(ofSize: 112)])
        emojiBig.draw(at: NSPoint(x: 30, y: y0 + 54))
        let lab0 = NSAttributedString(string: "지금 (🐛 글자)", attributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: ink])
        lab0.draw(at: NSPoint(x: 30, y: y0 + 6))
        for (i, item) in menus.enumerated() {
            let x = CGFloat(260 + i * 215)
            let small = tinted(item.1, ink, height: 36)
            cg.interpolationQuality = .high
            cg.draw(small, in: CGRect(x: x + 40, y: y0 + 256, width: CGFloat(small.width), height: 36))
            // 16pt 도 옆에
            let small16 = tinted(item.1, ink, height: 32)
            cg.draw(small16, in: CGRect(x: x + 100, y: y0 + 258, width: CGFloat(small16.width), height: 32))
            let big = tinted(item.1, ink, height: 144)
            cg.draw(big, in: CGRect(x: x + 20, y: y0 + 54, width: CGFloat(big.width), height: 144))
            let lab = NSAttributedString(string: item.0, attributes: [.font: NSFont.boldSystemFont(ofSize: 15), .foregroundColor: ink])
            lab.draw(at: NSPoint(x: x + 20, y: y0 + 6))
        }
    }
}
save(mb, "preview-menubar.png")
print("done")
