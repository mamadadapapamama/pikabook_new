import Flutter
import UIKit
import UserNotifications
import StoreKit
import Firebase
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()
    
    // 키보드 관련 설정 추가
    configureKeyboardSettings()
    
    // Flutter 채널 설정
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
    
    // App Store Receipt 채널 설정
    setupAppStoreReceiptChannel()
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
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
  
  /// 키보드 관련 설정
  private func configureKeyboardSettings() {
    // 키보드 자동 조정 비활성화
    NotificationCenter.default.addObserver(
      forName: UIResponder.keyboardWillShowNotification,
      object: nil,
      queue: .main
    ) { notification in
      // 키보드 표시 시 추가 처리
      if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
        print("📱 [Keyboard] 키보드 표시: \(keyboardFrame)")
      }
    }
    
    // 키보드 숨김 시 처리
    NotificationCenter.default.addObserver(
      forName: UIResponder.keyboardWillHideNotification,
      object: nil,
      queue: .main
    ) { _ in
      print("📱 [Keyboard] 키보드 숨김")
    }
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

// MARK: - UNUserNotificationCenterDelegate
  
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
