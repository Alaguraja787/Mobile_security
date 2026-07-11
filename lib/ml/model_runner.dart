import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'package:onnxruntime/onnxruntime.dart';


class ModelRunner {


  late OrtSession _session;


  bool loaded = false;



  Future<void> loadModel() async {


    if (loaded) return;


    OrtEnv.instance.init();


    final rawAssetFile =
        await rootBundle.load(
            "assets/models/privacy_guardian.onnx"
        );


    final bytes =
        rawAssetFile.buffer.asUint8List();



    final sessionOptions =
        OrtSessionOptions();



    _session =
        OrtSession.fromBuffer(
            bytes,
            sessionOptions
        );


    loaded = true;


  }




  Future<double> predict(

      List<double> features

      ) async {


    await loadModel();



    final modelInput =
        List<double>.filled(
            196,
            0.0
        );



    for(int i=0;i<features.length;i++){

      modelInput[i]=features[i];

    }



    final inputOrt =
        OrtValueTensor.createTensorWithDataList(

            Float32List.fromList(modelInput),

            [1,196]

        );



    final outputs =
        _session.run(

            OrtRunOptions(),

            {

              "float_input": inputOrt

            }

        );



    final result =
        outputs[0]?.value;



    print(
      "RAW AI OUTPUT => $result"
    );



    double riskScore = 0;



    // classification output handling

    if(result.toString().contains("1")){


      // calculate custom percentage from features

      double score = 0;


      for(final f in features){

        score += f;

      }


      riskScore =
          (score * 15)
              .clamp(
                10,
                100
              )
              .toDouble();


    }

    else{


      riskScore = 10;


    }



    inputOrt.release();


    for(final e in outputs){

      e?.release();

    }



    return riskScore;


  }


}