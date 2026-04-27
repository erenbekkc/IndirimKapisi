package com.alp.indirim_radari

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin.NativeAdFactory

class NativeAdFactoryImpl(private val context: Context) : NativeAdFactory {
    override fun createNativeAd(nativeAd: NativeAd, customOptions: MutableMap<String, Any>?): NativeAdView {
        val view = LayoutInflater.from(context).inflate(R.layout.native_ad, null) as NativeAdView

        val headlineView = view.findViewById<TextView>(R.id.ad_headline)
        val bodyView = view.findViewById<TextView>(R.id.ad_body)
        val ctaView = view.findViewById<Button>(R.id.ad_call_to_action)
        val iconView = view.findViewById<ImageView>(R.id.ad_app_icon)

        headlineView.text = nativeAd.headline
        view.headlineView = headlineView

        if (nativeAd.body != null) {
            bodyView.text = nativeAd.body
            bodyView.visibility = View.VISIBLE
        } else {
            bodyView.visibility = View.GONE
        }
        view.bodyView = bodyView

        if (nativeAd.callToAction != null) {
            ctaView.text = nativeAd.callToAction
            ctaView.visibility = View.VISIBLE
        } else {
            ctaView.visibility = View.GONE
        }
        view.callToActionView = ctaView

        if (nativeAd.icon != null) {
            iconView.setImageDrawable(nativeAd.icon!!.drawable)
            iconView.visibility = View.VISIBLE
        } else {
            iconView.visibility = View.GONE
        }
        view.iconView = iconView

        view.setNativeAd(nativeAd)
        return view
    }
}
