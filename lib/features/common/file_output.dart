import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'widgets.dart';

/// Saving generated documents, and offering to open them afterwards.
///
/// The clinic's whole point of contact with a report is the file it ends up
/// with, so the save dialog is the platform's own and the success message
/// names the path.
class FileOutput {
  /// Asks where to put [bytes] and writes them there.
  ///
  /// Returns the file, or null if the user cancelled.
  static Future<File?> savePdf(
    BuildContext context, {
    required Uint8List bytes,
    required String suggestedName,
    String successMessage = 'Report saved',
  }) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PDF document', extensions: ['pdf']),
      ],
    );
    if (location == null) return null;

    final path = location.path.toLowerCase().endsWith('.pdf')
        ? location.path
        : '${location.path}.pdf';
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);

    if (context.mounted) {
      _announce(context, successMessage, file);
    }
    return file;
  }

  /// Writes arbitrary text, used by the backup export.
  static Future<File?> saveFile(
    BuildContext context, {
    required Future<File> Function(String path) write,
    required String suggestedName,
    required String typeLabel,
    required String extension,
    String successMessage = 'Saved',
  }) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [
        XTypeGroup(label: typeLabel, extensions: [extension]),
      ],
    );
    if (location == null) return null;

    final path = location.path.toLowerCase().endsWith('.$extension')
        ? location.path
        : '${location.path}.$extension';
    final file = await write(path);
    if (context.mounted) _announce(context, successMessage, file);
    return file;
  }

  /// Asks for an existing file, used by the backup restore.
  static Future<XFile?> pickFile({
    required String typeLabel,
    required String extension,
  }) =>
      openFile(
        acceptedTypeGroups: [
          XTypeGroup(label: typeLabel, extensions: [extension]),
        ],
      );

  static void _announce(BuildContext context, String message, File file) {
    displayInfoBar(
      context,
      duration: const Duration(seconds: 8),
      builder: (context, close) => InfoBar(
        title: Text(message),
        content: Text(file.path),
        severity: InfoBarSeverity.success,
        isLong: true,
        onClose: close,
        action: Button(
          onPressed: () => open(file),
          child: const Text('Open'),
        ),
      ),
    );
  }

  /// Hands the file to whatever the desktop uses to view it.
  static Future<void> open(File file) async {
    final uri = Uri.file(file.path);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  /// Reveals the containing folder, for when a viewer is not installed.
  static Future<void> revealFolder(File file) async {
    final uri = Uri.file(file.parent.path);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}

/// Convenience wrapper so pages can report a failure the same way everywhere.
Future<void> guarded(
  BuildContext context,
  Future<void> Function() action, {
  String failureTitle = 'That did not work',
}) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) {
      notify(
        context,
        '$e',
        title: failureTitle,
        severity: InfoBarSeverity.error,
      );
    }
  }
}
