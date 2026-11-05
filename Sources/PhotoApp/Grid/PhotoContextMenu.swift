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
        return menu
    }

    /// For the photo in the loupe: the grid's items, then zoom, original and crop.
    static func loupe(model: LibraryModel) -> NSMenu {
        let state = LibraryMenuState(model)
        let menu = NSMenu()
        addPhotoItems(to: menu, model: model, state: state)
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
        return menu
    }

    private static func stepZoom(_ model: LibraryModel, in zoomIn: Bool) {
        NotificationCenter.default.post(name: .loupeShouldStepZoom, object: model,
                                        userInfo: [LoupeZoomStep.zoomInKey: zoomIn])
    }

    /// Culling, keywords, albums, adjustments, export and the RAW+JPEG pair.
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
        menu.addItem(ActionMenuItem(String(localized: "Suggest Keywords")) {
            model.suggestKeywords(for: model.actionTargetVersionIDs)
            model.showsInspector = true
        })
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
            menu.addItem(ActionMenuItem(String(localized: "Reset All Adjustments")) { model.resetAllAdjustments() })
        }
        if state.mode == .grid ? state.targetsIncludePhoto : state.canEditLoupePhoto {
            menu.addItem(ActionMenuItem(String(localized: "Rotate Left")) { model.rotate(clockwise: false) })
            menu.addItem(ActionMenuItem(String(localized: "Rotate Right")) { model.rotate(clockwise: true) })
        }
        let showsPair = state.groupPairs && model.focusedItem?.representsPair == true
        if state.canExport || showsPair {
            menu.addItem(.separator())
        }
        if state.canExport {
            menu.addItem(ActionMenuItem(String(localized: "Export…")) { model.export.begin() })
        }
        if showsPair {
            menu.addItem(submenu(String(localized: "RAW+JPEG Pair"), [
                ActionMenuItem(String(localized: "Show the RAW File")) { model.showPairFile(raw: true) },
                ActionMenuItem(String(localized: "Show the JPEG or HEIC File")) { model.showPairFile(raw: false) },
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
