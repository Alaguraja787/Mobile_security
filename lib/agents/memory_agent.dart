import 'package:shared_preferences/shared_preferences.dart';



class MemoryAgent{



Future<void> saveBehaviour(

String app,

String action

)

async{


final prefs=

await SharedPreferences.getInstance();



await prefs.setString(

app,

action

);


}




Future<String?>

getBehaviour(

String app

)

async{


final prefs=

await SharedPreferences.getInstance();


return prefs.getString(app);


}




}