class PrivacyEvent {


final String appName;

final String packageName;

final List<String> permissions;


final bool isBackground;

final bool isScreenLocked;


final double uploadBytes;



PrivacyEvent({

required this.appName,

required this.packageName,

required this.permissions,

required this.isBackground,

required this.isScreenLocked,

required this.uploadBytes,

});




factory PrivacyEvent.fromMap(

Map<dynamic,dynamic> map

){


return PrivacyEvent(


appName:

map["appName"] ?? "Unknown App",



packageName:

map["packageName"] ?? "",



permissions:

List<String>.from(

map["permissions"] ?? []

),



isBackground:

map["background"] ?? false,



isScreenLocked:

map["locked"] ?? false,



uploadBytes:

(map["upload"] ?? 0).toDouble(),


);


}


}