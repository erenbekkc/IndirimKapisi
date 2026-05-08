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

    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()

    FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
      self,
      factoryId: "campaignCardAd",
      nativeAdFactory: CampaignCardAdFactory()
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }
}
