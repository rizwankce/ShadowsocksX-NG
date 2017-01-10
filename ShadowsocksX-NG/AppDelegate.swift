//
//  AppDelegate.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/5.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Cocoa
import Carbon

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate {
    
    var qrcodeWinCtrl: SWBQRCodeWindowController!
    var preferencesWinCtrl: PreferencesWindowController!
    var advPreferencesWinCtrl: AdvPreferencesWindowController!
    var proxyPreferencesWinCtrl: ProxyPreferencesController!
    var editUserRulesWinCtrl: UserRulesController!
    var httpPreferencesWinCtrl : HTTPPreferencesWindowController!

    let keyCode = kVK_ANSI_P
    let modifierKeys = cmdKey+controlKey
    var hotKeyRef: EventHotKeyRef?

    var launchAtLoginController: LaunchAtLoginController = LaunchAtLoginController()
    
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var statusMenu: NSMenu!
    
    @IBOutlet weak var runningStatusMenuItem: NSMenuItem!
    @IBOutlet weak var toggleRunningMenuItem: NSMenuItem!
    @IBOutlet weak var proxyMenuItem: NSMenuItem!
    @IBOutlet weak var autoModeMenuItem: NSMenuItem!
    @IBOutlet weak var globalModeMenuItem: NSMenuItem!
    @IBOutlet weak var manualModeMenuItem: NSMenuItem!
    @IBOutlet weak var showRunningModeMenuItem: NSMenuItem!
    
    @IBOutlet weak var serversMenuItem: NSMenuItem!
    @IBOutlet var showQRCodeMenuItem: NSMenuItem!
    @IBOutlet var scanQRCodeMenuItem: NSMenuItem!
    @IBOutlet var showBunchJsonExampleFileItem: NSMenuItem!
    @IBOutlet var importBunchJsonFileItem: NSMenuItem!
    @IBOutlet var exportAllServerProfileItem: NSMenuItem!
    @IBOutlet var serversPreferencesMenuItem: NSMenuItem!
    
    @IBOutlet weak var lanchAtLoginMenuItem: NSMenuItem!

    @IBOutlet weak var hudWindow: NSPanel!
    @IBOutlet weak var panelView: NSView!
    @IBOutlet weak var isNameTextField: NSTextField!

    let kHudFadeInDuration: Double = 0.25
    let kHudFadeOutDuration: Double = 0.5
    let kHudDisplayDuration: Double = 2.0

    let kHudAlphaValue: CGFloat = 0.75
    let kHudCornerRadius: CGFloat = 18.0
    let kHudHorizontalMargin: CGFloat = 30
    let kHudHeight: CGFloat = 90.0

    var timerToFadeOut: Timer? = nil
    var fadingOut: Bool = false

    var statusItem: NSStatusItem!
    
    static let StatusItemIconWidth:CGFloat = 20
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
        
        NSUserNotificationCenter.default.delegate = self
        
        // Prepare ss-local
        InstallSSLocal()
        InstallPrivoxy()
        // Prepare defaults
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "ShadowsocksOn": true,
            "ShadowsocksRunningMode": "auto",
            "LocalSocks5.ListenPort": NSNumber(value: 1086 as UInt16),
            "LocalSocks5.ListenAddress": "127.0.0.1",
            "PacServer.ListenPort":NSNumber(value: 8090 as UInt16),
            "LocalSocks5.Timeout": NSNumber(value: 60 as UInt),
            "LocalSocks5.EnableUDPRelay": NSNumber(value: false as Bool),
            "LocalSocks5.EnableVerboseMode": NSNumber(value: false as Bool),
            "GFWListURL": "https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt",
            "AutoConfigureNetworkServices": NSNumber(value: true as Bool),
            "LocalHTTP.ListenAddress": "127.0.0.1",
            "LocalHTTP.ListenPort": NSNumber(value: 1087 as UInt16),
            "LocalHTTPOn": true,
            "LocalHTTP.FollowGlobal": true
            ])
        
        statusItem = NSStatusBar.system().statusItem(withLength: AppDelegate.StatusItemIconWidth)
        let image = NSImage(named: "menu_icon")
        image?.isTemplate = true
        statusItem.image = image
        statusItem.menu = statusMenu
        
        
        let notifyCenter = NotificationCenter.default
        notifyCenter.addObserver(forName: NSNotification.Name(rawValue: NOTIFY_ADV_PROXY_CONF_CHANGED), object: nil, queue: nil
            , using: {
                (note) in
                self.applyConfig()
            }
        )
        notifyCenter.addObserver(forName: NSNotification.Name(rawValue: NOTIFY_SERVER_PROFILES_CHANGED), object: nil, queue: nil
            , using: {
                (note) in
                let profileMgr = ServerProfileManager.instance
                if profileMgr.activeProfileId == nil &&
                    profileMgr.profiles.count > 0{
                    if profileMgr.profiles[0].isValid(){
                        profileMgr.setActiveProfiledId(profileMgr.profiles[0].uuid)
                    }
                }
                self.updateServersMenu()
                self.updateRunningModeMenu()
                SyncSSLocal()
            }
        )
        notifyCenter.addObserver(forName: NSNotification.Name(rawValue: NOTIFY_ADV_CONF_CHANGED), object: nil, queue: nil
            , using: {
                (note) in
                SyncSSLocal()
                self.applyConfig()
            }
        )
        notifyCenter.addObserver(forName: NSNotification.Name(rawValue: NOTIFY_HTTP_CONF_CHANGED), object: nil, queue: nil
            , using: {
                (note) in
                SyncPrivoxy()
                self.applyConfig()
            }
        )
        notifyCenter.addObserver(forName: NSNotification.Name(rawValue: "NOTIFY_FOUND_SS_URL"), object: nil, queue: nil) {
            (note: Notification) in
            if let userInfo = (note as NSNotification).userInfo {
                let urls: [URL] = userInfo["urls"] as! [URL]
                
                let mgr = ServerProfileManager.instance
                var isChanged = false
                
                for url in urls {
                    if let profile = ServerProfile(url: url) {
                        mgr.profiles.append(profile)
                        isChanged = true
                        
                        let userNote = NSUserNotification()
                        userNote.title = "Add Shadowsocks Server Profile".localized
                        if userInfo["source"] as! String == "qrcode" {
                            userNote.subtitle = "By scan QR Code".localized
                        } else if userInfo["source"] as! String == "url" {
                            userNote.subtitle = "By Handle SS URL".localized
                        }
                        userNote.informativeText = "Host: \(profile.serverHost)"
                        //" Port: \(profile.serverPort)"
                        //" Encription Method: \(profile.method)".localized
                        userNote.soundName = NSUserNotificationDefaultSoundName
                        
                        NSUserNotificationCenter.default
                            .deliver(userNote);
                    }
                }
                
                if isChanged {
                    mgr.save()
                    self.updateServersMenu()
                }
            }
        }
        
        // Handle ss url scheme
        NSAppleEventManager.shared().setEventHandler(self
            , andSelector: #selector(self.handleURLEvent)
            , forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        
        updateMainMenu()
        updateServersMenu()
        updateRunningModeMenu()
        updateLaunchAtLoginMenu()
        
        ProxyConfHelper.install()
        ProxyConfHelper.startMonitorPAC()
        applyConfig()
        SyncSSLocal()

        // Register global hotkey
        registerHotkey()
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
        StopSSLocal()
        StopPrivoxy()
        ProxyConfHelper.disableProxy()
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
    }

    func applyConfig() {
        let defaults = UserDefaults.standard
        let isOn = defaults.bool(forKey: "ShadowsocksOn")
        let mode = defaults.string(forKey: "ShadowsocksRunningMode")
        
        if isOn {
            StartSSLocal()
            StartPrivoxy()
            if mode == "auto" {
                ProxyConfHelper.enablePACProxy()
            } else if mode == "global" {
                ProxyConfHelper.enableGlobalProxy()
            } else if mode == "manual" {
                ProxyConfHelper.disableProxy()
            }
        } else {
            StopSSLocal()
            StopPrivoxy()
            ProxyConfHelper.disableProxy()
        }
    }

    // MARK: - Hotkey Methods
    func registerHotkey() -> Void {
        var gMyHotKeyID = EventHotKeyID()
        gMyHotKeyID.signature = OSType(fourCharCodeFrom(string: "sxng"))
        gMyHotKeyID.id = UInt32(keyCode)

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)

        // Void pointer to `self`:
        let context = Unmanaged.passUnretained(self).toOpaque()

        // Install handler.
        InstallEventHandler(GetApplicationEventTarget(), {(nextHanlder, theEvent, userContext) -> OSStatus in
            // Extract pointer to `self` from void pointer:
            let mySelf = Unmanaged<AppDelegate>.fromOpaque(userContext!).takeUnretainedValue()

            switch Globals.proxyType {
            case .pac:
                Globals.proxyType = .global
                UserDefaults.standard.setValue("global", forKey: "ShadowsocksRunningMode")
                mySelf.isNameTextField.stringValue = "Gobal Mode"
                mySelf.updateRunningModeMenu()
                mySelf.applyConfig()
            case .global:
                Globals.proxyType = .pac
                UserDefaults.standard.setValue("auto", forKey: "ShadowsocksRunningMode")
                mySelf.isNameTextField.stringValue = "Auto Mode"
                mySelf.updateRunningModeMenu()
                mySelf.applyConfig()
            }

            mySelf.fadeInHud()

            return noErr
        }, 1, &eventType, context, nil)

        // Register hotkey.
        RegisterEventHotKey(UInt32(keyCode),
                            UInt32(modifierKeys),
                            gMyHotKeyID,
                            GetApplicationEventTarget(),
                            0,
                            &hotKeyRef)
    }

    func fourCharCodeFrom(string: String) -> FourCharCode {
        assert(string.characters.count == 4, "String length must be 4")
        var result: FourCharCode = 0
        for char in string.utf16 {
            result = (result << 8) + FourCharCode(char)
        }
        return result
    }

    // MARK: - UI Methods
    @IBAction func toggleRunning(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        var isOn = defaults.bool(forKey: "ShadowsocksOn")
        isOn = !isOn
        defaults.set(isOn, forKey: "ShadowsocksOn")
        
        updateMainMenu()
        
        applyConfig()
    }
    
    @IBAction func updateGFWList(_ sender: NSMenuItem) {
        UpdatePACFromGFWList()
    }
    
    @IBAction func editUserRulesForPAC(_ sender: NSMenuItem) {
        if editUserRulesWinCtrl != nil {
            editUserRulesWinCtrl.close()
        }
        let ctrl = UserRulesController(windowNibName: "UserRulesController")
        editUserRulesWinCtrl = ctrl
        
        ctrl.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
        ctrl.window?.makeKeyAndOrderFront(self)
    }
    
    @IBAction func showQRCodeForCurrentServer(_ sender: NSMenuItem) {
        var errMsg: String?
        if let profile = ServerProfileManager.instance.getActiveProfile() {
            if profile.isValid() {
                // Show window
                if qrcodeWinCtrl != nil{
                    qrcodeWinCtrl.close()
                }
                qrcodeWinCtrl = SWBQRCodeWindowController(windowNibName: "SWBQRCodeWindowController")
                qrcodeWinCtrl.qrCode = profile.URL()!.absoluteString
                qrcodeWinCtrl.showWindow(self)
                NSApp.activate(ignoringOtherApps: true)
                qrcodeWinCtrl.window?.makeKeyAndOrderFront(nil)
                
                return
            } else {
                errMsg = "Current server profile is not valid.".localized
            }
        } else {
            errMsg = "No current server profile.".localized
        }
        let userNote = NSUserNotification()
        userNote.title = errMsg
        userNote.soundName = NSUserNotificationDefaultSoundName
        
        NSUserNotificationCenter.default
            .deliver(userNote);
    }
    
    @IBAction func scanQRCodeFromScreen(_ sender: NSMenuItem) {
        ScanQRCodeOnScreen()
    }
    
    @IBAction func showBunchJsonExampleFile(sender: NSMenuItem) {
        ServerProfileManager.showExampleConfigFile()
    }
    
    @IBAction func importBunchJsonFile(sender: NSMenuItem) {
        ServerProfileManager.instance.importConfigFile()
        //updateServersMenu()//not working
    }
    
    @IBAction func exportAllServerProfile(sender: NSMenuItem) {
        ServerProfileManager.instance.exportConfigFile()
    }

    @IBAction func toggleLaunghAtLogin(sender: NSMenuItem) {
        launchAtLoginController.launchAtLogin = !launchAtLoginController.launchAtLogin;
        updateLaunchAtLoginMenu()
    }
    
    @IBAction func selectPACMode(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        defaults.setValue("auto", forKey: "ShadowsocksRunningMode")
        updateRunningModeMenu()
        applyConfig()
    }
    
    @IBAction func selectGlobalMode(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        defaults.setValue("global", forKey: "ShadowsocksRunningMode")
        updateRunningModeMenu()
        applyConfig()
    }
    
    @IBAction func selectManualMode(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        defaults.setValue("manual", forKey: "ShadowsocksRunningMode")
        updateRunningModeMenu()
        applyConfig()
    }
    
    @IBAction func editServerPreferences(_ sender: NSMenuItem) {
        if preferencesWinCtrl != nil {
            preferencesWinCtrl.close()
        }
        let ctrl = PreferencesWindowController(windowNibName: "PreferencesWindowController")
        preferencesWinCtrl = ctrl
        
        ctrl.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
        ctrl.window?.makeKeyAndOrderFront(self)
    }
    
    @IBAction func editAdvPreferences(_ sender: NSMenuItem) {
        if advPreferencesWinCtrl != nil {
            advPreferencesWinCtrl.close()
        }
        let ctrl = AdvPreferencesWindowController(windowNibName: "AdvPreferencesWindowController")
        advPreferencesWinCtrl = ctrl
        
        ctrl.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
        ctrl.window?.makeKeyAndOrderFront(self)
    }
    
    @IBAction func editHTTPPreferences(_ sender: NSMenuItem) {
        if httpPreferencesWinCtrl != nil {
            httpPreferencesWinCtrl.close()
        }
        let ctrl = HTTPPreferencesWindowController(windowNibName: "HTTPPreferencesWindowController")
        httpPreferencesWinCtrl = ctrl
        
        ctrl.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
        ctrl.window?.makeKeyAndOrderFront(self)
    }
    
    @IBAction func editProxyPreferences(_ sender: NSObject) {
        if proxyPreferencesWinCtrl != nil {
            proxyPreferencesWinCtrl.close()
        }
        proxyPreferencesWinCtrl = ProxyPreferencesController(windowNibName: "ProxyPreferencesController")
        proxyPreferencesWinCtrl.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
        proxyPreferencesWinCtrl.window?.makeKeyAndOrderFront(self)
    }
    
    @IBAction func selectServer(_ sender: NSMenuItem) {
        let index = sender.tag
        let spMgr = ServerProfileManager.instance
        let newProfile = spMgr.profiles[index]
        if newProfile.uuid != spMgr.activeProfileId {
            spMgr.setActiveProfiledId(newProfile.uuid)
            updateServersMenu()
            SyncSSLocal()
        }
        updateRunningModeMenu()
    }
    
    @IBAction func showLogs(_ sender: NSMenuItem) {
        let ws = NSWorkspace.shared()
        if let appUrl = ws.urlForApplication(withBundleIdentifier: "com.apple.Console") {
            try! ws.launchApplication(at: appUrl
                ,options: .default
                ,configuration: [NSWorkspaceLaunchConfigurationArguments: "~/Library/Logs/ss-local.log"])
        }
    }
    
    @IBAction func feedback(_ sender: NSMenuItem) {
        NSWorkspace.shared().open(URL(string: "https://github.com/qiuyuzhou/ShadowsocksX-NG/issues")!)
    }
    
    @IBAction func showAbout(_ sender: NSMenuItem) {
        NSApp.orderFrontStandardAboutPanel(sender);
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @IBAction func showRunningMode(_ sender: NSMenuItem) {
        sender.state = sender.state == 1 ? 0 : 1
        let defaults = UserDefaults.standard
        let isShown = (sender.state == 1)
        defaults.set(isShown, forKey: "ShowRunningModeOnStatusBar")
        updateStatusItemUI(isShownnRunningMode: isShown)
    }
    
    func updateLaunchAtLoginMenu() {
        if launchAtLoginController.launchAtLogin {
            lanchAtLoginMenuItem.state = 1
        } else {
            lanchAtLoginMenuItem.state = 0
        }
    }
    
    func updateRunningModeMenu() {
        let defaults = UserDefaults.standard
        let mode = defaults.string(forKey: "ShadowsocksRunningMode")
        
        showRunningModeMenuItem.title = "Show Running Mode On Status Bar".localized
        showRunningModeMenuItem.state = defaults.bool(forKey: "ShowRunningModeOnStatusBar") ? 1 : 0
        
        var serverMenuText = "Servers".localized

        let mgr = ServerProfileManager.instance
        for p in mgr.profiles {
            if mgr.activeProfileId == p.uuid {
                var profileName :String
                if !p.remark.isEmpty {
                    profileName = p.remark
                } else {
                    profileName = p.serverHost
                }
                serverMenuText = "\(serverMenuText) - \(profileName)"
            }
        }
        serversMenuItem.title = serverMenuText
        
        if mode == "auto" {
            proxyMenuItem.title = "Proxy - Auto By PAC".localized
            autoModeMenuItem.state = 1
            globalModeMenuItem.state = 0
            manualModeMenuItem.state = 0
        } else if mode == "global" {
            proxyMenuItem.title = "Proxy - Global".localized
            autoModeMenuItem.state = 0
            globalModeMenuItem.state = 1
            manualModeMenuItem.state = 0
        } else if mode == "manual" {
            proxyMenuItem.title = "Proxy - Manual".localized
            autoModeMenuItem.state = 0
            globalModeMenuItem.state = 0
            manualModeMenuItem.state = 1
        }
        let isShown = defaults.bool(forKey: "ShowRunningModeOnStatusBar")
        updateStatusItemUI(isShownnRunningMode: isShown)
    }
    
    func updateStatusItemUI(isShownnRunningMode: Bool) {
        if isShownnRunningMode {
            let defaults = UserDefaults.standard
            let mode = defaults.string(forKey: "ShadowsocksRunningMode")
            if mode == "auto" {
                statusItem.title = "Auto".localized
            } else if mode == "global" {
                statusItem.title = "Global".localized
            } else if mode == "manual" {
                statusItem.title = "Manual".localized
            }
            let titleWidth = statusItem.title!.size(withAttributes: [NSFontAttributeName: statusItem.button!.font!]).width
            let imageWidth:CGFloat = AppDelegate.StatusItemIconWidth
            statusItem.length = titleWidth + imageWidth + 2
        } else {
            statusItem.length = AppDelegate.StatusItemIconWidth
        }
    }
    
    func updateMainMenu() {
        let defaults = UserDefaults.standard
        let isOn = defaults.bool(forKey: "ShadowsocksOn")
        if isOn {
            runningStatusMenuItem.title = "Shadowsocks: On".localized
            toggleRunningMenuItem.title = "Turn Shadowsocks Off".localized
            let image = NSImage(named: "menu_icon")
            statusItem.image = image
        } else {
            runningStatusMenuItem.title = "Shadowsocks: Off".localized
            toggleRunningMenuItem.title = "Turn Shadowsocks On".localized
            let image = NSImage(named: "menu_icon_disabled")
            statusItem.image = image
        }
    }
    
    func updateServersMenu() {
        let mgr = ServerProfileManager.instance
        serversMenuItem.submenu?.removeAllItems()
        let showQRItem = showQRCodeMenuItem
        let scanQRItem = scanQRCodeMenuItem
        let preferencesItem = serversPreferencesMenuItem
        let showBunch = showBunchJsonExampleFileItem
        let importBuntch = importBunchJsonFileItem
        let exportAllServer = exportAllServerProfileItem
        
        var i = 0
        for p in mgr.profiles {
            let item = NSMenuItem()
            item.tag = i
            if p.remark.isEmpty {
                item.title = "\(p.serverHost)"
            } else {
                item.title = "\(p.remark) (\(p.serverHost))"
            }
            if mgr.activeProfileId == p.uuid {
                item.state = 1
            }
            if !p.isValid() {
                item.isEnabled = false
            }
            item.action = #selector(AppDelegate.selectServer)
            
            serversMenuItem.submenu?.addItem(item)
            i += 1
        }
        if !mgr.profiles.isEmpty {
            serversMenuItem.submenu?.addItem(NSMenuItem.separator())
        }
        serversMenuItem.submenu?.addItem(showQRItem!)
        serversMenuItem.submenu?.addItem(scanQRItem!)
        serversMenuItem.submenu?.addItem(showBunch!)
        serversMenuItem.submenu?.addItem(importBuntch!)
        serversMenuItem.submenu?.addItem(exportAllServer!)
        serversMenuItem.submenu?.addItem(NSMenuItem.separator())
        serversMenuItem.submenu?.addItem(preferencesItem!)
    }
    
    func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        if let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue {
            if let url = URL(string: urlString) {
                NotificationCenter.default.post(
                    name: Notification.Name(rawValue: "NOTIFY_FOUND_SS_URL"), object: nil
                    , userInfo: [
                        "ruls": [url],
                        "source": "url",
                        ])
            }
        }
    }
    
    //------------------------------------------------------------
    // NSUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: NSUserNotificationCenter
        , shouldPresent notification: NSUserNotification) -> Bool {
        return true
    }
}

