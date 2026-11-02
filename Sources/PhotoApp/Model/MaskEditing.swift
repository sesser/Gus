import AppKit
import PhotoCore

/// The shapes a mask can be made of, as the Masks heading offers them.
enum MaskShapeKind: String, CaseIterable {
    case linear, radial, brush, luminanceRange, colorRange

    var title: String {
        switch self {
        case .linear: String(localized: "Linear Gradient", comment: "Mask shape")
        case .radial: String(localized: "Radial Gradient", comment: "Mask shape")
        case .brush: String(localized: "Brush", comment: "Mask shape")
        case .luminanceRange: String(localized: "Luminance Range", comment: "Mask shape")
        case .colorRange: String(localized: "Color Range", comment: "Mask shape")
        }
    }

    var symbol: String {
        switch self {
        case .linear: "rectangle.tophalf.filled"
        case .radial: "circle.dashed"
        case .brush: "paintbrush.pointed"
        case .luminanceRange: "sun.max"
        case .colorRange: "eyedropper"
        }
    }

    init(_ shape: MaskShape) {
        switch shape {
        case .linear: self = .linear
        case .radial: self = .radial
        case .brush: self = .brush
        case .luminanceRange: self = .luminanceRange
        case .colorRange: self = .colorRange
        }
    }
}

extension MaskShape {
    var brushComponent: Bool { if case .brush = self { true } else { false } }
}

extension AdjustmentEditor {
    var selectedMask: Mask? {
        guard let selectedMaskID else { return nil }
        return adjustments.local.masks.first { $0.id == selectedMaskID }
    }

    // MARK: Frames

    /// The crop the output frame is cut with: the stack's, or the camera's
    /// frame of a RAW file decoded whole for its masks.
    var maskCrop: Crop {
        let crop = adjustments.crop
        if crop.isIdentity, let cameraRect { return Crop(rect: cameraRect) }
        return crop
    }

    /// The mask frame's size in pixels. Before a RAW file with a camera crop
    /// has a mask, its frames are the camera's frame: scaled up to the sensor.
    var maskSourceSize: CGSize? {
        guard let size = maskFrameSize else { return nil }
        if let cameraRect, adjustments.crop.isIdentity, frame?.adjustments.local.renderedMasks.isEmpty ?? true {
            return CGSize(width: size.width / cameraRect.width, height: size.height / cameraRect.height)
        }
        return size
    }

    /// A point of the output (unit coordinates, y down) in the mask frame.
    func maskPoint(fromOutput point: CGPoint) -> MaskPoint? {
        guard let size = maskSourceSize else { return nil }
        let mapped = CropGeometry.outputToMask(point, crop: maskCrop, sourceSize: size)
        return MaskPoint(x: mapped.x, y: mapped.y)
    }

    func outputPoint(fromMask point: MaskPoint) -> CGPoint? {
        guard let size = maskSourceSize else { return nil }
        return CropGeometry.maskToOutput(CGPoint(x: point.x, y: point.y), crop: maskCrop, sourceSize: size)
    }

    // MARK: Changing masks

    /// Changes the masks as one undo step (or a live frame while `phase` is
    /// changing), unless the result would pass `MaskLimits`.
    @discardableResult
    func changeMasks(_ actionName: String, phase: EditPhase, _ body: (inout LocalAdjustments) -> Void) -> Bool {
        guard state == .ready else { return false }
        var next = adjustments.local
        body(&next)
        guard MaskLimits.allows(next) else {
            library?.statusMessage = String(localized: "That would pass the limit on masks, components or brush points.")
            return false
        }
        change(actionName, phase: phase) { $0.local = next }
        return true
    }

    /// Changes the selected mask.
    func changeSelectedMask(_ actionName: String, phase: EditPhase, _ body: (inout Mask) -> Void) {
        guard let selectedMaskID else { return }
        changeMasks(actionName, phase: phase) { local in
            guard let index = local.masks.firstIndex(where: { $0.id == selectedMaskID }) else { return }
            body(&local.masks[index])
        }
    }

