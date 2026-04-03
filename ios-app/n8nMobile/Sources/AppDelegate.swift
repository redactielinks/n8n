import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        let nav = UINavigationController(rootViewController: ServerListViewController())
        nav.navigationBar.barTintColor = UIColor(red: 1.0, green: 0.46, blue: 0.0, alpha: 1.0)
        nav.navigationBar.tintColor = .white
        nav.navigationBar.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.navigationBar.isTranslucent = false
        window?.rootViewController = nav
        window?.makeKeyAndVisible()
        return true
    }
}
