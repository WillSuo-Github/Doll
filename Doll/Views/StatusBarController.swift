import AppKit
import Monitor
import SwiftUI

let defaultIconSize: CGFloat = 20
let defaultIcon = #imageLiteral(resourceName: "DefaultStatusBarIcon")

private final class NonActivatingNotificationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { false }
}

class StatusBarController {
    private var statusBar: NSStatusBar!
    private var isDark = false
    private var latestBadgeText = ""
    private var latestMessageCount = 0

    private var notificationPanel: NonActivatingNotificationPanel = {
        let panel = NonActivatingNotificationPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }()
    private var hideNotificationTimer: DispatchWorkItem?

    private var giantBadgeController = GiantBadgeViewController()
    private var giantBadgePanel = NSPanel(contentRect: NSRect(origin: .zero, size: defaultWindowSize),
                              styleMask: [.nonactivatingPanel],
                              backing: .buffered, defer: false)
    private var lastTimeShowingGiantBadge = Date()

    public var statusItem: NSStatusItem!
    public var monitoredApp: MonitoredApp? {
        didSet {
            refreshIcon()
        }
    }
    private var monitoredAppIcon: NSImage?

    init() {
        setupStatusBar()
    }

    func setupStatusBar(icon: NSImage? = nil) {
        statusBar = .system
        statusItem = statusBar.statusItem(withLength: defaultIconSize)
        if let statusBarButton = statusItem.button {
            statusBarButton.sendAction(on: [.leftMouseUp, .rightMouseUp])
            statusBarButton.image = icon ?? defaultIcon
            statusBarButton.image?.size = NSSize(width: defaultIconSize, height: defaultIconSize)
            statusBarButton.image?.isTemplate = false
            statusBarButton.imagePosition = .imageLeft
            statusBarButton.action = #selector(onIconClicked(sender:))
            statusBarButton.target = self
            statusBarButton.toolTip = NSLocalizedString("Hold option key ⌥ and click to config", comment: "")
        }

        giantBadgePanel.isOpaque = false
        giantBadgePanel.hasShadow = false
        giantBadgePanel.backgroundColor = NSColor.clear

        notificationPanel.isOpaque = false
        notificationPanel.hasShadow = true
        notificationPanel.backgroundColor = NSColor.clear
    }

    func refreshIcon() {
        monitoredAppIcon = Storage.appIcon(for: monitoredApp?.bundleId ?? "")

        if(AppSettings.isIconMask(for: monitoredApp?.appName ?? "") && isDark) {
            monitoredAppIcon = monitoredAppIcon?.invert()
        }

        updateBadgeText(latestBadgeText, force: true)
    }

