import 'dart:convert';
import 'dart:ui' as import_ui;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:signature/signature.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../widgets/shared_widgets.dart';
import '../services/locataire_service.dart';
import '../services/parametres_service.dart';
import '../services/bien_service.dart';
import '../models/bien.dart';
import 'biens_screen.dart';

class AddLocataireScreen extends StatefulWidget {
  final Locataire? locataire;
  const AddLocataireScreen({this.locataire, super.key});

  @override
  State<AddLocataireScreen> createState() => _AddLocataireScreenState();
}

class _AddLocataireScreenState extends State<AddLocataireScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _prenom, _nom, _tel, _logement, _loyer, _jour, _penalite, _notes;
  late TextEditingController _profession, _revenus, _numPiece;
  late TextEditingController _adresseLogement, _charges, _dureeBail;
  late SignatureController _signatureController;
  bool _loading = false;
  bool _isSigning = false;
  bool _modeTest = false;
  StatutLocataire _statut = StatutLocataire.nonPaye;
  DateTime? _dateEntree;
  String? _typePiece;
  String? _piecePath;
  String? _pieceName;
  String _langue = 'fr';
  String _frequence = 'mensuel';
  int? _uniteId; // unité de logement sélectionnée (relie au module biens)

  bool get isEdit => widget.locataire != null;

  @override
  void initState() {
    super.initState();
    final l = widget.locataire;
    // Split existing full name back to prenom/nom for edit mode
    final parts = (l?.nom ?? '').split(' ');
    final existingPrenom = parts.isNotEmpty ? parts.first : '';
    final existingNom = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    
    _prenom = TextEditingController(text: existingPrenom);
    _nom    = TextEditingController(text: existingNom);
    _tel      = TextEditingController(text: l?.telephone ?? '');
    _logement = TextEditingController(text: l?.logement ?? '');
    _loyer    = TextEditingController(text: l?.montantLoyer.toInt().toString() ?? '');
    _jour     = TextEditingController(text: l?.jourEcheance.toString() ?? '5');
    _penalite = TextEditingController(text: l?.penaliteJournaliere.toInt().toString() ?? '3000');
    _notes    = TextEditingController(text: l?.notes ?? '');
    _profession = TextEditingController();
    _revenus    = TextEditingController();
    _numPiece   = TextEditingController();
    _adresseLogement = TextEditingController(text: l?.adresseLogement ?? '');
    _charges    = TextEditingController(text: (l != null && l.chargesMensuelles > 0) ? l.chargesMensuelles.toInt().toString() : '');
    _dureeBail  = TextEditingController(text: (l?.dureeBailMois ?? 12).toString());
    _frequence  = l?.frequencePaiement ?? 'mensuel';
    _signatureController = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.transparent,
    );
    _statut   = l?.statut ?? StatutLocataire.nonPaye;
    _dateEntree = l?.dateEntree ?? DateTime.now();
    _langue   = l?.languePreferee ?? 'fr';

    // Création : pré-remplir la pénalité avec le défaut du bailleur (Paramètres)
    if (!isEdit) {
      ParametresService().getParametres().then((c) {
        if (c != null && mounted) {
          final def = double.tryParse('${c['penalite_defaut']}');
          if (def != null) setState(() => _penalite.text = def.toStringAsFixed(0));
        }
      });
    }
  }

  @override
  void dispose() {
    _prenom.dispose(); _nom.dispose(); _tel.dispose(); _logement.dispose(); _loyer.dispose();
    _jour.dispose(); _penalite.dispose(); _notes.dispose();
    _profession.dispose(); _revenus.dispose(); _numPiece.dispose();
    _adresseLogement.dispose(); _charges.dispose(); _dureeBail.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  // ── Sélecteur de logement (unité reliée au module biens) ──────────────────
  Future<void> _choisirLogement() async {
    final svc = BienService();
    final results = await Future.wait([svc.getProprietes(), svc.getUnites()]);
    if (!mounted) return;
    final biens = results[0] as List<Propriete>;
    final unites = results[1] as List<UniteLogement>;
    final t = AppLocalizations.of(context);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6, minChildSize: 0.4, maxChildSize: 0.9,
        builder: (_, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: context.cBorder, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            Text(t.selectHousing, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: context.cText)),
            const SizedBox(height: 8),
            for (final b in biens) ...[
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 2, left: 4),
                child: Text(b.titre.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.cTextSub, letterSpacing: 0.5)),
              ),
              ...unites.where((u) => u.propriete == b.id).map((u) => ListTile(
                    dense: true,
                    leading: Icon(u.estOccupee ? Icons.person_rounded : Icons.meeting_room_outlined,
                        color: u.estOccupee ? AppColors.warning : AppColors.success, size: 20),
                    title: Text('${b.titre} › ${u.numero}', style: TextStyle(color: context.cText, fontSize: 14)),
                    subtitle: Text(u.estOccupee ? '${t.occupied}${u.locataireNom != null ? ' · ${u.locataireNom}' : ''}' : t.vacant,
                        style: TextStyle(fontSize: 11, color: context.cTextSub)),
                    trailing: _uniteId == u.id ? const Icon(Icons.check_rounded, color: AppColors.success) : null,
                    onTap: () {
                      setState(() {
                        _uniteId = u.id;
                        _logement.text = '${b.titre} › ${u.numero}';
                        if (_loyer.text.trim().isEmpty && u.loyerStandard > 0) {
                          _loyer.text = u.loyerStandard.toInt().toString();
                        }
                        if (_adresseLogement.text.trim().isEmpty && b.adresse.isNotEmpty) {
                          _adresseLogement.text = b.adresse;
                        }
                      });
                      Navigator.pop(sheetCtx);
                    },
                  )),
              if (unites.where((u) => u.propriete == b.id).isEmpty)
                Padding(padding: const EdgeInsets.only(left: 16, bottom: 4),
                    child: Text(t.noUnitInProperty, style: TextStyle(fontSize: 12, color: context.cHint))),
            ],
            const Divider(height: 24),
            ListTile(
              leading: const Icon(Icons.add_business_outlined, color: AppColors.blue),
              title: Text(t.createProperty, style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w600)),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final nb = await showCreerBien(context);
                if (nb != null && mounted) _choisirLogement(); // ré-ouvre avec le nouveau bien
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_home_outlined, color: AppColors.blue),
              title: Text(t.createUnit, style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w600)),
              onTap: () async {
                Navigator.pop(sheetCtx);
                await _creerUniteFlow(biens);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _creerUniteFlow(List<Propriete> biens) async {
    Propriete? bien;
    if (biens.isEmpty) {
      bien = await showCreerBien(context);
    } else if (biens.length == 1) {
      bien = biens.first;
    } else if (mounted) {
      bien = await _choisirBien(biens);
    }
    if (bien == null || !mounted) return;
    final u = await showCreerUnite(context, bien.id);
    if (u != null && mounted) {
      setState(() { _uniteId = u.id; _logement.text = '${bien!.titre} › ${u.numero}'; });
    }
  }

  Future<Propriete?> _choisirBien(List<Propriete> biens) {
    final t = AppLocalizations.of(context);
    return showModalBottomSheet<Propriete>(
      context: context,
      backgroundColor: context.cCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 14),
          Text(t.chooseProperty, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: context.cText)),
          const SizedBox(height: 8),
          ...biens.map((b) => ListTile(
                leading: const Icon(Icons.apartment_rounded, color: AppColors.blue),
                title: Text(b.titre, style: TextStyle(color: context.cText)),
                onTap: () => Navigator.pop(sheetCtx, b),
              )),
          ListTile(
            leading: const Icon(Icons.add_business_outlined, color: AppColors.blue),
            title: Text(t.createProperty, style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w600)),
            onTap: () async {
              final nb = await showCreerBien(context);
              if (context.mounted) Navigator.pop(sheetCtx, nb);
            },
          ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  String _idLabel(String v, AppLocalizations t) => switch (v) {
    'Passeport' => t.idPassport,
    'Permis' => t.idLicense,
    _ => t.idCard,
  };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final safeTop = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: context.bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            automaticallyImplyLeading: false,
            elevation: 0,
            backgroundColor: context.bg,
            centerTitle: true,
            leading: IconButton(
              icon: Icon(Icons.close_rounded, color: context.cText, size: 24),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              isEdit ? t.editTenant : t.newTenant,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: context.cText),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle(t.personalInfo),
                    _GlassInput(label: t.firstName, controller: _prenom, icon: Icons.person_outline_rounded, hint: 'Ex: Jean'),
                    const SizedBox(height: 16),
                    _GlassInput(label: t.lastName, controller: _nom, icon: Icons.badge_outlined, hint: 'Ex: Dupont'),
                    const SizedBox(height: 16),
                    _GlassInput(label: t.phone, controller: _tel, icon: Icons.phone_outlined, hint: '+237 ...', type: TextInputType.phone),
                    const SizedBox(height: 16),
                    // Logement = sélecteur d'unité (relié au module biens)
                    GestureDetector(
                      onTap: _choisirLogement,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                        decoration: BoxDecoration(
                          color: context.cCard,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: context.cBorder),
                        ),
                        child: Row(children: [
                          Icon(Icons.home_outlined, size: 18, color: context.cHint),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _logement.text.isEmpty ? t.housing : _logement.text,
                              style: TextStyle(
                                  fontSize: 14,
                                  color: _logement.text.isEmpty ? context.cHint : context.cText,
                                  fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(Icons.expand_more_rounded, color: context.cHint, size: 20),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _SectionTitle(t.contractDetails),
                    Row(children: [
                      Expanded(child: _GlassInput(label: t.rentFcfa, controller: _loyer, icon: Icons.payments_outlined, type: TextInputType.number)),
                      const SizedBox(width: 12),
                      Expanded(child: _GlassInput(label: t.dueDayField, controller: _jour, icon: Icons.calendar_month_outlined, type: TextInputType.number)),
                    ]),
                    const SizedBox(height: 16),
                    _GlassInput(label: t.penaltyPerDay, controller: _penalite, icon: Icons.money_off_csred_outlined, type: TextInputType.number),
                    const SizedBox(height: 16),
                    // Langue des rappels (SMS/WhatsApp/appel) envoyés au locataire
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(color: context.cCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: context.cBorder)),
                      child: Row(children: [
                        Icon(Icons.translate_rounded, color: context.cTextSub, size: 20),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t.reminderLanguage, style: TextStyle(fontSize: 11, color: context.cTextSub, fontWeight: FontWeight.w600)),
                          Text(_langue == 'en' ? t.english : t.french, style: TextStyle(fontSize: 14, color: context.cText, fontWeight: FontWeight.w600)),
                        ])),
                        ToggleButtons(
                          isSelected: [_langue == 'fr', _langue == 'en'],
                          onPressed: (i) => setState(() => _langue = i == 0 ? 'fr' : 'en'),
                          borderRadius: BorderRadius.circular(10),
                          constraints: const BoxConstraints(minWidth: 48, minHeight: 36),
                          children: const [Text('FR'), Text('EN')],
                        ),
                      ]),
                    ),
                    const SizedBox(height: 24),
                    // ── Mentions légales (bail) ──
                    _SectionTitle(t.legalSection),
                    _GlassInput(label: t.addressHousing, controller: _adresseLogement, icon: Icons.location_on_outlined),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: _GlassInput(label: t.monthlyCharges, controller: _charges, icon: Icons.receipt_long_outlined, type: TextInputType.number)),
                      const SizedBox(width: 12),
                      Expanded(child: _GlassInput(label: t.leaseDurationMonths, controller: _dureeBail, icon: Icons.event_outlined, type: TextInputType.number)),
                    ]),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(color: context.cCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: context.cBorder)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.paymentFrequency, style: TextStyle(fontSize: 11, color: context.cTextSub, fontWeight: FontWeight.w600)),
                        DropdownButton<String>(
                          value: _frequence,
                          isExpanded: true,
                          underline: const SizedBox.shrink(),
                          dropdownColor: context.cCard,
                          items: [
                            DropdownMenuItem(value: 'mensuel', child: Text(t.freqMonthly, style: TextStyle(color: context.cText))),
                            DropdownMenuItem(value: 'trimestriel', child: Text(t.freqQuarterly, style: TextStyle(color: context.cText))),
                            DropdownMenuItem(value: 'semestriel', child: Text(t.freqHalfYearly, style: TextStyle(color: context.cText))),
                            DropdownMenuItem(value: 'annuel', child: Text(t.freqYearly, style: TextStyle(color: context.cText))),
                          ],
                          onChanged: (v) => setState(() => _frequence = v ?? 'mensuel'),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 24),
                    _SectionTitle(t.additionalInfo),
                    _GlassInput(label: t.profession, controller: _profession, icon: Icons.work_outline_rounded, hint: t.hintProfession),
                    const SizedBox(height: 16),
                    _GlassInput(label: t.monthlyIncome, controller: _revenus, icon: Icons.account_balance_wallet_outlined, type: TextInputType.number),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(color: context.cCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: context.cBorder)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.idType, style: TextStyle(fontSize: 11, color: context.cTextSub, fontWeight: FontWeight.w600)),
                        DropdownButton<String>(
                          value: _typePiece,
                          isExpanded: true,
                          underline: const SizedBox.shrink(),
                          dropdownColor: context.cCard,
                          hint: Text(t.select, style: TextStyle(color: context.cHint, fontSize: 14)),
                          items: const ['CNI', 'Passeport', 'Permis']
                              .map((v) => DropdownMenuItem(value: v, child: Text(_idLabel(v, t), style: TextStyle(color: context.cText))))
                              .toList(),
                          onChanged: (v) => setState(() => _typePiece = v),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    _GlassInput(label: t.idNumber, controller: _numPiece, icon: Icons.badge_outlined),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _choisirPiece,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: context.cCard,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _piecePath != null ? AppColors.success : context.cBorder),
                        ),
                        child: Row(children: [
                          Icon(_piecePath != null ? Icons.check_circle_rounded : Icons.upload_file_outlined,
                              color: _piecePath != null ? AppColors.success : AppColors.blue, size: 20),
                          const SizedBox(width: 10),
                          Expanded(child: Text(
                            _pieceName ?? t.attachId,
                            style: TextStyle(fontSize: 13, color: context.cText, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          )),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _SectionTitle(t.currentStatus),
                    _StatutPicker(selected: _statut, onSelect: (s) => setState(() => _statut = s)),
                    const SizedBox(height: 24),
                    _SectionTitle(t.signatureDocs),
                    Container(
                      decoration: BoxDecoration(
                        color: context.cCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: context.cBorder),
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              IgnorePointer(
                                ignoring: !_isSigning,
                                child: Signature(
                                  controller: _signatureController,
                                  height: 150,
                                  backgroundColor: Colors.white,
                                ),
                              ),
                              if (!_isSigning)
                                Positioned.fill(
                                  child: Container(
                                    color: Colors.black.withOpacity(0.05),
                                    child: Center(
                                      child: ElevatedButton.icon(
                                        onPressed: () => setState(() => _isSigning = true),
                                        icon: const Icon(Icons.edit_rounded, size: 18),
                                        label: Text(t.tapToSign),
                                        style: ElevatedButton.styleFrom(
                                          elevation: 0,
                                          backgroundColor: Colors.white.withOpacity(0.9),
                                          foregroundColor: AppColors.blue,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          Container(
                            decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: context.cBorder)),
                              color: context.cCard,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                if (_isSigning)
                                  TextButton.icon(
                                    onPressed: () => setState(() => _isSigning = false),
                                    icon: const Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.success),
                                    label: Text(t.finish, style: const TextStyle(color: AppColors.success)),
                                  ),
                                TextButton.icon(
                                  onPressed: () {
                                    _signatureController.clear();
                                    if (!_isSigning) setState(() => _isSigning = true);
                                  },
                                  icon: const Icon(Icons.clear, size: 16, color: AppColors.danger),
                                  label: Text(t.clear, style: const TextStyle(color: AppColors.danger)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _GlassInput(
                      label: t.notes,
                      controller: _notes,
                      icon: Icons.notes_rounded,
                      hint: t.notesHint,
                    ),
                    const SizedBox(height: 20),
                    // Mode Test Toggle
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: _modeTest
                            ? AppColors.warning.withOpacity(0.12)
                            : context.cCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _modeTest ? AppColors.warning : context.cBorder,
                          width: _modeTest ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.science_rounded,
                            color: _modeTest ? AppColors.warning : context.cHint,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.modeTest,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: _modeTest ? AppColors.warning : context.cText,
                                  ),
                                ),
                                Text(
                                  t.modeTestSub,
                                  style: TextStyle(fontSize: 11, color: context.cHint),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _modeTest,
                            onChanged: (v) => setState(() => _modeTest = v),
                            activeColor: AppColors.warning,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    _SubmitBtn(label: isEdit ? t.saveChanges : t.addTenant, loading: _loading, onTap: _save),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _choisirPiece() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (res != null && res.files.single.path != null) {
      setState(() {
        _piecePath = res.files.single.path;
        _pieceName = res.files.single.name;
      });
    }
  }

  void _save() async {
    final t = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    if (_prenom.text.trim().isEmpty || _nom.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.nameRequired), backgroundColor: AppColors.danger),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await _enregistrer();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.saveErrorWith('$e')), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _enregistrer() async {
    final montantLoyer = double.tryParse(_loyer.text) ?? 0;
    final jourEcheance = int.tryParse(_jour.text) ?? 1;
    final penalite    = double.tryParse(_penalite.text);

    // Export de la signature manuscrite en base64 (si tracée) — protégé
    String? signatureB64;
    try {
      if (_signatureController.isNotEmpty) {
        final bytes = await _signatureController.toPngBytes();
        if (bytes != null) signatureB64 = base64Encode(bytes);
      }
    } catch (_) {
      signatureB64 = null; // une signature illisible ne doit pas bloquer l'enregistrement
    }

    final revenus = double.tryParse(_revenus.text);
    bool success;
    String? targetId;

    if (isEdit) {
      success = await LocataireService().updateLocataire(
        id:                widget.locataire!.id,
        nom:               _nom.text.trim(),
        prenom:            _prenom.text.trim(),
        telephone:         _tel.text.trim(),
        logement:          _logement.text.trim(),
        montantLoyer:      montantLoyer,
        jourEcheance:      jourEcheance,
        statut:            _statut,
        dateEntree:        _dateEntree ?? DateTime.now(),
        penaliteJournaliere: penalite,
        notes:             _notes.text.trim(),
        signatureBase64:   signatureB64,
        languePreferee:    _langue,
        unite:             _uniteId,
        adresseLogement:   _adresseLogement.text.trim(),
        chargesMensuelles: double.tryParse(_charges.text),
        dureeBailMois:     int.tryParse(_dureeBail.text),
        frequencePaiement: _frequence,
      );
      targetId = widget.locataire!.id;
    } else {
      final created = await LocataireService().createLocataire(
        nom:               _nom.text.trim(),
        prenom:            _prenom.text.trim(),
        telephone:         _tel.text.trim(),
        logement:          _logement.text.trim(),
        montantLoyer:      montantLoyer,
        jourEcheance:      jourEcheance,
        statut:            _statut,
        dateEntree:        _dateEntree ?? DateTime.now(),
        penaliteJournaliere: penalite,
        notes:             _notes.text.trim(),
        modeTest:          _modeTest,
        signatureBase64:   signatureB64,
        profession:        _profession.text.trim(),
        revenusMensuels:   revenus,
        typePieceIdentite: _typePiece,
        numeroPieceIdentite: _numPiece.text.trim(),
        languePreferee:    _langue,
        unite:             _uniteId,
        adresseLogement:   _adresseLogement.text.trim(),
        chargesMensuelles: double.tryParse(_charges.text),
        dureeBailMois:     int.tryParse(_dureeBail.text),
        frequencePaiement: _frequence,
      );
      success = created != null;
      targetId = created?.id;
    }

    // Upload de la pièce d'identité si un fichier a été sélectionné (2.3)
    if (success && _piecePath != null && targetId != null) {
      await LocataireService().uploadPieceIdentite(targetId, _piecePath!);
    }
    
    if (!mounted) return;
    setState(() => _loading = false);
    
    if (success) {
      final t = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEdit ? t.tenantUpdated : t.tenantAdded),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context, true); // retourne `true` pour signaler un rafraîchissement
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).genericError), backgroundColor: AppColors.danger),
      );
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12, left: 4),
        child: Text(title.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.cTextSub, letterSpacing: 1.2)),
      );
}

