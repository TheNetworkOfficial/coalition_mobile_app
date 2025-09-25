import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// Call the signer to get presigned PUT URLs
Future<Map<String, dynamic>> signUploads({
  required Uri endpoint,
  required String jobId,
  required List<Map<String, String>> files, // [{path, contentType}]
}) async {
  final res = await http.post(
    endpoint,
    headers: {'content-type': 'application/json'},
    body: jsonEncode({'jobId': jobId, 'files': files}),
  );
  if (res.statusCode != 200) {
    throw Exception('Sign failed: ${res.statusCode} ${res.body}');
  }
  return jsonDecode(res.body);
}

// PUT the files directly to S3 using the returned URLs
Future<void> putFile(Uri putUrl, File file,
    {required String contentType}) async {
  final res = await http.put(
    putUrl,
    headers: {'content-type': contentType},
    body: await file.readAsBytes(),
  );
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception('PUT failed: ${res.statusCode} ${res.body}');
  }
}

// Example usage
Future<void> uploadRenditions() async {
  final endpoint =
      Uri.parse('https://ocon6vm2d9.execute-api.us-west-2.amazonaws.com/');
  final cfgPublicBase = 'https://d21wy4swosisq5.cloudfront.net';
  final jobId = 'some-uuid-from-your-transcoder';

  final sign = await signUploads(
    endpoint: endpoint,
    jobId: jobId,
    files: [
      {
        'path': 'hls/master.m3u8',
        'contentType': 'application/vnd.apple.mpegurl'
      },
      {'path': 'mp4/720.mp4', 'contentType': 'video/mp4'},
    ],
  );

  // upload each file
  for (final r in (sign['results'] as List)) {
    final url = Uri.parse(r['putUrl']);
    final path = r['path'] as String;
    final file = File('/local/path/to/$path'); // your transcoder output path
    final contentType =
        path.endsWith('.m3u8') ? 'application/vnd.apple.mpegurl' : 'video/mp4';
    await putFile(url, file, contentType: contentType);
  }

  // Save HTTPS CDN URLs into your feed:
  final adaptiveStreamUri = '$cfgPublicBase/videos/$jobId/hls/master.m3u8';
  debugPrint('Adaptive stream available at $adaptiveStreamUri');
  // Store adaptiveStreamUri (and MP4s) on the post; delete local temp files to free space.
}
