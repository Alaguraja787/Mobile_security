class AppInfo{

final String name;

final String package;

final List<String> permissions;


AppInfo({

required this.name,

required this.package,

required this.permissions

});


factory AppInfo.fromJson(Map data){

return AppInfo(

name:data["name"],

package:data["package"],

permissions:
List<String>.from(data["permissions"])

);

}

}