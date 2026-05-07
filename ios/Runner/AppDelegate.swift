import Flutter
import UIKit
import GoogleMobileAds

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

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
