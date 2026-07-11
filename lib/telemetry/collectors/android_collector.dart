import 'package:flutter/services.dart';

class AndroidCollector {

  static const MethodChannel _channel =
      MethodChannel(
        "privacy_sentinel/telemetry",
      );


  Future<Map<String, dynamic>> collectTelemetry() async {

    try {

      final result =
          await _channel.invokeMethod(
            "collectTelemetry",
          );


      return Map<String, dynamic>.from(
        result,
      );

    }

    catch(e){

      return {
        "error": e.toString()
      };

    }

  }

}