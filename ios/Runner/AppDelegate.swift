import Flutter
import UIKit
import UserNotifications
import StoreKit

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
    
    // 포그라운드 알림 표시를 위한 설정
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }
    
    // App Store Receipt 채널 설정
    setupAppStoreReceiptChannel()
    
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
  
  private func setupAppStoreReceiptChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    
    let receiptChannel = FlutterMethodChannel(
      name: "app_store_receipt",
      binaryMessenger: controller.binaryMessenger
    )
    
    receiptChannel.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "getReceiptData":
        self?.getReceiptData(result: result)
      case "refreshReceipt":
        self?.refreshReceipt(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
  
  /// 현재 디바이스의 App Store Receipt 데이터 가져오기
  private func getReceiptData(result: @escaping FlutterResult) {
    guard let receiptURL = Bundle.main.appStoreReceiptURL else {
      print("❌ [AppStoreReceipt] Receipt URL을 찾을 수 없습니다")
      result(FlutterError(code: "NO_RECEIPT_URL", message: "Receipt URL not found", details: nil))
      return
    }
    
    guard let receiptData = try? Data(contentsOf: receiptURL) else {
      print("❌ [AppStoreReceipt] Receipt 데이터를 읽을 수 없습니다")
      result(FlutterError(code: "NO_RECEIPT_DATA", message: "Could not read receipt data", details: nil))
      return
    }
    
    let receiptString = receiptData.base64EncodedString()
    print("✅ [AppStoreReceipt] Receipt 데이터 획득 성공: \(receiptData.count) bytes")
    
    result(receiptString)
  }
  
  /// Receipt 새로고침 (사용자에게 App Store 로그인 요청 가능)
  private func refreshReceipt(result: @escaping FlutterResult) {
    let request = SKReceiptRefreshRequest()
    request.delegate = ReceiptRefreshDelegate(result: result)
    request.start()
  }
}

// MARK: - UNUserNotificationCenterDelegate
@available(iOS 10.0, *)
extension AppDelegate {
  // 앱이 포그라운드에 있을 때 알림 표시
  override func userNotificationCenter(_ center: UNUserNotificationCenter,
                            willPresent notification: UNNotification,
                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.alert, .sound, .badge])
  }
  
  // 알림 탭 처리
  override func userNotificationCenter(_ center: UNUserNotificationCenter,
                            didReceive response: UNNotificationResponse,
                            withCompletionHandler completionHandler: @escaping () -> Void) {
    completionHandler()
  }
}

/// Receipt 새로고침 델리게이트
class ReceiptRefreshDelegate: NSObject, SKRequestDelegate {
  private let result: FlutterResult
  
  init(result: @escaping FlutterResult) {
    self.result = result
  }
  
  func requestDidFinish(_ request: SKRequest) {
    print("✅ [AppStoreReceipt] Receipt 새로고침 완료")
    result(true)
  }
  
  func request(_ request: SKRequest, didFailWithError error: Error) {
    print("❌ [AppStoreReceipt] Receipt 새로고침 실패: \(error.localizedDescription)")
    result(FlutterError(
      code: "REFRESH_FAILED",
      message: "Receipt refresh failed: \(error.localizedDescription)",
      details: nil
    ))
  }
}
