/// Represents diagnostic verification metadata for a single telemetry field.
/// Used for development-only telemetry inspection and honest platform verification.
class TelemetryDiagnosticItem {
  final String field;
  final String value;
  final String sourceApi;
  final String scope;
  final String collectionType;
  final String availability;
  final String limitation;

  TelemetryDiagnosticItem({
    required this.field,
    required this.value,
    required this.sourceApi,
    required this.scope,
    required this.collectionType,
    required this.availability,
    required this.limitation,
  });

  factory TelemetryDiagnosticItem.fromMap(Map<dynamic, dynamic> map) {
    return TelemetryDiagnosticItem(
      field: map["field"]?.toString() ?? "",
      value: map["value"]?.toString() ?? "",
      sourceApi: map["sourceApi"]?.toString() ?? "",
      scope: map["scope"]?.toString() ?? "DEVICE",
      collectionType: map["collectionType"]?.toString() ?? "PERIODIC_SNAPSHOT",
      availability: map["availability"]?.toString() ?? "UNKNOWN",
      limitation: map["limitation"]?.toString() ?? "",
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "field": field,
      "value": value,
      "sourceApi": sourceApi,
      "scope": scope,
      "collectionType": collectionType,
      "availability": availability,
      "limitation": limitation,
    };
  }
}
