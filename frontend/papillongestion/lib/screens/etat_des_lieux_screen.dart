import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../widgets/shared_widgets.dart';
import '../services/etat_service.dart';
import '../core/pdf_helper.dart';
import '../core/api_config.dart';

/// Liste et création des états des lieux d'un locataire (3.1).
class EtatDesLieuxScreen extends StatefulWidget {
  final Locataire locataire;
  const EtatDesLieuxScreen({required this.locataire, super.key});
  @override
  State<EtatDesLieuxScreen> createState() => _EtatDesLieuxScreenState();
}

class _EtatDesLieuxScreenState extends State<EtatDesLieuxScreen> {
  final _service = EtatService();
  List<dynamic> _etats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final e = await _service.getEtats(widget.locataire.id);
    if (mounted) setState(() { _etats = e; _loading = false; });
  }

  Future<void> _nouvelEtat() async {
    final cree = await showFormSheet<bool>(
      context,
      builder: (_) => _NouvelEtatDialog(locataireId: widget.locataire.id),
    );
    if (cree == true) _fetch();
  }

  /// Construit l'URL absolue d'une photo (gère relatif vs absolu).
  String _photoUrl(String? p) {
    if (p == null || p.isEmpty) return '';
    if (p.startsWith('http')) return p;
    final base = ApiConfig.baseUrl.replaceAll('/api/v1/', '');
    return p.startsWith('/') ? '$base$p' : '$base/$p';
  }

  /// Visionneuse plein écran (swipe entre les photos).
  void _voirPhotos(List photos, int index) {
    final urls = [for (final ph in photos) _photoUrl(ph['photo']?.toString())]
        .where((u) => u.isNotEmpty).toList();
    if (urls.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _PhotoViewer(urls: urls, initial: index.clamp(0, urls.length - 1)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg, elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.cText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(t.inventoriesTitle, style: TextStyle(color: context.cText, fontSize: 17, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: t.inventoryShort,
            icon: const Icon(Icons.add_rounded, color: AppColors.blue),
            onPressed: _nouvelEtat,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetch,
              child: _etats.isEmpty
                  ? ListView(children: [const SizedBox(height: 120),
                      Center(child: Text(t.noInventory, style: TextStyle(color: context.cTextSub)))])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      itemCount: _etats.length,
                      itemBuilder: (_, i) {
                        final e = _etats[i];
                        final photos = (e['photos'] as List?) ?? [];
                        final entree = e['type_etat'] == 'entree';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: context.cCard, borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: context.cBorder)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Icon(entree ? Icons.login_rounded : Icons.logout_rounded,
                                  color: entree ? AppColors.success : AppColors.warning, size: 18),
                              const SizedBox(width: 8),
                              Text(entree ? t.entryInv : t.exitInv,
                                  style: TextStyle(fontWeight: FontWeight.w700, color: context.cText)),
                              const Spacer(),
                              Text('${e['date']}', style: TextStyle(fontSize: 12, color: context.cTextSub)),
                            ]),
                            if ((e['observations'] ?? '').toString().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(e['observations'], style: TextStyle(fontSize: 12, color: context.cTextSub)),
                            ],
                            const SizedBox(height: 6),
                            Text(t.photosCount(photos.length), style: TextStyle(fontSize: 11, color: context.cHint)),
                            // Galerie de miniatures (tap = plein écran)
                            if (photos.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 64,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: photos.length,
                                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                                  itemBuilder: (_, j) {
                                    final url = _photoUrl(photos[j]['photo']?.toString());
                                    return GestureDetector(
                                      onTap: () => _voirPhotos(photos, j),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Image.network(
                                          url, width: 64, height: 64, fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Container(
                                            width: 64, height: 64, color: context.cSurface,
                                            child: Icon(Icons.broken_image_outlined, color: context.cHint, size: 20)),
                                          loadingBuilder: (c, w, p) => p == null ? w : Container(
                                            width: 64, height: 64, color: context.cSurface,
                                            child: const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(children: [
                              TextButton.icon(
                                onPressed: () async {
                                  await showFormSheet(context, builder: (_) =>
                                      _AjoutPhotoDialog(etatId: e['id']));
                                  _fetch();
                                },
                                icon: const Icon(Icons.add_a_photo_outlined, size: 16),
                                label: Text(t.photo),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: () async {
                                  final bytes = await _service.getRapportPdf(e['id']);
                                  if (mounted) await ouvrirPdf(context, bytes, 'etat_${e['id']}.pdf');
                                },
                                icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                                label: Text(t.pdfReport),
                              ),
                            ]),
                          ]),
                        );
                      },
                    ),
            ),
    );
  }
}

