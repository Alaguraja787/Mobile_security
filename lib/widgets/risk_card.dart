import 'package:flutter/material.dart';

import '../models/app_telemetry.dart';
import '../models/risk_assessment.dart';

class RiskCard extends StatelessWidget {

  final AppTelemetry app;

  final RiskAssessment risk;

  const RiskCard({

    super.key,

    required this.app,

    required this.risk,

  });

  @override
  Widget build(BuildContext context) {

    Color color =
        risk.score >= 80
            ? Colors.red
            : risk.score >= 50
                ? Colors.orange
                : Colors.green;

    return Card(

      margin: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),

      child: ListTile(

        leading: CircleAvatar(

          backgroundColor: color,

          child: const Icon(
            Icons.security,
            color: Colors.white,
          ),

        ),

        title: Text(

          app.appName,

          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),

        ),

        subtitle: Column(

          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [

            const SizedBox(height: 6),

            Text(
              "Package: ${app.packageName}",
            ),

            Text(
              "Permissions: ${app.permissions.isEmpty ? "None" : app.permissions.join(", ")}",
            ),

            Text(
              "Foreground: ${app.foregroundMinutes != null ? "${app.foregroundMinutes!.toStringAsFixed(1)} min" : "Unavailable"}",
            ),

            Text(
              "Active: ${app.isActive != null ? (app.isActive! ? "Yes" : "No") : "Unavailable"}",
            ),

            Text(
              risk.reason,
            ),

          ],

        ),

        trailing: Container(

          padding: const EdgeInsets.all(10),

          decoration: BoxDecoration(

            color: color,

            borderRadius:
                BorderRadius.circular(12),

          ),

          child: Text(

            "${risk.score}%",

            style: const TextStyle(

              color: Colors.white,

              fontWeight: FontWeight.bold,

            ),

          ),

        ),

      ),

    );

  }

}