

import SwiftUI

@main
struct TimetableApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        setupUNUserNotification()
        
        Timetable.shared.registerBackgroundReload()
        Timetable.shared.scheduleBackgroundReload()
        
        UIScrollView.appearance().keyboardDismissMode = .onDrag
        UITextField.appearance().clearButtonMode = .whileEditing
        
        return true
    }
    
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Swift.Void) {
        switch identifier {
        case RadioDownloder.identifier:
            Timetable.shared.downloader.saveCompletionHandler(completionHandler)
        default:
            DispatchQueue.main.async {
                completionHandler()
            }
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func setupUNUserNotification() {
        let center = UNUserNotificationCenter.current()
        let setting: UNAuthorizationOptions  = [.alert, .sound]
        
        center.requestAuthorization(options: setting) { (granted, error) in
            if error != nil {
                return
            }
            if granted {
            } else {
            }
        }
        center.delegate = self
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Swift.Void) {
        completionHandler([.alert, .sound])
    }
}
