import Flutter
import UIKit
import GoogleMobileAds
import UserNotifications
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Swizzling kapalı olduğu için delegate ve token iletimini manuel yapıyoruz
    UNUserNotificationCenter.current().delegate = self
    Messaging.messaging().delegate = self
    application.registerForRemoteNotifications()

    FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
      self,
      factoryId: "campaignCardAd",
      nativeAdFactory: CampaignCardAdFactory()
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // APNS token gelince Firebase'e ilet
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
  }

  // APNS token alınamazsa sessizce geç
  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    // no-op
  }
}

// FCM token değişince Flutter plugin'e ilet
extension AppDelegate: MessagingDelegate {
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    let dataDict: [String: String] = ["token": fcmToken ?? ""]
    NotificationCenter.default.post(
      name: Notification.Name("FCMToken"),
      object: nil,
      userInfo: dataDict
    )
  }
}
