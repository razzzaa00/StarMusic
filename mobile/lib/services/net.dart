import 'dart:convert';

import 'package:http/http.dart' as http;

const browserUserAgent =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Mobile/15E148 Safari/604.1';

final http.Client httpClient = http.Client();

Future<dynamic> getJson(Uri uri, {Map<String, String>? headers, Duration timeout = const Duration(seconds: 10)}) async {
  final res = await httpClient.get(uri, headers: {'User-Agent': browserUserAgent, ...?headers}).timeout(timeout);
  if (res.statusCode < 200 || res.statusCode >= 300) throw HttpStatusException(res.statusCode, uri);
  return jsonDecode(utf8.decode(res.bodyBytes));
}

Future<dynamic> postJson(Uri uri, Object body, {Map<String, String>? headers, Duration timeout = const Duration(seconds: 10)}) async {
  final res = await httpClient
      .post(uri, body: jsonEncode(body), headers: {'Content-Type': 'application/json', 'User-Agent': browserUserAgent, ...?headers})
      .timeout(timeout);
  if (res.statusCode < 200 || res.statusCode >= 300) throw HttpStatusException(res.statusCode, uri);
  return jsonDecode(utf8.decode(res.bodyBytes));
}

class HttpStatusException implements Exception {
  HttpStatusException(this.status, this.uri);
  final int status;
  final Uri uri;
  @override
  String toString() => 'HTTP $status for ${uri.host}${uri.path}';
}
