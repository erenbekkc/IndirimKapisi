import Flutter
import UIKit
import GoogleMobileAds
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
      self,
      factoryId: "campaignCardAd",
      nativeAdFactory: CampaignCardAdFactory()
    )

    // APNS kaydını başlat
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // APNS token geldiğinde Firebase'e açıkça ilet
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }
}
