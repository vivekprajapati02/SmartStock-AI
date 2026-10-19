import '../../core/utils/parse.dart';

enum UserRole {
  viewer(1),
  manager(2),
  admin(3),
  owner(4);

  const UserRole(this.rank);

  final int rank;

  static UserRole parse(String? value) => UserRole.values.firstWhere(
        (r) => r.name == value,
        orElse: () => UserRole.viewer,
      );

  bool atLeast(UserRole other) => rank >= other.rank;

  String get label => name[0].toUpperCase() + name.substring(1);
}

class User {
  const User({
    required this.id,
    required this.orgId,
    required this.email,
    this.fullName,
    required this.role,
    required this.isActive,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        orgId: json['org_id'] as String,
        email: json['email'] as String,
        fullName: json['full_name'] as String?,
        role: UserRole.parse(json['role'] as String?),
        isActive: json['is_active'] as bool? ?? true,
        createdAt: parseDateTime(json['created_at']),
      );

  final String id;
  final String orgId;
  final String email;
  final String? fullName;
  final UserRole role;
  final bool isActive;
  final DateTime createdAt;

  /// Catalogue and stock writes require `manager` or above on the backend.
  bool get canWrite => role.atLeast(UserRole.manager);

  String get displayName =>
      (fullName != null && fullName!.trim().isNotEmpty) ? fullName! : email;
}

class TokenPair {
  const TokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  factory TokenPair.fromJson(Map<String, dynamic> json) => TokenPair(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        expiresIn: parseInt(json['expires_in']),
      );

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
}

class AuthResponse {
  const AuthResponse({required this.user, required this.tokens});

  factory AuthResponse.fromJson(Map<String, dynamic> json) => AuthResponse(
        user: User.fromJson(json['user'] as Map<String, dynamic>),
        tokens: TokenPair.fromJson(json['tokens'] as Map<String, dynamic>),
      );

  final User user;
  final TokenPair tokens;
}
