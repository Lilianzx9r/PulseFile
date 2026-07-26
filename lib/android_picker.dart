// lib/android_picker.dart
//
// Gère le sélecteur PulseFile dédié pour apps tierces sous Android
// (ACTION_PICK_FOLDER / ACTION_PICK_FILE, lancé via startActivityForResult
// par une autre app — voir MainActivity.kt). Équivalent Android de
// `pulsefile.exe pick-folder/pick-file` côté Windows (voir cli.dart).
//
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'widgets/local_folder_picker.dart';
import 'widgets/local_file_picker.dart';

const _pickerChannel = MethodChannel('com.pulsefile/picker');

/// Vérifie si l'app a été lancée par une app tierce pour lui fournir un
/// chemin choisi par l'utilisateur. Retourne la requête si oui (à passer à
/// [AndroidPickerApp]), null sinon — auquel cas l'app doit démarrer
/// normalement.
Future<Map<String, dynamic>?> checkPendingPicker() async {
  if (!Platform.isAndroid) return null;
  try {
    final result = await _pickerChannel.invokeMethod('getPendingPicker');
    if (result == null) return null;
    return Map<String, dynamic>.from(result as Map);
  } catch (_) {
    return null;
  }
}

/// App minimale affichée quand PulseFile est lancé en mode "sélecteur pour
/// app tierce" : pousse directement le picker concerné, puis renvoie le
/// résultat à l'app appelante via setResult()/finish() (côté natif).
class AndroidPickerApp extends StatelessWidget {
  final Map<String, dynamic> request;
  const AndroidPickerApp({super.key, required this.request});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3D7CF4)),
        useMaterial3: true,
      ),
      home: _AndroidPickerHost(request: request),
    );
  }
}

class _AndroidPickerHost extends StatefulWidget {
  final Map<String, dynamic> request;
  const _AndroidPickerHost({required this.request});

  @override
  State<_AndroidPickerHost> createState() => _AndroidPickerHostState();
}

class _AndroidPickerHostState extends State<_AndroidPickerHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final type  = widget.request['type'] as String?;
    final start = widget.request['start'] as String?;
    dynamic result;

    if (type == 'folder') {
      result = await Navigator.push<String>(context, MaterialPageRoute(
          builder: (_) => LocalFolderPickerScreen(initialPath: start)));
    } else {
      final multiple = widget.request['multiple'] == true;
      result = await Navigator.push<List<String>>(context, MaterialPageRoute(
          builder: (_) => LocalFilePickerScreen(
              initialPath: start, allowMultiple: multiple)));
    }

    if (result == null) {
      await _pickerChannel.invokeMethod('returnResult', {'ok': false});
    } else if (result is String) {
      await _pickerChannel.invokeMethod('returnResult', {'ok': true, 'path': result});
    } else if (result is List<String>) {
      if (result.isEmpty) {
        await _pickerChannel.invokeMethod('returnResult', {'ok': false});
      } else {
        await _pickerChannel.invokeMethod('returnResult', {'ok': true, 'paths': result});
      }
    }
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}