    @objc func onIconClicked(sender: AnyObject) {
        hideGiantBadge()
        hideNotificationAlert()

        let noAppSelected = statusItem.button?.image == defaultIcon
        let isOptionKeyHolding = NSEvent.modifierFlags.contains(.option)
        let isRightClick = NSApp.currentEvent?.isRightClick == true

        if noAppSelected || isOptionKeyHolding || isRightClick {
            MonitorEngine.shared.showConfigWindow()
        } else if let monitoredAppName = monitoredApp?.appName,
                  let monitoredAppBundleId = monitoredApp?.bundleId {
            let appRunning = MonitorService.isMonitoredAppRunning(bundleIdentifier: monitoredAppBundleId)
            if !appRunning {
                guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: monitoredAppBundleId) else {
                    return
                }

                NSWorkspace.shared.open(appURL)
            } else {
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == monitoredAppBundleId {
                    // Hide the app
                    NSWorkspace.shared.frontmostApplication?.hide()
                } else {
                    // Send the app window to front most
                    MonitorService.openMonitoredApp(appName: monitoredAppName)
                }
            }
        }
    }

    func monitorApp(app: MonitoredApp) {
        monitoredApp = app

        guard let appFullPath = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId)?.absoluteURL.path else {
            return
        }

        guard let targetBundle = Bundle(path: appFullPath) else {
            return
        }

        let appName = app.appName
        statusItem.autosaveName = "Doll_\(app.bundleId)"
        updateBadgeText(nil)

        guard let monitoredAppIcon = monitoredAppIcon else {
            return
        }
        updateBadgeIcon(icon: monitoredAppIcon, size: CGSize(width: defaultIconSize, height: defaultIconSize))

        MonitorService.observe(appName: appName) { [weak self] badge in
            let appRunning = MonitorService.isMonitoredAppRunning(bundleIdentifier: targetBundle.bundleIdentifier ?? "")
            let appIsNotRunningAndIconShouldBeHidden = AppSettings.hideWhenAppNotRunning && !appRunning
            let badgeIsEmptyAndIconShouldBeHidden = AppSettings.hideWhenNothingComing && (badge.isNil || badge?.isEmpty == true)

            if appIsNotRunningAndIconShouldBeHidden || badgeIsEmptyAndIconShouldBeHidden {
                self?.hideStatusBar()
            } else {
                let currentIsDark = self?.statusItem.button?.effectiveAppearance.name.rawValue.lowercased().contains("dark") ?? false
                if(self?.isDark != currentIsDark) {
                    self?.isDark = currentIsDark
                    self?.refreshIcon()
                }

                self?.updateBadgeText(badge)
            }

            self?.repositionGiantBadge()
        }
    }

    func hideStatusBar() {
        statusItem.isVisible = false
    }

    func updateBadgeText(_ text: String?, force: Bool = false) {
        statusItem.isVisible = true

        guard !AppSettings.showOnlyAppIcon else {
            latestBadgeText = text ?? ""
            refreshAppIcon()
            return
        }

        guard force || statusItem.button?.title != text else {
            return
        }

        let textWidth = (text ?? "")
            .width(withConstrainedHeight: defaultIconSize, font: .systemFont(ofSize: 14))
        statusItem.length = defaultIconSize + textWidth

        // New notification comes in
        let newText = text ?? ""

        if newText.isEmpty {
            hideGiantBadge()
            hideNotificationAlert()
        }

        guard let monitoredAppIcon = monitoredAppIcon else {
            return
        }

        if AppSettings.showAsRedBadge {
            let defaultIcon = monitoredAppIcon.addBadgeToImage(drawText: newText)
            let adjustedIcon = (newText.isEmpty && AppSettings.grayoutIconWhenNothingComing) ? (defaultIcon.grayOut() ?? defaultIcon) : defaultIcon
            updateBadgeIcon(icon: adjustedIcon)
            statusItem.length = defaultIconSize
            statusItem.button?.title = ""
        } else {
            let defaultIcon = monitoredAppIcon
            let adjustedIcon = (newText.isEmpty && AppSettings.grayoutIconWhenNothingComing) ? (defaultIcon.grayOut() ?? defaultIcon) : defaultIcon
            updateBadgeIcon(icon: adjustedIcon)
            statusItem.length = defaultIconSize + textWidth
            updateBadgeIcon(icon: adjustedIcon, size: CGSize(width: defaultIconSize, height: defaultIconSize))
            statusItem.button?.title = newText
        }

        let newMessageCount = Int(newText) ?? 0
        if latestBadgeText != newText {
            if AppSettings.showAlertInFullScreenMode {
                tryShowTheNewNotificationPopover(newText: newText)
            }

            let frontmostAppIsMonitoredApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == monitoredApp?.bundleId
            if !frontmostAppIsMonitoredApp, AppSettings.isGiantBadgeEnabled(for: monitoredApp?.appName ?? "") {
                // Don't show giant badge when message count is decreasing
                if newMessageCount >= latestMessageCount {
                    tryShowGiantBadge(text)
                } else {
                    hideGiantBadge()
                }
            } else {
                hideGiantBadge()
            }
        }

        latestBadgeText = newText
        latestMessageCount = newMessageCount
    }

    func refreshDisplayMode() {
        if AppSettings.showOnlyAppIcon {
            refreshAppIcon()
        } else {
            updateBadgeText(latestBadgeText, force: true)
        }
    }

    func refreshAppIcon() {
        guard let monitoredAppIcon else { return }
        let adjustedIcon = (latestBadgeText.isEmpty && AppSettings.grayoutIconWhenNothingComing) ? (monitoredAppIcon.grayOut() ?? monitoredAppIcon) : monitoredAppIcon
        statusItem.length = defaultIconSize
        statusItem.button?.title = ""
        updateBadgeIcon(icon: adjustedIcon, size: CGSize(width: defaultIconSize, height: defaultIconSize))
    }

    func updateBadgeIcon(icon: NSImage?, size: CGSize? = nil) {
        statusItem.button?.image = icon
        if let iconSize = size ?? icon?.size {
            statusItem.button?.image?.size = iconSize
        }
    }

    func tryShowGiantBadge(_ text: String?) {
        let now = Date()
        if !giantBadgePanel.isVisible || now.timeIntervalSince(lastTimeShowingGiantBadge) >= 3 {
            lastTimeShowingGiantBadge = now
            let currentActiveWindowIsFullScreen = Utils.currentActiveWindowIsFullScreen

            if giantBadgePanel.contentViewController != nil {
                giantBadgeController.animationFlag.toggle()
            } else {
                let giantBadgeView = GiantBadgeView(controller: giantBadgeController) { [weak self] in
                    guard let self = self else { return }
                    self.onIconClicked(sender: self)
                }
                giantBadgePanel.contentViewController = NSHostingController(rootView: giantBadgeView)
                giantBadgePanel.setContentSize(giantBadgeSize)
            }

            repositionGiantBadge()
            giantBadgePanel.level = .popUpMenu
            giantBadgePanel.setIsVisible(true)
            giantBadgePanel.orderFrontRegardless()
        }
    }

    func repositionGiantBadge() {
        guard let activeScreen = NSScreen.screenWithMouse,
           let iconFrame = statusItem.button?.window?.frame else {
            return
        }

        var menubarOffset: CGFloat = 0
        if Utils.currentActiveWindowIsFullScreen {
            // In mac with notch, the menubar didn't affect window's size
            menubarOffset = activeScreen.hasTopNotchDesign ? 0 : Utils.menubarHeight
        }

        giantBadgePanel.setFrameOrigin(NSPoint(x: iconFrame.midX - giantBadgeSize.width / 2, y: activeScreen.visibleFrame.maxY - giantBadgeSize.height + menubarOffset + giantBadgeYOffset))
    }

    func hideGiantBadge() {
        giantBadgePanel.setIsVisible(false)
    }

    func tryShowTheNewNotificationPopover(newText: String) {
        if Utils.currentActiveWindowIsFullScreen {
            showNotificationAlert(newText: newText)
        }
    }

    private func showNotificationAlert(newText: String) {
        hideNotificationTimer?.cancel()

        let targetApp = monitoredApp
        let view = NotificationView(icon: monitoredAppIcon ?? defaultIcon, badgeText: newText) { [weak self] in
            if let monitoredAppName = targetApp?.appName {
                MonitorService.openMonitoredApp(appName: monitoredAppName)
            }
            self?.hideNotificationAlert()
        }

        let hostingController = NSHostingController(rootView: view)
        notificationPanel.contentViewController = hostingController
        let fittingSize = hostingController.view.fittingSize
        notificationPanel.setContentSize(fittingSize)

        repositionNotificationPanel(panelSize: fittingSize)
        notificationPanel.orderFrontRegardless()

        let timer = DispatchWorkItem { [weak self] in
            self?.hideNotificationAlert()
        }
        hideNotificationTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timer)
    }

    private func hideNotificationAlert() {
        hideNotificationTimer?.cancel()
        hideNotificationTimer = nil
        notificationPanel.orderOut(nil)
    }

    private func repositionNotificationPanel(panelSize: CGSize) {
        guard let activeScreen = NSScreen.screenWithMouse ?? NSScreen.main,
              let iconFrame = statusItem.button?.window?.frame else {
            return
        }

        var originX = iconFrame.midX - panelSize.width / 2
        if originX + panelSize.width > activeScreen.frame.maxX - 12 {
            originX = activeScreen.frame.maxX - panelSize.width - 12
        }
        if originX < activeScreen.frame.minX + 12 {
            originX = activeScreen.frame.minX + 12
        }

        var targetY = activeScreen.visibleFrame.maxY - panelSize.height - 4
        if Utils.currentActiveWindowIsFullScreen {
            let offset = activeScreen.hasTopNotchDesign ? 0 : Utils.menubarHeight
            targetY = activeScreen.visibleFrame.maxY - panelSize.height + offset - 8
        }
        let maxY = activeScreen.frame.maxY - panelSize.height - 8
        let minY = activeScreen.frame.minY + 8
        let originY = min(max(targetY, minY), maxY)

        notificationPanel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    func destroy() {
        if let monitoredApp = monitoredApp {
            hideNotificationAlert()
            hideGiantBadge()
            MonitorService.unObserve(appName: monitoredApp.appName)
            MonitorEngine.shared.unMonitor(app: monitoredApp)
            statusBar.removeStatusItem(statusItem)
            AppSettings.toggleGiantBadge(for: monitoredApp.appName, value: false)
        }
    }
}

extension String {
    func width(withConstrainedHeight height: CGFloat, font: NSFont) -> CGFloat {
        let constraintRect = CGSize(width: .greatestFiniteMagnitude, height: height)
        let boundingBox = self.boundingRect(with: constraintRect, options: .usesLineFragmentOrigin, attributes: [NSAttributedString.Key.font: font], context: nil)

        return ceil(boundingBox.width)
    }
}

extension NSScreen {
    static var screenWithMouse: NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let screenWithMouse = (screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        })

        return screenWithMouse
    }
    var hasTopNotchDesign: Bool {
        guard #available(macOS 12, *) else { return false }
        return safeAreaInsets.top != 0
    }
}
