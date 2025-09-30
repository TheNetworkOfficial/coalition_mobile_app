import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/backend_config_loader.dart';
import '../../../core/config/backend_config_provider.dart';
import '../models/mux_dtos.dart';

typedef ProgressCallback = void Function(int sentBytes, int totalBytes);

const bool kUseMux = true;

class MuxUploadTicket {
  final String uploadId; // Mux direct_upload id (from backend)
  final String? method; // "POST" or "PUT" for simple uploads (if provided)
  final Uri? url; // simple upload URL
  final Uri? tusUrl; // tus endpoint if resumable
  final Map<String, String> tusHeaders; // e.g. Authorization if needed

  MuxUploadTicket({
    required this.uploadId,
    this.method,
    this.url,
    this.tusUrl,
    this.tusHeaders = const {},
  });

  factory MuxUploadTicket.fromJson(Map<String, dynamic> j) {
    return MuxUploadTicket(
      uploadId: j['upload_id'] as String,
      method: j['method'] as String?,
      url: j['url'] != null ? Uri.parse(j['url']) : null,
      tusUrl: j['tus']?['url'] != null ? Uri.parse(j['tus']['url']) : null,
      tusHeaders: j['tus']?['headers'] != null
          ? Map<String, String>.from(j['tus']['headers'])
          : const {},
    );
  }

  bool get isTus => tusUrl != null;
}

class MuxUploadResult {
  final String uploadId; // same as ticket.uploadId
  final int bytesSent;
  const MuxUploadResult({required this.uploadId, required this.bytesSent});
}

abstract class MuxUploadService {
  /// Calls *your backend* to mint a Direct Upload (simple or tus) and returns the ticket.
  Future<MuxUploadTicket> createDirectUpload({
    required String filename,
    required int filesizeBytes,
    String contentType = 'video/mp4',
    bool preferTus = true,
  });

  /// Uploads the MP4 to Mux using the ticket (simple or tus). Progress optional.
  Future<MuxUploadResult> uploadVideo({
    required MuxUploadTicket ticket,
    required File mp4,
    ProgressCallback? onProgress,
  });
}

final muxUploadServiceProvider = Provider<MuxUploadService>((ref) {
  final config = ref.watch(backendConfigProvider);
  final client = http.Client();
  ref.onDispose(client.close);
  return MuxUploadServiceHttp(client: client, config: config);
});

class MuxUploadServiceHttp implements MuxUploadService {
  MuxUploadServiceHttp({required http.Client client, required BackendConfig config})
      : _client = client,
        _config = config;

  final http.Client _client;
  final BackendConfig _config;
  static const Duration _httpTimeout = Duration(seconds: 5);

  static const _kTusResumableVersion = '1.0.0';

  Uri get _muxBaseUri => _ensureTrailingSlash(_config.baseUri).resolve('mux/');

  @override
  Future<MuxUploadTicket> createDirectUpload({
    required String filename,
    required int filesizeBytes,
    String contentType = 'video/mp4',
    bool preferTus = true,
  }) async {
    final uri = _muxBaseUri.resolve('direct-uploads');
    final requestDto = CreateMuxUploadRequest(
      filename: filename,
      filesize: filesizeBytes,
      contentType: contentType,
      preferTus: preferTus,
    );
    final response = await _client
        .post(
      uri,
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(requestDto.toJson()),
    )
        .timeout(_httpTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Failed to create Mux upload: ${response.statusCode} ${response.reasonPhrase}\n${response.body}',
        uri: uri,
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final responseDto = CreateMuxUploadResponse.fromJson(decoded);

    return MuxUploadTicket(
      uploadId: responseDto.uploadId,
      method: responseDto.method,
      url: responseDto.url != null ? Uri.parse(responseDto.url!) : null,
      tusUrl: responseDto.tus != null && responseDto.tus!['url'] != null
          ? Uri.parse(responseDto.tus!['url'] as String)
          : null,
      tusHeaders: responseDto.tus != null && responseDto.tus!['headers'] != null
          ? Map<String, String>.from(
              (responseDto.tus!['headers'] as Map<dynamic, dynamic>).map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              ),
            )
          : const {},
    );
  }

