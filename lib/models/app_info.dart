class AppInfo {
  final String name;
  final String package;
  final bool isSystemApp;
  final bool isEnabled;
  final int uid;
  final String versionName;
  final int versionCode;
  final List<String> permissions;
  final List<String> grantedPermissions;
  final List<String> dangerousPermissions;

  AppInfo({
    required this.name,
    required this.package,
    this.isSystemApp = false,
    this.isEnabled = true,
    this.uid = -1,
    this.versionName = "",
    this.versionCode = 0,
    required this.permissions,
    this.grantedPermissions = const [],
    this.dangerousPermissions = const [],
  });

  factory AppInfo.fromJson(Map<dynamic, dynamic> data) {
    return AppInfo(
      name: data["appName"]?.toString() ?? data["name"]?.toString() ?? "",
      package:
          data["packageName"]?.toString() ?? data["package"]?.toString() ?? "",
      isSystemApp: data["isSystemApp"] == true,
      isEnabled: data["isEnabled"] != false,
      uid: (data["uid"] as num?)?.toInt() ?? -1,
      versionName: data["versionName"]?.toString() ?? "",
      versionCode: (data["versionCode"] as num?)?.toInt() ?? 0,
      permissions: List<String>.from(
          data["requestedPermissions"] ?? data["permissions"] ?? []),
      grantedPermissions: List<String>.from(data["grantedPermissions"] ?? []),
      dangerousPermissions:
          List<String>.from(data["dangerousPermissions"] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "name": name,
      "package": package,
      "isSystemApp": isSystemApp,
      "isEnabled": isEnabled,
      "uid": uid,
      "versionName": versionName,
      "versionCode": versionCode,
      "permissions": permissions,
      "grantedPermissions": grantedPermissions,
      "dangerousPermissions": dangerousPermissions,
    };
  }
}