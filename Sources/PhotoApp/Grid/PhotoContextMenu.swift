import AppKit
import PhotoCore
import PhotoUI

/// The context menus of the grid's photos and the loupe (section 7 of
/// docs/UI_REDESIGN.md). They run the menu bar's commands on what the menu
/// bar would act on; commands with nothing to act on are left out rather than
/// dimmed (HIG: Context menus).
@MainActor
enum PhotoContextMenu {
    /// For the grid's selection, after a right-click set it.
    static func grid(model: LibraryModel) -> NSMenu {
        let state = LibraryMenuState(model)
        let menu = NSMenu()
        menu.addItem(ActionMenuItem(String(localized: "Open in Loupe")) { model.openLoupe() })
        menu.addItem(.separator())
        addPhotoItems(to: menu, model: model, state: state)
        addRemoveItem(to: menu, model: model, state: state)
        return menu
    }

    /// For the photo in the loupe: the grid's items, then zoom, original and crop.
    static func loupe(model: LibraryModel) -> NSMenu {
        let state = LibraryMenuState(model)
        let menu = NSMenu()
        addPhotoItems(to: menu, model: model, state: state)
        // Last, whichever way the menu ends below.
        defer { addRemoveItem(to: menu, model: model, state: state) }
        guard state.showsLoupePhoto else { return menu }
        menu.addItem(.separator())
        let zoom = state.loupeZoom
        if zoom.canZoomIn { menu.addItem(ActionMenuItem(String(localized: "Zoom In")) { stepZoom(model, in: true) }) }
        if zoom.canZoomOut { menu.addItem(ActionMenuItem(String(localized: "Zoom Out")) { stepZoom(model, in: false) }) }
        menu.addItem(ActionMenuItem(zoom.isZoomed ? String(localized: "Zoom to Fit") : String(localized: "Zoom to 100%")) {
            NotificationCenter.default.post(name: .loupeShouldToggleZoom, object: model)
        })
        if state.canEditLoupePhoto && !state.isCropping {
            menu.addItem(ActionMenuItem(state.showsOriginal ? String(localized: "Show Adjustments")
                                                            : String(localized: "Show Original")) {
                model.editor.toggleOriginal()
            })
        }
        if state.canShowSharpeningMap {
            let titles = SharpeningMapText.menuTitle
            menu.addItem(ActionMenuItem(state.showsSharpeningMap ? titles.hide : titles.show) {
                model.toggleSharpeningMap(from: .menu)
            })
        }
        if state.canShowFringeMap {
            let titles = LensText.menuTitle
            menu.addItem(ActionMenuItem(state.showsFringeMap ? titles.hide : titles.show) {
                model.toggleFringeMap(from: .menu)
            })
        }
        if state.isPixelMagnifierActive {
            menu.addItem(submenu(PixelMagnifierText.menuTitle, PixelMagnifierLevel.allCases.map { level in
                let item = ActionMenuItem(PixelMagnifierText.title(level)) { model.setPixelMagnifierLevel(level) }
                item.state = level == state.pixelMagnifierLevel ? .on : .off
                return item
            }))
        }
        if state.canEditLoupePhoto {
            menu.addItem(ActionMenuItem(state.isCropping ? String(localized: "Finish Cropping") : String(localized: "Crop")) {
                model.crop()
            })
        }
        return menu
    }

    /// For the video in the loupe (design.md N9): the photo items that apply
    /// to a video (culling, keywords, albums), then Play / Pause and Show Grid.
    static func videoLoupe(model: LibraryModel) -> NSMenu {
        let state = LibraryMenuState(model)
        let menu = NSMenu()
        addPhotoItems(to: menu, model: model, state: state)
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(ActionMenuItem(state.isVideoPlaying ? String(localized: "Pause") : String(localized: "Play")) {
            model.playback.toggle()
        })
        menu.addItem(ActionMenuItem(String(localized: "Show Grid")) { model.closeLoupe() })
        addRemoveItem(to: menu, model: model, state: state)
        return menu
    }

    /// Remove from Library…: the last item of each photo menu, alone after a
    /// separator, away from the frequent items (library-ops design §2.2).
    /// Left out while an import keeps a removal from starting (§8).
    private static func addRemoveItem(to menu: NSMenu, model: LibraryModel, state: LibraryMenuState) {
        guard state.hasTargets, state.canRemoveFromLibrary else { return }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(ActionMenuItem(LibraryOpsText.removeFromLibraryMenu) { model.removeTargetsFromLibrary() })
    }

    private static func stepZoom(_ model: LibraryModel, in zoomIn: Bool) {
        NotificationCenter.default.post(name: .loupeShouldStepZoom, object: model,
                                        userInfo: [LoupeZoomStep.zoomInKey: zoomIn])
    }

