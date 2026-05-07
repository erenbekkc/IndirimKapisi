import Flutter
import GoogleMobileAds

class CampaignCardAdFactory: NSObject, FLTNativeAdFactory {
  func createNativeAd(_ nativeAd: NativeAd, customOptions: [AnyHashable: Any]? = nil) -> NativeAdView? {
    let adView = NativeAdView()
    adView.backgroundColor = .white
    adView.layer.cornerRadius = 12
    adView.layer.masksToBounds = true
    adView.layer.borderWidth = 0.5
    adView.layer.borderColor = UIColor.systemGray5.cgColor

    // Headline
    let headlineLabel = UILabel()
    headlineLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
    headlineLabel.numberOfLines = 2
    headlineLabel.textColor = .label
    headlineLabel.text = nativeAd.headline
    adView.headlineView = headlineLabel

    // Body
    let bodyLabel = UILabel()
    bodyLabel.font = UIFont.systemFont(ofSize: 12)
    bodyLabel.textColor = .secondaryLabel
    bodyLabel.numberOfLines = 2
    bodyLabel.text = nativeAd.body
    adView.bodyView = bodyLabel

    // Ad label
    let adLabel = UILabel()
    adLabel.text = "Reklam"
    adLabel.font = UIFont.systemFont(ofSize: 10, weight: .bold)
    adLabel.textColor = UIColor(red: 0.09, green: 0.64, blue: 0.29, alpha: 1)
    adLabel.backgroundColor = UIColor(red: 0.86, green: 0.99, blue: 0.91, alpha: 1)
    adLabel.textAlignment = .center
    adLabel.layer.cornerRadius = 4
    adLabel.layer.masksToBounds = true

    // CTA Button
    let ctaButton = UIButton(type: .system)
    ctaButton.setTitle(nativeAd.callToAction, for: .normal)
    ctaButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
    ctaButton.setTitleColor(.white, for: .normal)
    ctaButton.backgroundColor = UIColor(red: 0.09, green: 0.64, blue: 0.29, alpha: 1)
    ctaButton.layer.cornerRadius = 8
    ctaButton.isUserInteractionEnabled = false
    adView.callToActionView = ctaButton

    // Layout
    let stack = UIStackView(arrangedSubviews: [headlineLabel, bodyLabel])
    stack.axis = .vertical
    stack.spacing = 4

    let hStack = UIStackView(arrangedSubviews: [stack, ctaButton])
    hStack.axis = .horizontal
    hStack.spacing = 10
    hStack.alignment = .center
    ctaButton.widthAnchor.constraint(equalToConstant: 80).isActive = true

    let container = UIStackView(arrangedSubviews: [adLabel, hStack])
    container.axis = .vertical
    container.spacing = 8
    container.translatesAutoresizingMaskIntoConstraints = false

    adView.addSubview(container)
    NSLayoutConstraint.activate([
      container.topAnchor.constraint(equalTo: adView.topAnchor, constant: 10),
      container.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 12),
      container.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -12),
      container.bottomAnchor.constraint(equalTo: adView.bottomAnchor, constant: -10),
      adLabel.widthAnchor.constraint(equalToConstant: 52),
      adLabel.heightAnchor.constraint(equalToConstant: 18),
    ])

    adView.nativeAd = nativeAd
    return adView
  }
}
