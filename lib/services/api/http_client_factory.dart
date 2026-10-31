import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../config/cloud_defaults.dart';

/// The HTTP client for the Storely API.
///
/// Production: the platform default, which checks server certificates against
/// the phone's trusted authorities. A debug build run against a local server may
/// also trust one extra authority, passed as `STORELY_DEV_CA_B64`. The check is on
/// [kDebugMode], a compile-time constant, so a release build cannot trust it even
/// if the value is supplied by mistake.
http.Client createApiHttpClient() {
  if (kDebugMode && CloudDefaults.devCaBase64.isNotEmpty) {
    final context = SecurityContext(withTrustedRoots: true)
      ..setTrustedCertificatesBytes(base64Decode(CloudDefaults.devCaBase64));
    return IOClient(HttpClient(context: context));
  }
  return http.Client();
}
