import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    UIApplication.shared.isIdleTimerDisabled = true
    return true
  }

  func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
  }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  private var vr: VRViewController?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    guard let ws = scene as? UIWindowScene else { return }
    let w = UIWindow(windowScene: ws)
    let vc = VRViewController()
    w.rootViewController = vc
    w.makeKeyAndVisible()
    window = w
    vr = vc
  }

  func sceneDidBecomeActive(_ scene: UIScene) {
    UIApplication.shared.isIdleTimerDisabled = true
    vr?.resume()
  }

  func sceneWillResignActive(_ scene: UIScene) {
    vr?.pause()
  }
}