    /// A new mask of `kind`, selected; gradients start in the middle of what the loupe shows.
    func addMask(_ kind: MaskShapeKind) {
        guard let component = newComponent(kind, operation: .add) else { return }
        let count = adjustments.local.masks.count
        var values = LocalValues()
        values.exposure = kind == .linear ? -0.5 : 0.3
        let mask = Mask(name: String(localized: "Mask \(count + 1)", comment: "A new mask's name"),
                        components: [component], adjustments: values)
        if changeMasks(String(localized: "Add Mask"), phase: .committed, { $0.masks.append(mask) }) {
            selectedMaskID = mask.id
            isBrushing = kind == .brush
            isSamplingColor = kind == .colorRange
        }
    }

    /// Adds a component of `kind` to the selected mask.
    func addComponent(_ kind: MaskShapeKind, operation: MaskOperation) {
        guard let component = newComponent(kind, operation: operation) else { return }
        changeSelectedMask(String(localized: "Add to Mask"), phase: .committed) { $0.components.append(component) }
        isBrushing = kind == .brush
        isSamplingColor = kind == .colorRange
    }

    private func newComponent(_ kind: MaskShapeKind, operation: MaskOperation) -> MaskComponent? {
        func point(_ x: Double, _ y: Double) -> MaskPoint? { maskPoint(fromOutput: CGPoint(x: x, y: y)) }
        let shape: MaskShape
        switch kind {
        case .linear:
            guard let start = point(0.5, 0.15), let end = point(0.5, 0.55) else { return nil }
            shape = .linear(LinearGradient(start: start, end: end))
        case .radial:
            guard let center = point(0.5, 0.5) else { return nil }
            shape = .radial(RadialGradient(center: center, radiusX: 0.2, radiusY: 0.14,
                                           rotation: -CropGeometry.outputRotation(0, crop: maskCrop)))
        case .brush: shape = .brush(Brush())
        case .luminanceRange: shape = .luminanceRange(LuminanceRange())
        case .colorRange: shape = .colorRange(ColorRange())
        }
        return MaskComponent(shape, operation: operation)
    }

    func removeMask(_ id: UUID) {
        changeMasks(String(localized: "Delete Mask"), phase: .committed) { $0.masks.removeAll { $0.id == id } }
        if selectedMaskID == id { selectedMaskID = adjustments.local.masks.last?.id }
    }

    /// Moves a mask `offset` places in the list (masks apply in list order).
    func moveMask(_ id: UUID, by offset: Int) {
        changeMasks(String(localized: "Move Mask"), phase: .committed) { local in
            guard let index = local.masks.firstIndex(where: { $0.id == id }) else { return }
            let target = min(max(index + offset, 0), local.masks.count - 1)
            local.masks.insert(local.masks.remove(at: index), at: target)
        }
    }

    func renameMask(_ id: UUID, to name: String) {
        changeMasks(String(localized: "Rename Mask"), phase: .committed) { local in
            if let index = local.masks.firstIndex(where: { $0.id == id }) { local.masks[index].name = name }
        }
    }

    func setMaskEnabled(_ id: UUID, _ isEnabled: Bool) {
        changeMasks(isEnabled ? String(localized: "Turn On Mask") : String(localized: "Turn Off Mask"),
                    phase: .committed) { local in
            if let index = local.masks.firstIndex(where: { $0.id == id }) { local.masks[index].isEnabled = isEnabled }
        }
    }

    func setLocal(_ keyPath: WritableKeyPath<LocalValues, Double>, _ value: Double, phase: EditPhase) {
        changeSelectedMask(String(localized: "Local Adjustment"), phase: phase) { $0.adjustments[keyPath: keyPath] = value }
    }

    func setMaskAmount(_ value: Double, phase: EditPhase) {
        changeSelectedMask(String(localized: "Mask Amount"), phase: phase) { $0.amount = value }
    }

