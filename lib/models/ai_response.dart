class AIResponse{


final int risk;

final String message;

final String action;


AIResponse({

required this.risk,

required this.message,

required this.action

});


factory AIResponse.fromJson(Map data){

return AIResponse(

risk:data["risk"],

message:data["message"],

action:data["action"]

);

}


}