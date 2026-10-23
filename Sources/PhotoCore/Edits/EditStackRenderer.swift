import CoreImage

/// Applies an edit stack to a decoded master.
///
/// Input and output are in the pipeline's linear working space; conversion to the
/// output color space happens after rendering. Implementations must be cheap to
/// call: they build a lazy Core Image graph, they do not render.
public protocol EditStackRenderer: Sendable {
    func apply(_ stack: EditStack, to image: CIImage) throws -> CIImage
}

/// Phase 1 renderer: returns the input untouched regardless of the stack.
public struct PassThroughRenderer: EditStackRenderer {
    public init() {}

    public func apply(_ stack: EditStack, to image: CIImage) throws -> CIImage {
        image
    }
}
