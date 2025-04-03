import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let screenshotChannel = FlutterMethodChannel(name: "com.example.pikabook/screenshot",
                                              binaryMessenger: controller.binaryMessenger)
    
    screenshotChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      switch call.method {
      case "startScreenshotDetection":
        self.startScreenshotDetection(screenshotChannel: screenshotChannel)
        result(true)
      case "stopScreenshotDetection":
        self.stopScreenshotDetection()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    })
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func startScreenshotDetection(screenshotChannel: FlutterMethodChannel) {
    // 스크린샷 감지 시작
    NotificationCenter.default.addObserver(
      forName: UIApplication.userDidTakeScreenshotNotification,
      object: nil,
      queue: OperationQueue.main) { _ in
        screenshotChannel.invokeMethod("onScreenshotTaken", arguments: nil)
    }
  }
  
  private func stopScreenshotDetection() {
    // 스크린샷 감지 중지
    NotificationCenter.default.removeObserver(
      self,
      name: UIApplication.userDidTakeScreenshotNotification,
      object: nil
    )
  }
}
