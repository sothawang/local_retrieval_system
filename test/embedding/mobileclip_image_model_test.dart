import 'package:flutter_test/flutter_test.dart';
import 'package:local_retrieval_system/embedding/model_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Inspect MobileCLIP TFLite model', () async {
    final manager = TFLiteModelManager.instance;

    await manager.initializeMobileClip();

    final interpreter = manager.mobileClipImageInterpreter;

    print('==============================');
    print('MOBILECLIP MODEL INFO');
    print('==============================');

    print('Input Tensor Count: ${interpreter.getInputTensors().length}');
    print('Output Tensor Count: ${interpreter.getOutputTensors().length}');

    print('\n========== INPUT ==========');

    for (int i = 0; i < interpreter.getInputTensors().length; i++) {
      final tensor = interpreter.getInputTensors()[i];

      print('Input[$i]');
      print('Name  : ${tensor.name}');
      print('Shape : ${tensor.shape}');
      print('Type  : ${tensor.type}');
      print('--------------------------');
    }

    print('\n========== OUTPUT ==========');

    for (int i = 0; i < interpreter.getOutputTensors().length; i++) {
      final tensor = interpreter.getOutputTensors()[i];

      print('Output[$i]');
      print('Name  : ${tensor.name}');
      print('Shape : ${tensor.shape}');
      print('Type  : ${tensor.type}');
      print('--------------------------');
    }

    manager.disposeMobileClip();
  });
}