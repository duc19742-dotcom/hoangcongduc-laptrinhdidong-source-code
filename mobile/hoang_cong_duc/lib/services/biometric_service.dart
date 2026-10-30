import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'api_service.dart';

class FingerprintService {
  static const channel = MethodChannel('duc_attendance/fingerprint');
  Future<bool> available() async =>
      await channel.invokeMethod<bool>('available') ?? false;
  Future<String> createKey(String alias) async =>
      (await channel.invokeMethod<String>('createKey', {'alias': alias}))!;
  Future<String> sign(String alias, String nonce) async {
    try {
      return (await channel.invokeMethod<String>('sign', {
        'alias': alias,
        'nonce': nonce,
      }))!;
    } on PlatformException catch (e) {
      throw ApiException(e.message ?? 'Không xác thực được vân tay.');
    }
  }

  Future<void> remove(String alias) async =>
      channel.invokeMethod('removeKey', {'alias': alias});
}

class FaceService {
  Future<List<double>?> capture() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 90,
    );
    if (photo == null) return null;
    final detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: true,
      ),
    );
    Interpreter? interpreter;
    try {
      final original = img.decodeImage(await photo.readAsBytes());
      if (original == null) throw const ApiException('Không đọc được ảnh.');
      final oriented = img.bakeOrientation(original);
      await File(photo.path).writeAsBytes(img.encodeJpg(oriented, quality: 95));
      final faces = await detector.processImage(
        InputImage.fromFilePath(photo.path),
      );
      if (faces.length != 1) {
        throw const ApiException(
          'Chụp đúng một khuôn mặt, không che mặt và đủ sáng.',
        );
      }
      final face = faces.single;
      if ((face.headEulerAngleY ?? 0).abs() > 15 ||
          (face.headEulerAngleZ ?? 0).abs() > 12 ||
          (face.headEulerAngleX ?? 0).abs() > 18 ||
          face.boundingBox.width < 80) {
        throw const ApiException(
          'Nhìn thẳng vào camera, giữ đầu ngay và tiến gần hơn.',
        );
      }
      final box = face.boundingBox;
      final x = max(0, (box.left - box.width * .06).floor());
      final y = max(0, (box.top - box.height * .03).floor());
      final width = min(oriented.width - x, (box.width * 1.12).ceil());
      final height = min(oriented.height - y, (box.height * 1.06).ceil());
      if (width <= 0 || height <= 0) {
        throw const ApiException('Khuôn mặt nằm ngoài ảnh. Hãy chụp lại.');
      }
      final crop = img.copyResize(
        img.copyCrop(oriented, x: x, y: y, width: width, height: height),
        width: 112,
        height: 112,
      );
      interpreter = await Interpreter.fromAsset(
        'assets/mobilefacenet.tflite',
        options: InterpreterOptions()..threads = 2,
      );
      final shape = interpreter.getInputTensor(0).shape;
      final outputShape = interpreter.getOutputTensor(0).shape;
      if (shape.length != 4 ||
          shape[1] != 112 ||
          shape[2] != 112 ||
          shape[3] != 3 ||
          outputShape.last != 192) {
        throw const ApiException('Mô hình khuôn mặt không tương thích.');
      }
      final pixels = List.generate(
        112,
        (y) => List.generate(112, (x) {
          final p = crop.getPixel(x, y);
          return [
            (p.r - 127.5) / 128,
            (p.g - 127.5) / 128,
            (p.b - 127.5) / 128,
          ];
        }),
      );
      final input = List.generate(shape[0], (_) => pixels);
      final output = List.generate(
        outputShape[0],
        (_) => List<double>.filled(192, 0),
      );
      interpreter.run(input, output);
      final values = output.first;
      final norm = sqrt(values.fold<double>(0, (n, v) => n + v * v));
      if (!norm.isFinite || norm < 1e-8) {
        throw const ApiException(
          'Không trích xuất được khuôn mặt. Hãy chụp lại.',
        );
      }
      return values.map((v) => v / norm).toList();
    } on PlatformException catch (e) {
      throw ApiException(
        e.message ?? 'Không mở được camera. Hãy kiểm tra quyền camera.',
      );
    } finally {
      interpreter?.close();
      await detector.close();
      try {
        await File(photo.path).delete();
      } on FileSystemException {
        /* Temporary capture already removed by Android. */
      }
    }
  }
}
