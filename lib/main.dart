import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';

// ======================================================
// FUNCIONES EN ISOLATES
// ======================================================

Future<String> generateCsvTask(String directoryPath) async {
  final random = Random();
  final csv = StringBuffer();

  csv.writeln('timestamp,temperatura');

  for (int i = 0; i < 100; i++) {
    final timestamp = DateTime.now().toIso8601String();
    final temperature = (18 + random.nextDouble() * 17).toStringAsFixed(2);

    csv.writeln('$timestamp,$temperature');
  }

  final content = csv.toString();

  final csvFile = File('$directoryPath/sensor_log.csv');
  final hashFile = File('$directoryPath/sensor_log.sha256');

  await csvFile.writeAsString(content, flush: true);

  final hash = sha256.convert(utf8.encode(content)).toString();

  await hashFile.writeAsString(hash, flush: true);

  return csvFile.path;
}

Future<bool> validateCsvTask(String directoryPath) async {
  final csvFile = File('$directoryPath/sensor_log.csv');
  final hashFile = File('$directoryPath/sensor_log.sha256');

  if (!await csvFile.exists()) {
    throw FileSystemException('No existe sensor_log.csv');
  }

  if (!await hashFile.exists()) {
    throw FileSystemException('No existe sensor_log.sha256');
  }

  final content = await csvFile.readAsString();
  final originalHash = (await hashFile.readAsString()).trim();

  final calculatedHash = sha256.convert(utf8.encode(content)).toString();

  return originalHash == calculatedHash;
}

Future<void> savePreferencesTask(Map<String, dynamic> data) async {
  final file = File(data['path'] as String);

  await file.writeAsString(jsonEncode(data['preferences']), flush: true);
}

Future<Map<String, dynamic>?> readPreferencesTask(String path) async {
  final file = File(path);

  if (!await file.exists()) {
    return null;
  }

  final content = await file.readAsString();

  return jsonDecode(content) as Map<String, dynamic>;
}

// ======================================================
// MAIN
// ======================================================

void main() {
  runApp(const SensorApp());
}

// ======================================================
// APLICACIÓN
// ======================================================

class SensorApp extends StatefulWidget {
  const SensorApp({super.key});

  @override
  State<SensorApp> createState() => _SensorAppState();
}

class _SensorAppState extends State<SensorApp> {
  final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  ThemeMode themeMode = ThemeMode.light;

  int samplingInterval = 5;

  String? directoryPath;

  bool isLoading = true;
  bool isGenerating = false;
  bool isValidating = false;

  bool? integrityResult;

  @override
  void initState() {
    super.initState();
    loadPreferences();
  }

  // ====================================================
  // MENSAJES
  // ====================================================

  void showMessage(String message, {bool error = false}) {
    debugPrint(message);

    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ====================================================
  // OBTENER DIRECTORIO
  // ====================================================

  Future<String> getStoragePath() async {
    if (directoryPath != null) {
      return directoryPath!;
    }

    final directory = await getApplicationDocumentsDirectory();

    directoryPath = directory.path;

    debugPrint('Directorio de almacenamiento: $directoryPath');

    return directoryPath!;
  }

  // ====================================================
  // CARGAR PREFERENCIAS
  // ====================================================

  Future<void> loadPreferences() async {
    try {
      final path = await getStoragePath();

      final preferences = await compute(
        readPreferencesTask,
        '$path/preferences.json',
      );

      if (preferences != null && mounted) {
        setState(() {
          themeMode = preferences['darkMode'] == true
              ? ThemeMode.dark
              : ThemeMode.light;

          samplingInterval =
              (preferences['samplingInterval'] as num?)?.toInt() ?? 5;

          samplingInterval = samplingInterval.clamp(1, 60);
        });
      }

      debugPrint('Preferencias cargadas correctamente.');
    } catch (e, stackTrace) {
      debugPrint('ERROR CARGANDO PREFERENCIAS: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        showMessage('Error al cargar preferencias: $e', error: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // ====================================================
  // GUARDAR PREFERENCIAS
  // ====================================================

  Future<void> savePreferences() async {
    try {
      final path = await getStoragePath();

      final preferences = {
        'darkMode': themeMode == ThemeMode.dark,
        'samplingInterval': samplingInterval,
      };

      await compute(savePreferencesTask, {
        'path': '$path${Platform.pathSeparator}preferences.json',
        'preferences': preferences,
      });

      debugPrint('Preferencias guardadas correctamente.');
    } on FileSystemException catch (e) {
      showMessage('Error de archivos: ${e.message}', error: true);
    } catch (e, stackTrace) {
      debugPrint('ERROR GUARDANDO PREFERENCIAS: $e');
      debugPrintStack(stackTrace: stackTrace);

      showMessage('Error al guardar preferencias: $e', error: true);
    }
  }

  void changeTheme(bool value) {
    setState(() {
      themeMode = value ? ThemeMode.dark : ThemeMode.light;
    });

    savePreferences();
  }

  void changeSamplingInterval(double value) {
    setState(() {
      samplingInterval = value.round();
    });

    savePreferences();
  }

  // ====================================================
  // GENERAR CSV
  // ====================================================

  Future<void> generateCsv() async {
    if (isGenerating) return;

    setState(() {
      isGenerating = true;
      integrityResult = null;
    });

    showMessage('Iniciando generación del archivo CSV...');

    try {
      final path = await getStoragePath();

      debugPrint('Generando CSV en: $path');

      final csvPath = await compute(generateCsvTask, path);

      if (!mounted) return;

      showMessage('CSV generado correctamente.');

      debugPrint('ARCHIVO CREADO: $csvPath');
      debugPrint(
        'FIRMA SHA-256: $path${Platform.pathSeparator}sensor_log.sha256',
      );
    } on FileSystemException catch (e) {
      debugPrint('ERROR DE ARCHIVOS: $e');
      showMessage('Error al generar CSV: ${e.message}', error: true);
    } catch (e, stackTrace) {
      debugPrint('ERROR GENERANDO CSV: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        showMessage('Error inesperado: $e', error: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          isGenerating = false;
        });
      }
    }
  }

  // ====================================================
  // VALIDAR INTEGRIDAD
  // ====================================================

  Future<void> validateIntegrity() async {
    if (isValidating) return;

    setState(() {
      isValidating = true;
      integrityResult = null;
    });

    showMessage('Verificando integridad del archivo...');

    try {
      final path = await getStoragePath();

      final result = await compute(validateCsvTask, path);

      if (!mounted) return;

      setState(() {
        integrityResult = result;
      });

      if (result) {
        showMessage('El archivo es válido. SHA-256 coincide.');
      } else {
        showMessage('¡El archivo fue alterado!', error: true);
      }
    } on FileSystemException catch (e) {
      showMessage('Error de archivos: ${e.message}', error: true);
    } catch (e, stackTrace) {
      debugPrint('ERROR VALIDANDO CSV: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        showMessage('Error al validar: $e', error: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          isValidating = false;
        });
      }
    }
  }

