import 'threat_type.dart';

class Threat {

  final ThreatType type;

  final String title;

  final String description;

  final int severity;

  const Threat({

    required this.type,

    required this.title,

    required this.description,

    required this.severity,

  });

}