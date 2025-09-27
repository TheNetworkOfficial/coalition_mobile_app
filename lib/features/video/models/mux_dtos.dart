class CreateMuxUploadRequest {
  final String filename;
  final int filesize;
  final String contentType;
  final bool preferTus;

  CreateMuxUploadRequest({
    required this.filename,
    required this.filesize,
    required this.contentType,
    this.preferTus = true,
  });

  Map<String, dynamic> toJson() => {
        'filename': filename,
        'filesize': filesize,
        'content_type': contentType,
        'prefer_tus': preferTus,
      };
}

class CreateMuxUploadResponse {
  final String uploadId;
  final String? method;
  final String? url;
  final Map<String, dynamic>? tus;

  CreateMuxUploadResponse({
    required this.uploadId,
    this.method,
    this.url,
    this.tus,
  });

  factory CreateMuxUploadResponse.fromJson(Map<String, dynamic> json) {
    return CreateMuxUploadResponse(
      uploadId: json['upload_id'] as String,
      method: json['method'] as String?,
      url: json['url'] as String?,
      tus: json['tus'] != null
          ? Map<String, dynamic>.from(json['tus'] as Map)
          : null,
    );
  }
}
