import 'package:flutter_test/flutter_test.dart';
import 'package:local_retrieval_system/embedding/model_manager.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MobileCLIP Text Model Info', () {
    test('Print model input/output information', () async {
      await TFLiteModelManager.instance.initialize();

      final Interpreter interpreter =
          TFLiteModelManager.instance.mobileClipTextInterpreter;

      print('');
      print('==============================');
      print('MOBILECLIP TEXT MODEL INFO');
      print('==============================');

      print('Input Tensor Count: ${interpreter.getInputTensors().length}');
      print('Output Tensor Count: ${interpreter.getOutputTensors().length}');
      print('');

      print('========== INPUT ==========');

      for (int i = 0; i < interpreter.getInputTensors().length; i++) {
        final tensor = interpreter.getInputTensor(i);

        print('Input[$i]');
        print('Name  : ${tensor.name}');
        print('Shape : ${tensor.shape}');
        print('Type  : ${tensor.type}');
        print('--------------------------');
      }

      print('');

      print('========== OUTPUT ==========');

      for (int i = 0; i < interpreter.getOutputTensors().length; i++) {
        final tensor = interpreter.getOutputTensor(i);

        print('Output[$i]');
        print('Name  : ${tensor.name}');
        print('Shape : ${tensor.shape}');
        print('Type  : ${tensor.type}');
        print('--------------------------');
      }

      print('');

      expect(interpreter.getInputTensors().isNotEmpty, true);
      expect(interpreter.getOutputTensors().isNotEmpty, true);

      TFLiteModelManager.instance.dispose();
    });
  });
}