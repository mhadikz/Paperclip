import Foundation

@MainActor
func registerViewModelTests(_ r: TestRunner) {
    func makeViewModel(_ world: TestWorld, confirm: Bool = true) -> (ClipboardViewModel, AppState) {
        let appState = AppState()
        let settings = AppSettings(defaults: TestDefaults.fresh())
        settings.confirmBeforeDeleting = true
        let vm = ClipboardViewModel(
            appState: appState,
            appRouter: AppRouter(),
            clipboard: world.clipboard,
            pinboards: world.pinboards,
            aiMemory: world.aiMemory,
            stack: world.stack,
            settings: settings,
            pasteClip: world.pasteClip,
            deleteClips: world.deleteClips,
            managePinboards: ManagePinboardUseCase(pinboards: world.pinboards),
            updateClip: UpdateClipUseCase(clipboard: world.clipboard),
            updateAIMemory: UpdateAIMemoryUseCase(aiMemory: world.aiMemory),
            confirmation: FakeConfirmation(answer: confirm)
        )
        return (vm, appState)
    }

    r.test("view model: visible clips follow search, type filter and pinboard") {
        let world = TestWorld()
        world.copyText("alpha docker note")
        world.copyText("https://example.com/docker")
        world.copyText("beta")
        let (vm, appState) = makeViewModel(world)
        try expectEqual(vm.visibleClips.count, 3)

        appState.searchText = "docker"
        try expectEqual(vm.visibleClips.count, 2)
        appState.searchText = "docker alpha"
        try expectEqual(vm.visibleClips.map(\.text), ["alpha docker note"], "all terms must match")
        appState.searchText = ""
        appState.filterType = .link
        try expectEqual(vm.visibleClips.map(\.contentType), [.link])
        appState.filterType = nil

        let board = world.pinboards.create(name: "Board", colorHex: "#FFC300")
        let beta = world.clipboard.clips[0]
        world.pinboards.pin(clipID: beta.id, to: board.id)
        appState.selectedPinboardID = board.id
        try expectEqual(vm.visibleClips.map(\.id), [beta.id])
        try expectEqual(vm.activePinboard?.id, board.id)
    }

    r.test("view model: menu list ignores search and honors display count") {
        let world = TestWorld()
        for i in 0..<30 { world.copyText("clip \(i)") }
        let (vm, appState) = makeViewModel(world)
        appState.searchText = "zzz"
        try expect(vm.visibleClips.isEmpty, "history filtered")
        try expectEqual(vm.displayedClips.count, 20, "menu unaffected, capped by displayCount")
    }

    r.test("view model: keyboard selection moves and clamps") {
        let world = TestWorld()
        world.copyText("one"); world.copyText("two"); world.copyText("three")
        let (vm, appState) = makeViewModel(world)
        vm.selectFirstIfNeeded()
        try expectEqual(appState.selectedClipID, vm.visibleClips[0].id)
        vm.moveSelection(by: 1)
        try expectEqual(appState.selectedClipID, vm.visibleClips[1].id)
        vm.moveSelection(by: 5)
        try expectEqual(appState.selectedClipID, vm.visibleClips[2].id, "clamped at end")
        vm.moveSelection(by: -10)
        try expectEqual(appState.selectedClipID, vm.visibleClips[0].id, "clamped at start")
        vm.togglePreview()
        try expectEqual(appState.previewClipID, vm.visibleClips[0].id)
        vm.togglePreview()
        try expect(appState.previewClipID == nil, "toggles off")
    }

    r.test("view model: delete selected asks for confirmation and keeps a sensible selection") {
        let world = TestWorld()
        world.copyText("one"); world.copyText("two"); world.copyText("three")
        let (vm, _) = makeViewModel(world, confirm: false)
        vm.selectFirstIfNeeded()
        vm.deleteSelected()
        try expectEqual(world.clipboard.clips.count, 3, "declined confirmation keeps the clip")

        let (vm2, appState2) = makeViewModel(world, confirm: true)
        appState2.selectedClipID = vm2.visibleClips[1].id
        vm2.deleteSelected()
        try expectEqual(world.clipboard.clips.map(\.text), ["three", "one"])
        try expectEqual(appState2.selectedClipID, world.clipboard.clips[1].id, "selection moves to the next row")
    }

    r.test("view model: copy/paste route through the use case") {
        let world = TestWorld()
        world.copyText("x")
        let (vm, _) = makeViewModel(world)
        let clip = world.clipboard.clips[0]
        vm.copyOnly(clip)
        try expect(world.paste.keystrokes.isEmpty, "copy only")
        vm.pasteFromMenu(clip)
        try expectEqual(world.paste.keystrokes.count, 1)
        try expectEqual(world.paste.accessibilityRequests, 0, "permission already granted → no prompt")
        vm.copyText("ai output")
        try expectEqual(world.paste.writes.last?.text, "ai output")
    }

    r.test("view model: pinboards and favorites") {
        let world = TestWorld()
        world.copyText("x")
        let (vm, appState) = makeViewModel(world)
        let clip = world.clipboard.clips[0]
        vm.createPinboard(name: "  Ideas ")
        try expectEqual(vm.pinboards.first?.name, "Ideas")
        try expectEqual(appState.selectedPinboardID, vm.pinboards.first?.id, "new board selected")
        let board = vm.pinboards[0]
        vm.togglePin(clip, on: board)
        try expect(vm.isPinned(clip), "pinned")
        try expectEqual(vm.pinboards(containing: clip).map(\.id), [board.id])
        vm.togglePin(clip, on: board)
        try expect(!vm.isPinned(clip), "unpinned")
        vm.toggleFavorite(clip)
        try expect(vm.isFavorite(clip), "favorite")
        vm.deletePinboard(board)
        try expect(appState.selectedPinboardID == nil, "selection cleared")
    }
}
