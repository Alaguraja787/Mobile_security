import 'package:flutter/material.dart';

import '../models/privacy_event.dart';

import '../models/risk_assessment.dart';



class RiskCard extends StatelessWidget{


final PrivacyEvent event;


final RiskAssessment risk;




const RiskCard({

super.key,

required this.event,

required this.risk

});



@override

Widget build(BuildContext context){



Color color =

risk.score>70

?

Colors.red

:

Colors.green;




return Card(

child:

ListTile(

leading:

Icon(

Icons.security,

color:color

),



title:

Text(event.appName),



subtitle:

Text(

"${event.permissions.isEmpty ? "NO PERMISSIONS" : event.permissions.join(", ")}\n${risk.reason}"

),




trailing:

Text(

"${risk.score}%",

style:

TextStyle(

color:color,

fontSize:20

),

),


),


);



}



}