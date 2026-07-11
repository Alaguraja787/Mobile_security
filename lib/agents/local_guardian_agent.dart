import '../models/privacy_event.dart';
import '../models/risk_assessment.dart';


import 'risk_agent.dart';

import 'decision_agent.dart';



class LocalGuardianAgent{


final RiskAgent riskAgent =
RiskAgent();


final DecisionAgent decisionAgent =
DecisionAgent();




Future<RiskAssessment> analyze(

PrivacyEvent event

)

async{


int risk =

await riskAgent.calculateRisk(event);



String decision=

decisionAgent.decide(risk);




return RiskAssessment(


score:risk,


level:decision,


reason:

"AI model detected privacy risk score $risk"


);


}



}