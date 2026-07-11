import '../models/privacy_event.dart';

import '../ml/model_runner.dart';

import '../ml/feature_encoder.dart';



class RiskAgent{


final ModelRunner model=

ModelRunner();



final FeatureEncoder encoder=

FeatureEncoder();




Future<int> calculateRisk(

PrivacyEvent event

)

async{


final features=

encoder.encode(event);



final risk=

await model.predict(features);



return risk.toInt();


}


}