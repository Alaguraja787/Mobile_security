class DecisionAgent{


String decide(

int risk

){


if(risk>=75){

return "BLOCK";

}



if(risk>=40){

return "WARN";

}



return "ALLOW";


}


}