    func setComponent(_ index: Int, _ actionName: String, phase: EditPhase, _ body: (inout MaskComponent) -> Void) {
        changeSelectedMask(actionName, phase: phase) { mask in
            guard mask.components.indices.contains(index) else { return }
            body(&mask.components[index])
        }
    }

    func removeComponent(_ index: Int) {
        changeSelectedMask(String(localized: "Remove from Mask"), phase: .committed) { mask in
            if mask.components.indices.contains(index) { mask.components.remove(at: index) }
        }
    }

    // MARK: Brush

    /// Starts a stroke at `point` (output unit coordinates) in the selected
    /// mask's last brush component, adding one when it has none.
    func beginStroke(at point: CGPoint) {
        guard let mask = selectedMask, let start = maskPoint(fromOutput: point) else { return }
        var component = mask.components.lastIndex { $0.shape.brushComponent }
        if component == nil {
            changeSelectedMask(String(localized: "Brush Stroke"), phase: .changing) {
                $0.components.append(MaskComponent(.brush(Brush())))
            }
            component = selectedMask.map { $0.components.count - 1 }
        }
        guard let component else { return }
        var stroke = brushTemplate
        stroke.points = [start]
        var strokeIndex = 0
        changeSelectedMask(String(localized: "Brush Stroke"), phase: .changing) { mask in
            guard case .brush(var brush) = mask.components[component].shape else { return }
            brush.strokes.append(stroke)
            strokeIndex = brush.strokes.count - 1
            mask.components[component].shape = .brush(brush)
        }
        paintingStroke = (mask.id, component, strokeIndex)
    }

    /// Adds a sample to the stroke being painted (thinned to a tenth of the radius).
    func continueStroke(to point: CGPoint, finished: Bool = false) {
        guard let painting = paintingStroke, painting.mask == selectedMaskID, let next = maskPoint(fromOutput: point),
              let size = maskSourceSize else { return }
        let aspect = Double(size.width / max(size.height, 1))
        var changed = false
        var updated: Brush?
        if let mask = selectedMask, mask.components.indices.contains(painting.component),
           case .brush(var brush) = mask.components[painting.component].shape,
           brush.strokes.indices.contains(painting.stroke) {
            if finished {
                brush.strokes[painting.stroke].finish(next)
                changed = true
            } else {
                changed = brush.strokes[painting.stroke].record(next, aspect: aspect)
            }
            updated = brush
        }
        if finished { paintingStroke = nil }
        guard let updated, changed || finished else { return }
        changeSelectedMask(String(localized: "Brush Stroke"), phase: finished ? .committed : .changing) {
            $0.components[painting.component].shape = .brush(updated)
        }
    }

    // MARK: Color

    /// Adds the color under `point` (output unit coordinates) of the frame on
    /// screen to the selected mask's last color range, in OkLab.
    func sampleColor(at point: CGPoint) {
        guard let image = frame?.image.cgImage, let mask = selectedMask,
              let component = mask.components.lastIndex(where: { if case .colorRange = $0.shape { true } else { false } }),
              let color = Self.linearRec2020(of: image, at: point) else { return }
        let sample = ColorRange.okLab(linearRec2020: color)
        setComponent(component, String(localized: "Sample Color"), phase: .committed) { component in
            guard case .colorRange(var range) = component.shape else { return }
            range.samples.append(sample)
            component.shape = .colorRange(range)
        }
    }

    /// The pixel of `image` at `point` (unit coordinates, y down) in linear Rec. 2020.
    static func linearRec2020(of image: CGImage, at point: CGPoint) -> SIMD3<Double>? {
        let x = min(max(Int(point.x * CGFloat(image.width)), 0), image.width - 1)
        let y = min(max(Int(point.y * CGFloat(image.height)), 0), image.height - 1)
        guard let space = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020),
              let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
        var values = [Float](repeating: 0, count: 4)
        let drawn = values.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 32,
                                          bytesPerRow: 16, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                              | CGBitmapInfo.floatComponents.rawValue
                                              | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return false }
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        return SIMD3(Double(values[0]), Double(values[1]), Double(values[2]))
    }
}
