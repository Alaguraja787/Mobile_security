import 'package:flutter/material.dart';

import 'screens/dashboard/dashboard_screen.dart';

import 'services/app_usage_service.dart';



void main() async {


  WidgetsFlutterBinding.ensureInitialized();



  try{


    final usage =

        await AppUsageService()
            .getUsage();



    print(
        "🔥 APP USAGE DATA 🔥"
    );


    print(
        usage
    );


  }

  catch(e){


    print(
        "Usage monitor error: $e"
    );


  }




  runApp(

      const PrivacySentinelApp()

  );


}




class PrivacySentinelApp extends StatelessWidget {


  const PrivacySentinelApp({super.key});



  @override

  Widget build(BuildContext context) {



    return MaterialApp(


      debugShowCheckedModeBanner:false,


      title:"Privacy Sentinel AI",


      theme:ThemeData(


        brightness:Brightness.dark,


        useMaterial3:true,


      ),



      home:


      const DashboardScreen(),



    );



  }


}