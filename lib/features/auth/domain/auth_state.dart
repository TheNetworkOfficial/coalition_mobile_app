import 'package:equatable/equatable.dart';

import 'app_user.dart';

class AuthState extends Equatable {
  const AuthState({this.user, this.errorMessage, this.isLoading = false});

  final AppUser? user;
  final String? errorMessage;
  final bool isLoading;

  AuthState copyWith({
    AppUser? user,
    String? errorMessage,
    bool? isLoading,
    bool clearError = false,
  }) {
    return AuthState(
      user: user ?? this.user,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [user, errorMessage, isLoading];
}
