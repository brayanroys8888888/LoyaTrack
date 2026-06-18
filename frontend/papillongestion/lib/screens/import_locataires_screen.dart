import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../services/locataire_service.dart';
import '../core/pdf_helper.dart';

/// Écran d'import en masse de locataires depuis un fichier CSV/Excel (2.4).
class ImportLocatairesScreen extends StatefulWidget {
  const ImportLocatairesScreen({super.key});
  @override
  State<ImportLocatairesScreen> createState() => _ImportLocatairesScreenState();
}

class _ImportLocatairesScreenState extends State<ImportLocatairesScreen> {
  final _service = LocataireService();
  String? _path;
  String? _name;
  bool _loading = false;
  Map<String, dynamic>? _resultat;

  Future<void> _choisir() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['csv', 'xlsx', 'xls'],
    );
    if (res != null && res.files.single.path != null) {
      setState(() {
        _path = res.files.single.path;
        _name = res.files.single.name;
        _resultat = null;
      });
    }
  }

  Future<void> _telechargerModele() async {
    final bytes = await _service.getModeleImport();
    if (mounted) await ouvrirPdf(context, bytes, 'modele_import_locataires.csv');
  }

  Future<void> _importer() async {
    if (_path == null) return;
    setState(() => _loading = true);
    final res = await _service.importLocataires(_path!, _name ?? 'import.csv');
    if (!mounted) return;
    setState(() { _loading = false; _resultat = res; });
    if (res != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context).importedCount((res['crees'] ?? 0) as int)),
        backgroundColor: AppColors.success,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final r = _resultat;
    final erreurs = (r?['erreurs'] as List?) ?? [];
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg, elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.cText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(t.importTenants, style: TextStyle(color: context.cText, fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(t.importIntro,
              style: TextStyle(color: context.cTextSub, fontSize: 13)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _telechargerModele,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(t.downloadCsvTemplate),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _choisir,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.cCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _path != null ? AppColors.success : context.cBorder),
              ),
              child: Row(children: [
                Icon(_path != null ? Icons.check_circle_rounded : Icons.attach_file_rounded,
                    color: _path != null ? AppColors.success : AppColors.blue),
                const SizedBox(width: 10),
                Expanded(child: Text(_name ?? t.chooseFile,
                    style: TextStyle(color: context.cText, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: (_path == null || _loading) ? null : _importer,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: _loading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(t.import, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
          if (r != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: context.cSuccessBg, borderRadius: BorderRadius.circular(12)),
              child: Text('✓ ${t.importedCount((r['crees'] ?? 0) as int)}',
                  style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700)),
            ),
            if (erreurs.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(t.errorsCount(erreurs.length), style: TextStyle(fontWeight: FontWeight.w700, color: context.cText)),
              const SizedBox(height: 6),
              ...erreurs.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(t.importErrorLine(e['ligne'], e['message']),
                        style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                  )),
            ],
          ],
        ],
      ),
    );
  }
}