    /// Culling, keywords, albums, adjustments, Duplicate, export, Show in Finder and the RAW+JPEG pair.
    private static func addPhotoItems(to menu: NSMenu, model: LibraryModel, state: LibraryMenuState) {
        guard state.hasTargets else { return }
        menu.addItem(submenu(String(localized: "Rating"), [
            ActionMenuItem(String(localized: "No Rating")) { model.perform(.setRating(.unrated)) },
        ] + (1...5).map { stars in
            ActionMenuItem(RatingText.stars(stars)) { model.perform(.setRating(Rating(clamping: stars))) }
        } + [
            .separator(),
            ActionMenuItem(String(localized: "Raise Rating")) { model.perform(.adjustRating(1)) },
            ActionMenuItem(String(localized: "Lower Rating")) { model.perform(.adjustRating(-1)) },
        ]))
        menu.addItem(submenu(String(localized: "Flag"), [
            ActionMenuItem(String(localized: "Pick")) { model.perform(.setFlag(.picked)) },
            ActionMenuItem(String(localized: "Reject")) { model.perform(.setFlag(.rejected)) },
            ActionMenuItem(String(localized: "Clear Flag")) { model.perform(.setFlag(.none)) },
        ]))
        menu.addItem(submenu(String(localized: "Color Label"), ColorLabel.allCases.map { label in
            ActionMenuItem(ColorLabelText.name(label)) { model.perform(.setColorLabel(label)) }
        }))
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(String(localized: "Add Keywords…")) { model.beginKeywordEntry() })
        menu.addItem(ActionMenuItem(String(localized: "Suggest Keywords")) { model.suggestKeywordsForTargets() })
        if !state.albums.isEmpty {
            menu.addItem(submenu(String(localized: "Add to Album"), state.albums.map { album in
                ActionMenuItem(album.album.name) { model.addToAlbum(album.id) }
            }))
        }
        if state.isInAlbum {
            menu.addItem(ActionMenuItem(String(localized: "Remove from Album")) { model.removeFromCurrentAlbum() })
        }
        let adjusts = state.mode == .grid ? state.targetsIncludePhoto : state.canEditLoupePhoto && !state.isCropping
        // Videos have no adjustments to copy.
        if state.focusedIsPhoto || adjusts {
            menu.addItem(.separator())
        }
        if state.focusedIsPhoto {
            menu.addItem(ActionMenuItem(String(localized: "Copy Adjustments")) { model.copyAdjustments() })
        }
        if state.hasCopiedAdjustments && state.targetsIncludePhoto {
            menu.addItem(ActionMenuItem(String(localized: "Paste Adjustments")) { model.pasteAdjustments() })
        }
        if !state.presetCollections.isEmpty && state.targetsIncludePhoto {
            menu.addItem(submenu(String(localized: "Apply Preset"), state.presetCollections.flatMap { collection in
                let items = collection.presets.map { preset in
                    ActionMenuItem(preset.name) { model.applyAdjustmentPreset(preset) } as NSMenuItem
                }
                return collection.name.isEmpty ? items : [submenu(collection.name, items)]
            }))
        }
        if adjusts {
            menu.addItem(ActionMenuItem(String(localized: "Auto Exposure")) { model.autoExposure() })
        }
        if state.canResetAll {
            menu.addItem(ActionMenuItem(String(localized: "Reset All Adjustments")) { model.resetAllAdjustments() })
        }
        if state.mode == .grid ? state.targetsIncludePhoto : state.canEditLoupePhoto {
            menu.addItem(ActionMenuItem(String(localized: "Rotate Left")) { model.rotate(clockwise: false) })
            menu.addItem(ActionMenuItem(String(localized: "Rotate Right")) { model.rotate(clockwise: true) })
        }
        let showsPair = state.pairDisplay != nil
        if state.canDuplicate || state.canExport || state.canShowTargetsInFinder || showsPair {
            menu.addItem(.separator())
        }
        // Left out for videos, which are not duplicated (virtual-copies design §2.2).
        if state.canDuplicate {
            menu.addItem(ActionMenuItem(DuplicateText.title) { model.duplicateTargets() })
        }
        if state.canExport {
            menu.addItem(ActionMenuItem(String(localized: "Export…")) { model.export.begin() })
        }
        // Left out when no target's original is online (library-ops design §5.1).
        if state.canShowTargetsInFinder {
            menu.addItem(ActionMenuItem(LibraryOpsText.showInFinder) { model.showTargetsInFinder() })
        }
        if let display = state.pairDisplay {
            func item(_ title: String, raw: Bool, _ shown: PairDisplay.State) -> NSMenuItem {
                let item = ActionMenuItem(title) { model.showPairFile(raw: raw) }
                item.state = switch shown {
                case .on: .on
                case .off: .off
                case .mixed: .mixed
                }
                return item
            }
            menu.addItem(submenu(String(localized: "RAW+JPEG Pair"), [
                item(String(localized: "Show the RAW File"), raw: true, display.raw),
                item(String(localized: "Show the JPEG or HEIC File"), raw: false, display.companion),
            ]))
        }
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        items.forEach(submenu.addItem)
        item.submenu = submenu
        return item
    }
}

/// A menu item that runs a closure.
final class ActionMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not used") }

    @MainActor @objc private func run() {
        handler()
    }
}