extension AppDelegate {
    func fadeInHud() -> Void {
        if timerToFadeOut != nil {
            timerToFadeOut?.invalidate()
            timerToFadeOut = nil
        }

        fadingOut = false

        hudWindow.orderFrontRegardless()

        CATransaction.begin()
        CATransaction.setAnimationDuration(kHudFadeInDuration)
        CATransaction.setCompletionBlock { self.didFadeIn() }
        panelView.layer?.opacity = 1.0
        CATransaction.commit()
    }

    func didFadeIn() -> Void {
        timerToFadeOut = Timer.scheduledTimer(
            timeInterval: kHudDisplayDuration,
            target: self,
            selector: #selector(fadeOutHud),
            userInfo: nil,
            repeats: false)
    }

    func fadeOutHud() -> Void {
        fadingOut = true

        CATransaction.begin()
        CATransaction.setAnimationDuration(kHudFadeOutDuration)
        CATransaction.setCompletionBlock { self.didFadeOut() }
        panelView.layer?.opacity = 0.0
        CATransaction.commit()
    }

    func didFadeOut() -> Void {
        if fadingOut {
            self.hudWindow.orderOut(nil)
        }
        fadingOut = false
    }

    func setupHud() -> Void {
        isNameTextField.stringValue = "Global Mode"
        isNameTextField.sizeToFit()

        var labelFrame: CGRect = isNameTextField.frame
        var hudWindowFrame: CGRect = hudWindow.frame
        hudWindowFrame.size.width = labelFrame.size.width + kHudHorizontalMargin * 2
        hudWindowFrame.size.height = kHudHeight

        let screenRect: NSRect = NSScreen.screens()![0].visibleFrame
        hudWindowFrame.origin.x = (screenRect.size.width - hudWindowFrame.size.width) / 2
        hudWindowFrame.origin.y = (screenRect.size.height - hudWindowFrame.size.height) / 2
        hudWindow.setFrame(hudWindowFrame, display: true)

        var viewFrame: NSRect = hudWindowFrame;
        viewFrame.origin.x = 0
        viewFrame.origin.y = 0
        panelView.frame = viewFrame

        labelFrame.origin.x = kHudHorizontalMargin
        labelFrame.origin.y = (hudWindowFrame.size.height - labelFrame.size.height) / 2
        isNameTextField.frame = labelFrame
    }

    func initUIComponent() -> Void {
        hudWindow.isOpaque = false
        hudWindow.backgroundColor = .clear
        hudWindow.level = Int(CGWindowLevelForKey(.utilityWindow)) + 1000
        hudWindow.styleMask = .borderless
        hudWindow.hidesOnDeactivate = false
        hudWindow.collectionBehavior = .canJoinAllSpaces

        let viewLayer: CALayer = CALayer()
        viewLayer.backgroundColor = CGColor.init(red: 0.05, green: 0.05, blue: 0.05, alpha: kHudAlphaValue)
        viewLayer.cornerRadius = kHudCornerRadius
        panelView.wantsLayer = true
        panelView.layer = viewLayer
        panelView.layer?.opacity = 0.0

        setupHud()
    }
    
    override func awakeFromNib() {
        initUIComponent()
    }
}
