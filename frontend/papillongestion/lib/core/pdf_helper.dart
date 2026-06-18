import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

/// Sauvegarde des octets PDF dans un fichier temporaire et l'ouvre avec le
/// lecteur PDF du système. Affiche un retour via SnackBar.
Future<void> ouvrirPdf(BuildContext context, List<int>? bytes, String filename) async {
  final messenger = ScaffoldMessenger.of(context);
  if (bytes == null || bytes.isEmpty) {
    messenger.showSnackBar(const SnackBar(
      content: Text('Erreur lors de la génération du document'),
      backgroundColor: Colors.red,
    ));
    return;
  }
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    final res = await OpenFilex.open(file.path);
    if (res.type != ResultType.done) {
      messenger.showSnackBar(SnackBar(content: Text('Document enregistré : ${file.path}')));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Impossible d\'ouvrir le document: $e')));
  }
}