class _GlassInput extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final String? hint;
  final TextInputType type;
  const _GlassInput({required this.label, required this.controller, required this.icon, this.hint, this.type = TextInputType.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: context.cCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: context.cBorder)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: context.cTextSub, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(children: [
            Icon(icon, size: 18, color: AppColors.blue),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: controller,
                keyboardType: type,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: context.cText),
                decoration: InputDecoration(hintText: hint, hintStyle: TextStyle(color: context.cHint, fontSize: 14), border: InputBorder.none, isDense: true),
              ),
            ),
          ]),
        ]),
      );
}

class _StatutPicker extends StatelessWidget {
  final StatutLocataire selected;
  final ValueChanged<StatutLocataire> onSelect;
  const _StatutPicker({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8, runSpacing: 8,
        children: StatutLocataire.values.map((s) {
          final active = selected == s;
          return GestureDetector(
            onTap: () => onSelect(s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: active ? s.color : context.cCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: active ? s.color : context.cBorder),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(s.icon, style: TextStyle(color: active ? Colors.white : s.color, fontSize: 14)),
                const SizedBox(width: 6),
                Text(statutLabelL(s, AppLocalizations.of(context)), style: TextStyle(color: active ? Colors.white : context.cText, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ),
          );
        }).toList(),
      );
}

class _SubmitBtn extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;
  const _SubmitBtn({required this.label, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: loading ? null : onTap,
        child: Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            gradient: kGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: AppColors.blue.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
          ),
          alignment: Alignment.center,
          child: loading
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
        ),
      );
}
