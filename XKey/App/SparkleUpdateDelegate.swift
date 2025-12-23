//
//  SparkleUpdateDelegate.swift
//  XKey
//
//  Delegate for Sparkle auto-update to handle pre-update settings backup
//

import Foundation
import Sparkle

/// Delegate class to handle Sparkle update lifecycle events
/// Primary purpose: Force save settings to plist before app restarts for update
class SparkleUpdateDelegate: NSObject, SPUUpdaterDelegate {
    
    // MARK: - Debug Logging Callback
    
    /// Callback for logging debug messages
    var debugLogCallback: ((String) -> Void)?
    
    // MARK: - SPUUpdaterDelegate
    
    /// Called immediately before installing the specified update
    /// We use this as an early trigger to ensure settings are saved
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        logDebug("🔄 Sparkle: Will install update v\(item.displayVersionString)")
        
        // Force save settings before update is installed
        forceWriteAllSettings()
    }
    
    /// Called immediately before the application relaunches
    /// This is our last chance to save settings before restart
    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        logDebug("🔄 Sparkle: Will relaunch application - force saving settings...")
        
        // Force save settings one more time before restart
        forceWriteAllSettings()
        
        logDebug("✅ Sparkle: Settings saved, ready to relaunch")
    }
    
    /// Returns whether the relaunch should be delayed to perform other tasks
    /// We don't need to delay, but we use this as another opportunity to save
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        logDebug("🔄 Sparkle: Preparing for relaunch after update to v\(item.displayVersionString)")
        
        // Save settings before proceeding
        forceWriteAllSettings()
        
        // Don't postpone - immediately call installHandler
        // We've already saved settings, so it's safe to proceed
        return false
    }
    
    // MARK: - Settings Backup
    
    /// Force write all current settings to the plist file
    /// This ensures settings are persisted before app restart
    private func forceWriteAllSettings() {
        logDebug("💾 Force writing all settings to plist...")
        
        // Get current settings and re-save them
        // This ensures the plist file is up-to-date with the current App Group container
        SharedSettings.shared.forceWriteCurrentSettings()
        
        logDebug("✅ Settings written to plist successfully")
    }
    
    // MARK: - Debug Logging
    
    private func logDebug(_ message: String) {
        debugLogCallback?(message)
        sharedLogInfo(message)
    }
}
