// ad_manager.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdManager {
  static final AdManager instance = AdManager._internal();
  AdManager._internal();

  RewardedAd? _rewardedAd;
  bool _isAdLoading = false;

  // Safely checks target platform without importing dart:io
  final String _adUnitId = kIsWeb
      ? 'web_placeholder' // Never actually loaded on web
      : (defaultTargetPlatform == TargetPlatform.android
          ? 'ca-app-pub-9129185338955527/4473854550' // Android Real Ads ID
          : 'ca-app-pub-3940256099942544/1712485313'); // TODO: Replace with real iOS Ad Unit ID before App Store release

  void loadRewardedAd() {
    if (kIsWeb) return; // Abort immediately on Web
    
    if (_rewardedAd != null || _isAdLoading) return;
    _isAdLoading = true;

    RewardedAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isAdLoading = false;
        },
        onAdFailedToLoad: (error) {
          debugPrint('RewardedAd failed to load: $error');
          _rewardedAd = null;
          _isAdLoading = false;
        },
      ),
    );
  }

  void showRewardedAd({required VoidCallback onRewardEarned, required VoidCallback onAdFailed}) {
    // --- FAKE AD FOR WEB TESTING ---
    if (kIsWeb) {
      debugPrint('Web Mode: Simulating Ad Watch completion.');
      onRewardEarned();
      return; 
    }

    if (_rewardedAd == null) {
      debugPrint('Warning: Ad was not loaded yet.');
      onAdFailed(); // Tell the UI we failed (and unmute audio)
      loadRewardedAd(); 
      return;
    }

    bool rewardGranted = false;

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        // FIXED: If the user closed the ad early without earning the reward, notify caller so audio unmutes!
        if (!rewardGranted) {
          onAdFailed();
        }
        loadRewardedAd(); // Immediately queue up the next ad
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('RewardedAd failed to show: $error');
        ad.dispose();
        _rewardedAd = null;
        // FIXED: Trigger failure callback so UI/audio recovers cleanly
        onAdFailed();
        loadRewardedAd();
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        rewardGranted = true;
        onRewardEarned();
      },
    );
  }
}