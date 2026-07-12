import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../models/annonce.dart';
import '../models/models.dart' show formatMontant;
import '../services/annonce_service.dart';
import '../widgets/shared_widgets.dart';

const kAnnonceTypes = ['appartement', 'villa', 'studio', 'chambre', 'immeuble', 'bureau', 'autre'];

/// Libellé localisé d'un type d'annonce (la valeur stockée reste la clé FR).
String annonceTypeLabel(String type, AppLocalizations t) => switch (type) {
      'appartement' => t.typeApartment,
      'villa' => t.typeVilla,
      'studio' => t.typeStudio,
      'chambre' => t.adTypeRoom,
      'immeuble' => t.typeBuilding,
      'bureau' => t.adTypeOffice,
      _ => t.typeOther,
    };

/// Feuille de partage d'une annonce publiée (WhatsApp / copier / ouvrir).
Future<void> partagerAnnonce(BuildContext context, Annonce a) {
  final t = AppLocalizations.of(context);
  final url = a.urlPublique;
  final message = '${a.titre}\n${formatMontant(a.loyer)} FCFA/mois\n$url';
  return showFormSheet(context, builder: (ctx) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      sheetHeader(context, t.adShare),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () {
            Navigator.pop(ctx);
            launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}'),
                mode: LaunchMode.externalApplication);
          },
          icon: const Icon(Icons.chat_rounded, size: 18),
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          label: Text(t.sendWhatsApp, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: url));
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.linkCopied)));
          },
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: Text(t.copyLink, style: const TextStyle(fontSize: 12)),
        )),
        const SizedBox(width: 10),
        Expanded(child: OutlinedButton.icon(
          onPressed: () {
            Navigator.pop(ctx);
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          },
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: Text(t.openLink, style: const TextStyle(fontSize: 12)),
        )),
      ]),
    ]);
  });
}

class AddEditAnnonceScreen extends StatefulWidget {
  final Annonce annonce;
  const AddEditAnnonceScreen({required this.annonce, super.key});
  @override
  State<AddEditAnnonceScreen> createState() => _AddEditAnnonceScreenState();
}

class _AddEditAnnonceScreenState extends State<AddEditAnnonceScreen> {
  final _service = AnnonceService();

  late Annonce _annonce;
  late final TextEditingController _titre;
  late final TextEditingController _description;
  late final TextEditingController _loyer;
  late final TextEditingController _charges;
  late final TextEditingController _adresse;
  late final TextEditingController _superficie;

  late String _typeBien;
  late int _nbChambres, _nbSalons, _nbDouches, _cautionMois;
  late bool _meuble;
  int? _villeId, _quartierId;
  late List<PhotoAnnonce> _photos;

  List<Ville> _villes = [];
  bool _saving = false, _uploading = false;

  @override
  void initState() {
    super.initState();
    final a = widget.annonce;
    _annonce = a;
    _titre = TextEditingController(text: a.titre);
    _description = TextEditingController(text: a.description);
    _loyer = TextEditingController(text: a.loyer > 0 ? a.loyer.toStringAsFixed(0) : '');
    _charges = TextEditingController(text: a.charges > 0 ? a.charges.toStringAsFixed(0) : '');
    _adresse = TextEditingController(text: a.adresseIndicative);
    _superficie = TextEditingController(text: a.superficieM2?.toString() ?? '');
    _typeBien = a.typeBien;
    _nbChambres = a.nbChambres;
    _nbSalons = a.nbSalons;
    _nbDouches = a.nbDouches;
    _cautionMois = a.cautionMois;
    _meuble = a.meuble;
    _villeId = a.ville;
    _quartierId = a.quartier;
    _photos = List.of(a.photos);
    _chargerVilles();
  }

