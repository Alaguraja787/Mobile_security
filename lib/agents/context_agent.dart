class ContextAgent{


bool isPermissionSuspicious(

String permission,

String category

){



if(
category=="UTILITY" &&
permission=="CONTACTS"
){

return true;

}



if(
category=="CALCULATOR" &&
permission=="LOCATION"
){

return true;

}



return false;


}



}