import '../models/privacy_event.dart';


class FeatureEncoder {


List<double> encode(

PrivacyEvent event

){


final permissions =

event.permissions.join(" ").toUpperCase();




double camera =

permissions.contains("CAMERA")

? 1

: 0;



double microphone =

permissions.contains("RECORD_AUDIO")

? 1

: 0;




double contacts =

permissions.contains("CONTACTS")

? 1

: 0;




double location =

permissions.contains("LOCATION")

? 1

: 0;




double storage =

permissions.contains("STORAGE")

? 1

: 0;




double sms =

permissions.contains("SMS")

? 1

: 0;




double permissionCount =

event.permissions.length.toDouble();



double network =

event.uploadBytes / 1000000;




return [

camera,

microphone,

contacts,

location,

storage,

sms,

permissionCount,

network

];


}


}