  // ====================================================
  // INTERFAZ
  // ====================================================

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: messengerKey,
      title: 'IoT Sensor Manager',
      themeMode: themeMode,

      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
      ),

      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
      ),

      home: Scaffold(
        appBar: AppBar(
          title: const Text('IoT Sensor Manager'),
          centerTitle: true,
        ),

        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Configuración del usuario',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 15),

                    Card(
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: const Text('Tema oscuro'),
                            subtitle: const Text(
                              'Guardar preferencia de apariencia',
                            ),
                            secondary: const Icon(Icons.dark_mode),
                            value: themeMode == ThemeMode.dark,
                            onChanged: changeTheme,
                          ),

                          const Divider(),

                          ListTile(
                            leading: const Icon(Icons.timer),
                            title: const Text('Intervalo de muestreo IoT'),
                            subtitle: Text('$samplingInterval segundos'),
                          ),

                          Slider(
                            value: samplingInterval.toDouble(),
                            min: 1,
                            max: 60,
                            divisions: 59,
                            label: '$samplingInterval segundos',
                            onChanged: changeSamplingInterval,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 25),

                    const Text(
                      'Registro de sensores',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 15),

                    ElevatedButton.icon(
                      onPressed: isGenerating ? null : generateCsv,
                      icon: isGenerating
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.file_download),
                      label: Text(
                        isGenerating
                            ? 'Generando archivo...'
                            : 'Generar Log de Sensores (CSV)',
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(18),
                      ),
                    ),

                    const SizedBox(height: 12),

                    ElevatedButton.icon(
                      onPressed: isValidating ? null : validateIntegrity,
                      icon: isValidating
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.verified_user),
                      label: Text(
                        isValidating
                            ? 'Validando integridad...'
                            : 'Validar Integridad Log',
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(18),
                      ),
                    ),

                    const SizedBox(height: 25),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            const Text(
                              'Estado de integridad SHA-256',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 15),

                            Icon(
                              integrityResult == null
                                  ? Icons.help_outline
                                  : integrityResult!
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              color: integrityResult == null
                                  ? Colors.grey
                                  : integrityResult!
                                  ? Colors.green
                                  : Colors.red,
                              size: 65,
                            ),

                            const SizedBox(height: 10),

                            Text(
                              integrityResult == null
                                  ? 'Esperando validación'
                                  : integrityResult!
                                  ? 'Archivo válido'
                                  : 'Archivo alterado o inválido',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: integrityResult == null
                                    ? Colors.grey
                                    : integrityResult!
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Información del sistema',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),

                            const SizedBox(height: 10),

                            Text('Lecturas: 100'),
                            const Text('Formato: CSV'),
                            const Text('Algoritmo: SHA-256'),

                            Text('Intervalo: $samplingInterval segundos'),

                            const SizedBox(height: 8),

                            SelectableText(
                              'Directorio: ${directoryPath ?? "No disponible"}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
