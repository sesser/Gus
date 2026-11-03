import AppKit

/// Square cells in rows that fill the available width.
///
/// Every frame is computed arithmetically from the item index, so layout costs
/// are proportional to what is on screen, not to the number of items. That is
/// what keeps 50k-item libraries as cheap as 50.
///
/// Shared by the library grid and the import grid (decision 18).
public final class UniformGridLayout: NSCollectionViewLayout {
    public override init() { super.init() }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("not used") }

    /// Requested cell edge in points; the actual edge stretches so rows fill the width.
    public var targetCellSize: CGFloat = 180 {
        didSet { if oldValue != targetCellSize { invalidateLayout() } }
    }
    public let spacing: CGFloat = 6
    public let inset: CGFloat = 10

    public private(set) var columns = 1
    public private(set) var cellSize: CGFloat = 180
    private var itemCount = 0
    private var width: CGFloat = 0

    private var stride: CGFloat { cellSize + spacing }

    public override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        itemCount = collectionView.numberOfSections > 0 ? collectionView.numberOfItems(inSection: 0) : 0
        width = collectionView.enclosingScrollView?.contentView.bounds.width ?? collectionView.bounds.width
        let available = max(width - inset * 2, 1)
        columns = max(1, Int((available + spacing) / (targetCellSize + spacing)))
        cellSize = floor((available - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    public var rowCount: Int { itemCount == 0 ? 0 : (itemCount + columns - 1) / columns }

    public override var collectionViewContentSize: NSSize {
        let rows = CGFloat(rowCount)
        let height = rows == 0 ? 0 : inset * 2 + rows * cellSize + (rows - 1) * spacing
        return NSSize(width: width, height: height)
    }

    public func frame(forItemAt index: Int) -> NSRect {
        let row = index / columns
        let column = index % columns
        return NSRect(x: inset + CGFloat(column) * stride, y: inset + CGFloat(row) * stride,
                      width: cellSize, height: cellSize)
    }

    /// Indices of items whose cells intersect `rect`.
    public func indices(in rect: NSRect) -> Range<Int> {
        guard itemCount > 0, rect.height > 0 else { return 0..<0 }
        let firstRow = max(0, Int(floor((rect.minY - inset) / stride)))
        let lastRow = min(rowCount - 1, Int(floor((rect.maxY - inset) / stride)))
        guard firstRow <= lastRow else { return 0..<0 }
        return (firstRow * columns)..<min(itemCount, (lastRow + 1) * columns)
    }

    public override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        indices(in: rect).map { index in
            let attributes = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: index, section: 0))
            attributes.frame = frame(forItemAt: index)
            return attributes
        }
    }

    public override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard indexPath.item < itemCount else { return nil }
        let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
        attributes.frame = frame(forItemAt: indexPath.item)
        return attributes
    }

    public override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        newBounds.width != width
    }
}