  @override
  Future<MuxUploadResult> uploadVideo({
    required MuxUploadTicket ticket,
    required File mp4,
    ProgressCallback? onProgress,
  }) async {
    if (ticket.isTus) {
      return MuxUploadResult(
        uploadId: ticket.uploadId,
        bytesSent: await _uploadViaTus(
          ticket: ticket,
          mp4: mp4,
          onProgress: onProgress,
        ),
      );
    }

    final uploadUrl = ticket.url;
    if (uploadUrl == null) {
      throw StateError('Ticket missing direct upload URL.');
    }
    final method = (ticket.method ?? 'POST').toUpperCase();
    final totalBytes = await mp4.length();
    final request = http.StreamedRequest(method, uploadUrl)
      ..headers['content-type'] = 'video/mp4'
      ..contentLength = totalBytes;

    final completer = Completer<void>();
    var sentBytes = 0;
    final subscription = mp4.openRead().listen(
      (chunk) {
        request.sink.add(chunk);
        sentBytes += chunk.length;
        onProgress?.call(sentBytes, totalBytes);
      },
      onError: (Object error, StackTrace stackTrace) {
        request.sink.close();
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
      onDone: () {
        request.sink.close();
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      cancelOnError: true,
    );

    try {
      final responseFuture = _client.send(request).timeout(_httpTimeout);
      await completer.future;
      final response = await responseFuture;
      await response.stream.drain();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Mux upload failed: ${response.statusCode} ${response.reasonPhrase}',
          uri: uploadUrl,
        );
      }
    } finally {
      await subscription.cancel();
    }

    return MuxUploadResult(
      uploadId: ticket.uploadId,
      bytesSent: totalBytes,
    );
  }

  Future<int> _uploadViaTus({
    required MuxUploadTicket ticket,
    required File mp4,
    ProgressCallback? onProgress,
  }) async {
    final tusUrl = ticket.tusUrl;
    if (tusUrl == null) {
      throw StateError('Ticket marked as tus but missing endpoint.');
    }

    final totalBytes = await mp4.length();
    final headers = _mergeTusHeaders(ticket.tusHeaders);
    final initialOffset = await _fetchTusOffset(tusUrl, headers);
    if (initialOffset >= totalBytes) {
      onProgress?.call(totalBytes, totalBytes);
      return totalBytes;
    }

    if (initialOffset > 0) {
      onProgress?.call(initialOffset, totalBytes);
    }

    final request = http.StreamedRequest('PATCH', tusUrl)
      ..headers.addAll(headers)
      ..headers['Upload-Offset'] = initialOffset.toString()
      ..headers['Content-Type'] = 'application/offset+octet-stream'
      ..contentLength = totalBytes - initialOffset;

    final completer = Completer<void>();
    var sentBytes = initialOffset;
    final subscription = mp4.openRead(initialOffset).listen(
      (chunk) {
        request.sink.add(chunk);
        sentBytes += chunk.length;
        onProgress?.call(sentBytes, totalBytes);
      },
      onError: (Object error, StackTrace stackTrace) {
        request.sink.close();
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
      onDone: () {
        request.sink.close();
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      cancelOnError: true,
    );

    http.StreamedResponse response;
    try {
      final responseFuture = _client.send(request).timeout(_httpTimeout);
      await completer.future;
      response = await responseFuture;
    } finally {
      await subscription.cancel();
    }

    await response.stream.drain();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Mux tus upload failed: ${response.statusCode} ${response.reasonPhrase}',
        uri: tusUrl,
      );
    }

    final offsetHeader = response.headers['upload-offset'];
    final reportedOffset = offsetHeader != null ? int.tryParse(offsetHeader) : null;
    return reportedOffset ?? sentBytes;
  }

  Future<int> _fetchTusOffset(Uri tusUrl, Map<String, String> headers) async {
    final merged = Map<String, String>.from(headers);
    merged['Tus-Resumable'] = _kTusResumableVersion;

    http.Response response;
    try {
      response = await _client
          .head(tusUrl, headers: merged)
          .timeout(_httpTimeout);
    } on SocketException {
      return 0;
    }

    if (response.statusCode == 404 || response.statusCode == 405) {
      return 0;
    }

    if (response.statusCode >= 400) {
      throw HttpException(
        'Failed to query tus upload offset: ${response.statusCode} ${response.reasonPhrase}',
        uri: tusUrl,
      );
    }

    final offsetHeader = response.headers['upload-offset'];
    return offsetHeader != null ? int.tryParse(offsetHeader) ?? 0 : 0;
  }

  Map<String, String> _mergeTusHeaders(Map<String, String> base) {
    final merged = Map<String, String>.from(base);
    merged['Tus-Resumable'] = _kTusResumableVersion;
    return merged;
  }

  Uri _ensureTrailingSlash(Uri uri) {
    if (uri.path.endsWith('/')) {
      return uri;
    }
    final path = uri.path.isEmpty ? '/' : '${uri.path}/';
    return uri.replace(path: path);
  }
}
