import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final networkConnectivityServiceProvider =
    Provider<NetworkConnectivityService>((ref) {
  return NetworkConnectivityService(Connectivity());
});

final networkOnlineProvider = StreamProvider<bool>((ref) {
  return ref.watch(networkConnectivityServiceProvider).watchOnline();
});

class NetworkConnectivityService {
  NetworkConnectivityService(this._connectivity);

  final Connectivity _connectivity;

  Future<bool> isOnline() async {
    final results = await _connectivity.checkConnectivity();
    return _isAnyOnline(results);
  }

  Stream<bool> watchOnline() {
    return _connectivity.onConnectivityChanged.map(_isAnyOnline);
  }

  bool _isAnyOnline(List<ConnectivityResult> results) {
    return results.any(
      (result) =>
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.ethernet ||
          result == ConnectivityResult.vpn,
    );
  }
}
