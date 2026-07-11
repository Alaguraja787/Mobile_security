class RiskAssessment {

  final int score;

  final String level;

  final String reason;


  RiskAssessment({

    required this.score,

    required this.level,

    required this.reason,

  });


  Map<String,dynamic> toJson(){

    return {

      "score":score,

      "level":level,

      "reason":reason

    };

  }

}