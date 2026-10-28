import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// System equalizer on Android. iOS gives apps no equalizer for streamed audio, so it is absent there.
class EqualizerController extends ChangeNotifier {
  EqualizerController(this._prefs) : effect = Platform.isAndroid ? AndroidEqualizer() : null {
    enabled = _prefs.getBool('eqEnabled') ?? false;
    try {
      _saved = (jsonDecode(_prefs.getString('eqGains') ?? '[]') as List).map((g) => (g as num).toDouble()).toList();
    } catch (_) {}
  }

  final SharedPreferences _prefs;
  final AndroidEqualizer? effect;
  late bool enabled;
  List<double> _saved = [];
  AndroidEqualizerParameters? parameters;

  bool get available => effect != null;

  /// Called once the player has a source: the bands only exist from then on.
  Future<void> attach() async {
    final eq = effect;
    if (eq == null || parameters != null) return;
    final p = await eq.parameters;
    for (var i = 0; i < p.bands.length && i < _saved.length; i++) {
      await p.bands[i].setGain(_saved[i].clamp(p.minDecibels, p.maxDecibels));
    }
    await eq.setEnabled(enabled);
    parameters = p;
    notifyListeners();
  }

  Future<void> setEnabled(bool on) async {
    enabled = on;
    await _prefs.setBool('eqEnabled', on);
    await effect?.setEnabled(on);
    notifyListeners();
  }

  Future<void> setGain(int band, double gain) async {
    final p = parameters;
    if (p == null) return;
    await p.bands[band].setGain(gain);
    _saved = p.bands.map((b) => b.gain).toList();
    await _prefs.setString('eqGains', jsonEncode(_saved));
    notifyListeners();
  }

  Future<void> reset() async {
    final p = parameters;
    if (p == null) return;
    for (final b in p.bands) {
      await b.setGain(0);
    }
    _saved = p.bands.map((b) => b.gain).toList();
    await _prefs.setString('eqGains', jsonEncode(_saved));
    notifyListeners();
  }
}
