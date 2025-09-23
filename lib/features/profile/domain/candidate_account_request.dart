import 'package:equatable/equatable.dart';

enum CandidateAccountRequestStatus { pending, approved, denied }

class CandidateAccountRequest extends Equatable {
  const CandidateAccountRequest({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.campaignAddress,
    required this.fecNumber,
    required this.status,
    required this.submittedAt,
    this.reviewedAt,
    this.reviewedBy,
  });

  final String id;
  final String userId;
  final String fullName;
  final String phone;
  final String email;
  final String campaignAddress;
  final String fecNumber;
  final CandidateAccountRequestStatus status;
  final DateTime submittedAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;

  CandidateAccountRequest copyWith({
    String? id,
    String? userId,
    String? fullName,
    String? phone,
    String? email,
    String? campaignAddress,
    String? fecNumber,
    CandidateAccountRequestStatus? status,
    DateTime? submittedAt,
    DateTime? reviewedAt,
    String? reviewedBy,
  }) {
    return CandidateAccountRequest(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      campaignAddress: campaignAddress ?? this.campaignAddress,
      fecNumber: fecNumber ?? this.fecNumber,
      status: status ?? this.status,
      submittedAt: submittedAt ?? this.submittedAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewedBy: reviewedBy ?? this.reviewedBy,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'fullName': fullName,
        'phone': phone,
        'email': email,
        'campaignAddress': campaignAddress,
        'fecNumber': fecNumber,
        'status': status.name,
        'submittedAt': submittedAt.toIso8601String(),
        'reviewedAt': reviewedAt?.toIso8601String(),
        'reviewedBy': reviewedBy,
      };

  factory CandidateAccountRequest.fromJson(Map<String, dynamic> json) {
    return CandidateAccountRequest(
      id: json['id'] as String,
      userId: json['userId'] as String,
      fullName: json['fullName'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      campaignAddress: json['campaignAddress'] as String? ?? '',
      fecNumber: json['fecNumber'] as String? ?? '',
      status: _statusFromJson(json['status']),
      submittedAt: DateTime.tryParse(json['submittedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      reviewedAt: json['reviewedAt'] == null
          ? null
          : DateTime.tryParse(json['reviewedAt'] as String? ?? ''),
      reviewedBy: json['reviewedBy'] as String?,
    );
  }

  static CandidateAccountRequestStatus _statusFromJson(Object? value) {
    final raw = value?.toString();
    if (raw != null) {
      for (final status in CandidateAccountRequestStatus.values) {
        if (status.name == raw) {
          return status;
        }
      }
    }
    return CandidateAccountRequestStatus.pending;
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        fullName,
        phone,
        email,
        campaignAddress,
        fecNumber,
        status,
        submittedAt,
        reviewedAt,
        reviewedBy,
      ];
}
