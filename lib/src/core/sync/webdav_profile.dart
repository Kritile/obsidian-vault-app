import 'webdav_client.dart';

class WebDavProfile {
  const WebDavProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.username,
    required this.password,
    this.lastSyncAt,
  });

  final String id;
  final String name;
  final Uri baseUrl;
  final String username;
  final String password;
  final DateTime? lastSyncAt;

  WebDavCredentials get credentials => WebDavCredentials(
    baseUrl: baseUrl,
    username: username,
    password: password,
  );

  WebDavProfile copyWith({
    String? name,
    Uri? baseUrl,
    String? username,
    String? password,
    DateTime? lastSyncAt,
  }) => WebDavProfile(
    id: id,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    username: username ?? this.username,
    password: password ?? this.password,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl.toString(),
    'username': username,
    'password': password,
    if (lastSyncAt != null) 'lastSyncAt': lastSyncAt!.toIso8601String(),
  };

  factory WebDavProfile.fromJson(Map<String, Object?> json) => WebDavProfile(
    id: json['id']!.toString(),
    name: json['name']!.toString(),
    baseUrl: Uri.parse(json['baseUrl']!.toString()),
    username: json['username']!.toString(),
    password: json['password']!.toString(),
    lastSyncAt: DateTime.tryParse(json['lastSyncAt']?.toString() ?? ''),
  );
}