class _NouvelEtatDialog extends StatefulWidget {
  final String locataireId;
  const _NouvelEtatDialog({required this.locataireId});
  @override
  State<_NouvelEtatDialog> createState() => _NouvelEtatDialogState();
}

class _NouvelEtatDialogState extends State<_NouvelEtatDialog> {
  String _type = 'entree';
  final _obs = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      sheetHeader(context, t.newInventory),
      DropdownButtonFormField<String>(
        value: _type,
        dropdownColor: context.cCard,
        decoration: InputDecoration(labelText: t.typeLabel),
        items: [
          DropdownMenuItem(value: 'entree', child: Text(t.entryInv)),
          DropdownMenuItem(value: 'sortie', child: Text(t.exitInv)),
        ],
        onChanged: (v) => setState(() => _type = v ?? 'entree'),
      ),
      const SizedBox(height: 12),
      TextField(controller: _obs, maxLines: 2, style: TextStyle(color: context.cText),
          decoration: InputDecoration(labelText: t.observations)),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel))),
        const SizedBox(width: 12),
        Expanded(child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, foregroundColor: Colors.white),
          onPressed: _saving ? null : () async {
            setState(() => _saving = true);
            final id = await EtatService().createEtat(
              locataireId: widget.locataireId, type: _type, date: _date, observations: _obs.text);
            if (context.mounted) Navigator.pop(context, id != null);
          },
          child: Text(t.create),
        )),
      ]),
    ]);
  }
}

class _AjoutPhotoDialog extends StatefulWidget {
  final int etatId;
  const _AjoutPhotoDialog({required this.etatId});
  @override
  State<_AjoutPhotoDialog> createState() => _AjoutPhotoDialogState();
}

class _AjoutPhotoDialogState extends State<_AjoutPhotoDialog> {
  final _piece = TextEditingController();
  final _desc = TextEditingController();
  String? _photoPath;
  bool _saving = false;

  Future<void> _prendrePhoto(ImageSource source) async {
    final img = await ImagePicker().pickImage(source: source, imageQuality: 70);
    if (img != null) setState(() => _photoPath = img.path);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      sheetHeader(context, t.addPhoto),
      TextField(controller: _piece, style: TextStyle(color: context.cText),
          decoration: InputDecoration(labelText: t.roomHint)),
      const SizedBox(height: 12),
      TextField(controller: _desc, style: TextStyle(color: context.cText),
          decoration: InputDecoration(labelText: t.description)),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        TextButton.icon(onPressed: () => _prendrePhoto(ImageSource.camera),
            icon: const Icon(Icons.camera_alt_outlined, size: 18), label: Text(t.camera)),
        TextButton.icon(onPressed: () => _prendrePhoto(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined, size: 18), label: Text(t.gallery)),
      ]),
      if (_photoPath != null)
        Padding(padding: const EdgeInsets.only(top: 6),
            child: Text(t.photoSelected, style: const TextStyle(color: AppColors.success, fontSize: 12))),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel))),
        const SizedBox(width: 12),
        Expanded(child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, foregroundColor: Colors.white),
          onPressed: (_saving || _photoPath == null) ? null : () async {
            if (_piece.text.trim().isEmpty) return;
            setState(() => _saving = true);
            final ok = await EtatService().addPhoto(
              etatId: widget.etatId, piece: _piece.text.trim(),
              description: _desc.text.trim(), photoPath: _photoPath!);
            if (context.mounted) Navigator.pop(context, ok);
          },
          child: Text(t.add),
        )),
      ]),
    ]);
  }
}

// ─── Visionneuse plein écran des photos d'état des lieux ─────────────────────
class _PhotoViewer extends StatefulWidget {
  final List<String> urls;
  final int initial;
  const _PhotoViewer({required this.urls, required this.initial});
  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _ctrl = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('${_index + 1} / ${widget.urls.length}',
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: PageView.builder(
        controller: _ctrl,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 1, maxScale: 4,
          child: Center(
            child: Image.network(
              widget.urls[i],
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
              loadingBuilder: (c, w, p) => p == null ? w : const Center(child: CircularProgressIndicator(color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }
}
