import 'dart:convert';

import 'package:http/http.dart'
as http;

import 'app_config.dart';

import '../models/privacy_event.dart';



class ApiClient{


Future<Map<String,dynamic>?> analyze(

PrivacyEvent event

)

async{


try{


final response=

await http.post(


Uri.parse(

"${AppConfig.backendUrl}/analyze"

),


headers:{

"Content-Type":

"application/json"

},


body:

jsonEncode(

event.toJson()

)

);



if(response.statusCode==200){


return jsonDecode(response.body);


}


return null;


}


catch(e){


return null;


}



}



}