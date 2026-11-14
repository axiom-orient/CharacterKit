import AppKit
import SwiftUI

/// Capture the native SDK views already displayed in this app. No character redraw,
/// screenshot fixture, alternate renderer or synthetic frame clock is introduced.
@MainActor
final class CharacterCaptureController: ObservableObject {
  weak var view: NSView?
  func save(to url: URL) throws {
    guard let view, let layer = view.layer else { throw CocoaError(.coderInvalidValue) }
    let width = Int(ceil(view.bounds.width)), height = Int(ceil(view.bounds.height))
    guard width > 0, height > 0, width <= 4096, height <= 4096,
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext
    else { throw CocoaError(.coderInvalidValue) }
    context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
    (layer.presentation() ?? layer).render(in: context)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try png.write(to: url, options: .atomic)
  }
}

struct CharacterCaptureSurface<Content: View>: NSViewRepresentable {
  let controller: CharacterCaptureController
  let content: Content
  func makeNSView(context: Context) -> NSHostingView<Content> {
    let view = NSHostingView(rootView: content)
    view.wantsLayer = true
    controller.view = view
    return view
  }
  func updateNSView(_ view: NSHostingView<Content>, context: Context) {
    // Content observes the host model itself; preserve its SwiftUI identity/clocks.
    controller.view = view
  }
}

/// Observe our own window's content view without moving the chat UI into a second
/// hosting tree. Scene, accessibility, focus and open-window environments stay native.
struct CharacterCaptureAnchor: NSViewRepresentable {
  let controller: CharacterCaptureController
  func makeNSView(context: Context) -> NSView {
    let view = CharacterCaptureAnchorView()
    view.controller = controller
    return view
  }
  func updateNSView(_ view: NSView, context: Context) { controller.view = view.window?.contentView }
}

private final class CharacterCaptureAnchorView: NSView {
  weak var controller: CharacterCaptureController?
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    controller?.view = window?.contentView
  }
}
