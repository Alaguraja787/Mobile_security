import 'dart:async';


import 'collectors/android_collector.dart';


import '../models/privacy_event.dart';



class TelemetryService {


final AndroidCollector collector =

AndroidCollector();



final StreamController<PrivacyEvent>

_controller =

StreamController.broadcast();




Stream<PrivacyEvent>

get stream => _controller.stream;



Timer? timer;




void start(){



timer =

Timer.periodic(


const Duration(seconds:5),


(t)

async{



final data =

await collector.collectTelemetry();




if(data!=null){



final event =

PrivacyEvent.fromMap(data);



_controller.add(event);



}



}


);



}



void stop(){


timer?.cancel();


_controller.close();



}



}