import 'package:flutter/material.dart';


import '../../telemetry/telemetry_service.dart';

import '../../agents/local_guardian_agent.dart';


import '../../models/privacy_event.dart';

import '../../models/risk_assessment.dart';


import '../../widgets/risk_card.dart';



class DashboardScreen extends StatefulWidget{


const DashboardScreen({super.key});


@override

State<DashboardScreen>

createState()=>_DashboardScreenState();


}





class _DashboardScreenState

extends State<DashboardScreen>{



final TelemetryService telemetry=

TelemetryService();



final LocalGuardianAgent guardian=

LocalGuardianAgent();



List<Map<String,dynamic>>

events=[];




@override

void initState(){


super.initState();



telemetry.start();




telemetry.stream.listen(

(event)

async{



RiskAssessment risk =

await guardian.analyze(event);



setState((){


events.insert(

0,

{

"event":event,

"risk":risk

}

);


});


}


);


}



@override

Widget build(BuildContext context){



return Scaffold(


appBar:

AppBar(

title:

const Text(

"Privacy Sentinel AI"

)

),



body:


events.isEmpty


?


const Center(

child:

Text(

"Monitoring device..."

)

)



:


ListView.builder(

itemCount:

events.length,

itemBuilder:

(context,index){



return RiskCard(


event:

events[index]["event"],


risk:

events[index]["risk"]



);



}


),



);


}



}