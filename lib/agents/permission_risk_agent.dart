class PermissionRiskAgent {

  static const Map<String, int> permissionWeights = {

    "CAMERA": 20,

    "RECORD_AUDIO": 20,

    "READ_CONTACTS": 15,

    "WRITE_CONTACTS": 15,

    "ACCESS_FINE_LOCATION": 15,

    "ACCESS_COARSE_LOCATION": 10,

    "READ_SMS": 25,

    "SEND_SMS": 30,

    "READ_CALL_LOG": 25,

    "SYSTEM_ALERT_WINDOW": 30,

    "PACKAGE_USAGE_STATS": 25,

  };

  int calculateRisk(List<String> permissions) {

    int score = 0;

    for (final permission in permissions) {

      score += permissionWeights[permission] ?? 0;

    }

    return score;

  }

}