//
//  TempOffToolbarViewModel.swift
//  XKey
//
//  ViewModel for the temp off toolbar
//

import Foundation
import Combine

class TempOffToolbarViewModel: ObservableObject {
    // MARK: - Published Properties

    /// Whether spelling is temporarily off
    @Published var isSpellingTempOff: Bool = false

    /// Whether engine is temporarily off
    @Published var isEngineTempOff: Bool = false

    /// Whether to show the spelling button
    @Published var showSpellingButton: Bool = true

    /// Whether to show the engine button
    @Published var showEngineButton: Bool = true

    // MARK: - Callbacks

    /// Called when spelling temp off state changes
    var onSpellingToggle: ((Bool) -> Void)?

    /// Called when engine temp off state changes
    var onEngineToggle: ((Bool) -> Void)?

    // MARK: - Actions

    func toggleSpelling() {
        objectWillChange.send()
        isSpellingTempOff.toggle()
        onSpellingToggle?(isSpellingTempOff)
    }

    func toggleEngine() {
        objectWillChange.send()
        isEngineTempOff.toggle()
        onEngineToggle?(isEngineTempOff)
    }

    // MARK: - Configuration

    /// Update which buttons to show based on settings
    func updateVisibility(showSpelling: Bool, showEngine: Bool) {
        showSpellingButton = showSpelling
        showEngineButton = showEngine
    }

    /// Update temp off states (called from external source)
    func updateStates(spellingTempOff: Bool, engineTempOff: Bool) {
        isSpellingTempOff = spellingTempOff
        isEngineTempOff = engineTempOff
    }
}