  @override
  void dispose() {
    for (final c in [_titre, _description, _loyer, _charges, _adresse, _superficie]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _chargerVilles() async {
    final v = await _service.getVilles();
    if (mounted) setState(() => _villes = v);
  }

  Map<String, dynamic> _payload() => {
        'titre': _titre.text.trim(),
        'type_bien': _typeBien,
        'nb_chambres': _nbChambres,
        'nb_salons': _nbSalons,
        'nb_douches': _nbDouches,
        'superficie_m2': int.tryParse(_superficie.text.trim()),
        'meuble': _meuble,
        'ville': _villeId,
        'quartier': _quartierId,
        'adresse_indicative': _adresse.text.trim(),
        'loyer': double.tryParse(_loyer.text.trim()) ?? 0,
        'charges': double.tryParse(_charges.text.trim()) ?? 0,
        'caution_mois': _cautionMois,
        'description': _description.text.trim(),
      };

  Future<Annonce?> _enregistrer({bool silencieux = false}) async {
    setState(() => _saving = true);
    final maj = await _service.updateAnnonce(_annonce.id, _payload());
    if (!mounted) return maj;
    setState(() {
      _saving = false;
      if (maj != null) _annonce = maj;
    });
    final t = AppLocalizations.of(context);
    if (!silencieux) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(maj != null ? t.adDraftSaved : t.saveFailed)));
    }
    return maj;
  }

  Future<void> _publier() async {
    final saved = await _enregistrer(silencieux: true);
    if (saved == null || !mounted) return;
    setState(() => _saving = true);
    final res = await _service.publier(_annonce.id);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (res.annonce != null) _annonce = res.annonce!;
    });
    final t = AppLocalizations.of(context);
    if (res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.adPublished)));
      partagerAnnonce(context, _annonce);
    } else {
      showDialog(context: context, builder: (ctx) => AlertDialog(
        backgroundColor: context.cCard,
        title: Text(t.adPublish, style: TextStyle(color: context.cText)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: res.erreurs.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('• $e', style: TextStyle(color: context.cTextSub, fontSize: 13)))).toList()),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.ok))],
      ));
    }
  }

  Future<void> _changerStatut(Future<Annonce?> Function() action) async {
    setState(() => _saving = true);
    final maj = await action();
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (maj != null) _annonce = maj;
    });
  }

  Future<void> _ajouterPhotos() async {
    if (_photos.length >= 10) return;
    final xs = await ImagePicker().pickMultiImage(imageQuality: 70);
    if (xs.isEmpty) return;
    setState(() => _uploading = true);
    for (final x in xs) {
      if (_photos.length >= 10) break;
      final p = await _service.addPhoto(_annonce.id, x.path);
      if (p != null && mounted) setState(() => _photos.add(p));
    }
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _supprimerPhoto(PhotoAnnonce p) async {
    final ok = await _service.deletePhoto(_annonce.id, p.id);
    if (ok && mounted) setState(() => _photos.removeWhere((x) => x.id == p.id));
  }

  Future<void> _supprimerAnnonce() async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: context.cCard,
      title: Text(t.adDeleteConfirm, style: TextStyle(color: context.cText, fontSize: 16)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
        TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.delete, style: const TextStyle(color: AppColors.danger))),
      ],
    ));
    if (ok != true) return;
    final done = await _service.deleteAnnonce(_annonce.id);
    if (done && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final quartiers = _villes
        .firstWhere((v) => v.id == _villeId,
            orElse: () => const Ville(id: -1, nom: '', slug: ''))
        .quartiers;
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.cText, size: 20),
          onPressed: () => Navigator.pop(context, true),
        ),
        title: Text(t.adEdit, style: TextStyle(color: context.cText, fontSize: 18, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
            onPressed: _supprimerAnnonce,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _photosSection(t),
          const SizedBox(height: 16),
          AppInput(label: t.adTitle, hint: t.adTitle, controller: _titre, prefixIcon: Icons.title_rounded),
          const SizedBox(height: 14),
          _dropdown<String>(t.typeLabel, _typeBien, kAnnonceTypes,
              (v) => annonceTypeLabel(v, t), (v) => setState(() => _typeBien = v!)),
          const SizedBox(height: 14),
          _sectionTitle(t.adSectionLocation),
          _dropdown<int?>(t.adCity, _villeId, [null, ..._villes.map((v) => v.id)],
              (v) => v == null ? '—' : _villes.firstWhere((x) => x.id == v).nom,
              (v) => setState(() { _villeId = v; _quartierId = null; })),
          const SizedBox(height: 12),
          _dropdown<int?>(t.adDistrict, _quartierId, [null, ...quartiers.map((q) => q.id)],
              (v) => v == null ? '—' : quartiers.firstWhere((x) => x.id == v).nom,
              (v) => setState(() => _quartierId = v)),
          const SizedBox(height: 12),
          AppInput(label: t.adLandmark, hint: t.adLandmark, controller: _adresse, prefixIcon: Icons.place_outlined),
          const SizedBox(height: 16),
          _sectionTitle(t.adSectionDetails),
          _compteur(t.adBedrooms, _nbChambres, (v) => setState(() => _nbChambres = v)),
          _compteur(t.adLivingRooms, _nbSalons, (v) => setState(() => _nbSalons = v)),
          _compteur(t.adBathrooms, _nbDouches, (v) => setState(() => _nbDouches = v)),
          const SizedBox(height: 12),
          AppInput(label: t.adArea, hint: t.adArea, controller: _superficie, keyboardType: TextInputType.number, prefixIcon: Icons.square_foot_rounded),
          const SizedBox(height: 12),
          _toggleRow(t.adFurnished, _meuble, (v) => setState(() => _meuble = v)),
          const SizedBox(height: 16),
          _sectionTitle(t.adSectionPrice),
          AppInput(label: t.adRent, hint: t.adRent, controller: _loyer, keyboardType: TextInputType.number, prefixIcon: Icons.payments_outlined),
          const SizedBox(height: 12),
          AppInput(label: t.adCharges, hint: t.adCharges, controller: _charges, keyboardType: TextInputType.number, prefixIcon: Icons.add_card_outlined),
          const SizedBox(height: 12),
          _compteur(t.adDeposit, _cautionMois, (v) => setState(() => _cautionMois = v), min: 0),
          const SizedBox(height: 16),
          AppInput(label: t.adDescription, hint: t.adDescription, controller: _description, maxLines: 4, prefixIcon: Icons.notes_rounded),
          const SizedBox(height: 24),
          _actions(t),
        ],
      ),
    );
  }

  Widget _photosSection(AppLocalizations t) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle(t.adSectionPhotos),
      SizedBox(
        height: 96,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final p in _photos)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(p.image, width: 96, height: 96, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(width: 96, height: 96, color: context.cBorder)),
                ),
                Positioned(
                  top: 2, right: 2,
                  child: GestureDetector(
                    onTap: () => _supprimerPhoto(p),
                    child: Container(
                      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      padding: const EdgeInsets.all(2),
                      child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ]),
            ),
          if (_photos.length < 10)
            GestureDetector(
              onTap: _uploading ? null : _ajouterPhotos,
              child: Container(
                width: 96, height: 96,
                decoration: BoxDecoration(
                  color: context.cCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.cBorder),
                ),
                child: _uploading
                    ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.add_a_photo_outlined, color: AppColors.blue),
                        const SizedBox(height: 4),
                        Text(t.adAddPhotos, style: const TextStyle(fontSize: 9, color: AppColors.blue), textAlign: TextAlign.center),
                      ]),
              ),
            ),
        ]),
      ),
    ]);
  }

  Widget _actions(AppLocalizations t) {
    if (_annonce.estPubliee) {
      return Column(children: [
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: () => partagerAnnonce(context, _annonce),
          icon: const Icon(Icons.share_rounded, size: 18),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
          label: Text(t.adShare),
        )),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: _saving ? null : () => _changerStatut(() => _service.renouveler(_annonce.id)),
            child: Text(t.adRenew))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton(
            onPressed: _saving ? null : () => _changerStatut(() => _service.depublier(_annonce.id, pourvue: true)),
            child: Text(t.adMarkFilled))),
        ]),
        TextButton(
          onPressed: _saving ? null : () => _changerStatut(() => _service.depublier(_annonce.id)),
          child: Text(t.adUnpublish, style: TextStyle(color: context.cTextSub)),
        ),
      ]);
    }
    return Row(children: [
      Expanded(child: OutlinedButton(
        onPressed: _saving ? null : () => _enregistrer(),
        child: Text(t.adSaveDraft))),
      const SizedBox(width: 12),
      Expanded(child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
        onPressed: _saving ? null : _publier,
        child: _saving
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(t.adPublish))),
    ]);
  }

  Widget _sectionTitle(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(s, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: context.cText)),
      );

  Widget _dropdown<T>(String label, T value, List<T> items, String Function(T) labelOf, ValueChanged<T?> onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: context.cTextSub, letterSpacing: 0.8)),
      const SizedBox(height: 8),
      DropdownButtonFormField<T>(
        value: items.contains(value) ? value : null,
        dropdownColor: context.cCard,
        isExpanded: true,
        items: items.map((it) => DropdownMenuItem<T>(value: it, child: Text(labelOf(it), style: TextStyle(color: context.cText)))).toList(),
        onChanged: onChanged,
      ),
    ]);
  }

  Widget _compteur(String label, int value, ValueChanged<int> onChanged, {int min = 0}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: context.cText))),
        _rond(Icons.remove_rounded, () { if (value > min) onChanged(value - 1); }),
        SizedBox(width: 36, child: Text('$value', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, color: context.cText))),
        _rond(Icons.add_rounded, () => onChanged(value + 1)),
      ]),
    );
  }

  Widget _rond(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: context.cCard, shape: BoxShape.circle, border: Border.all(color: context.cBorder)),
          child: Icon(icon, size: 18, color: AppColors.blue),
        ),
      );

  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: context.cText)),
          AppToggle(value: value, onChanged: onChanged),
        ],
      );
}
