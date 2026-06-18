import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/paiement_service.dart';
import '../services/locataire_service.dart';

class AddPaiementScreen extends StatefulWidget {
  final Locataire? initialLocataire;
  const AddPaiementScreen({super.key, this.initialLocataire});

  @override
  State<AddPaiementScreen> createState() => _AddPaiementScreenState();
}

class _AddPaiementScreenState extends State<AddPaiementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _montant = TextEditingController();
  final _reference = TextEditingController();
  
  ModePaiement _mode = ModePaiement.especes;
  DateTime _datePaiement = DateTime.now();
  
  List<Locataire> _locataires = [];
  String? _selectedLocataireId;
  bool _isLoadingLocataires = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialLocataire != null) {
      _selectedLocataireId = widget.initialLocataire!.id;
    }
    // Recalcule le reste dû à chaque saisie du montant
    _montant.addListener(() => setState(() {}));
    _fetchLocataires();
  }

  Locataire? get _selectedLoc {
    for (final l in _locataires) {
      if (l.id == _selectedLocataireId) return l;
    }
    return null;
  }
  
  Future<void> _fetchLocataires() async {
    final locs = await LocataireService().getLocataires();
    if (mounted) {
      setState(() {
        _locataires = locs;
        _isLoadingLocataires = false;
        if (_selectedLocataireId == null && _locataires.isNotEmpty) {
          _selectedLocataireId = _locataires.first.id;
        }
      });
    }
  }

  @override
  void dispose() {
    _montant.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    if (_selectedLocataireId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.selectTenantPlease)));
      return;
    }

    setState(() => _isSaving = true);
    final success = await PaiementService().createPaiement(
      locataireId: int.parse(_selectedLocataireId!),
      montant: double.parse(_montant.text),
      modePaiement: _mode.label,
      datePaiement: _datePaiement,
      reference: _reference.text.isNotEmpty ? _reference.text : null,
    );
    if (!mounted) return;

    setState(() => _isSaving = false);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.paymentSaved, style: const TextStyle(color: Colors.white)), backgroundColor: AppColors.success),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.saveError, style: const TextStyle(color: Colors.white)), backgroundColor: AppColors.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.cText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(t.newPayment, style: TextStyle(color: context.cText, fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: _isLoadingLocataires 
        ? const Center(child: CircularProgressIndicator())
        : GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle(t.paymentDetails),
                    
                    // Locataire dropdown
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: context.isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: context.cBorder),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedLocataireId,
                          isExpanded: true,
                          dropdownColor: context.cCard,
                          icon: Icon(Icons.keyboard_arrow_down_rounded, color: context.cHint),
                          hint: Text(t.selectTenant, style: TextStyle(color: context.cHint)),
                          items: _locataires.map((loc) {
                            return DropdownMenuItem(
                              value: loc.id,
                              child: Text(loc.nom, style: TextStyle(color: context.cText)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() => _selectedLocataireId = val);
                          },
                        ),
                      ),
                    ),
                    
                    _GlassInput(label: t.amountFcfaLabel, controller: _montant, icon: Icons.payments_outlined, type: TextInputType.number),
                    _buildResteDuBanner(),
                    const SizedBox(height: 16),
                    _GlassInput(label: t.referenceNote, controller: _reference, icon: Icons.receipt_long_outlined, hint: t.referenceHint, validator: (_) => null),
                    const SizedBox(height: 24),

                    _SectionTitle(t.paymentMode),
                    _buildModeSelector(),
                    const SizedBox(height: 24),

                    _SectionTitle(t.date),
                    GestureDetector(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _datePaiement,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          builder: (context, child) => Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.light(
                                primary: AppColors.blue,
                                onPrimary: Colors.white,
                                surface: context.bg,
                                onSurface: context.cText,
                              ),
                            ),
                            child: child!,
                          ),
                        );
                        if (date != null) setState(() => _datePaiement = date);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: context.cBorder),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_month_outlined, color: context.cTextSub, size: 22),
                            const SizedBox(width: 12),
                            Text('${_datePaiement.day}/${_datePaiement.month}/${_datePaiement.year}', style: TextStyle(fontSize: 15, color: context.cText, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    
                    // Submit
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.blue,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: _isSaving
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text(t.save, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    );
  }

  /// Compare en direct le montant saisi au loyer du locataire sélectionné
  /// et affiche le reste dû (partiel) ou le nombre de mois couverts (avance).
  Widget _buildResteDuBanner() {
    final t = AppLocalizations.of(context);
    final loc = _selectedLoc;
    final saisi = double.tryParse(_montant.text) ?? 0;
    if (loc == null || saisi <= 0 || loc.montantLoyer <= 0) {
      return const SizedBox.shrink();
    }

    final loyer = loc.montantLoyer;
    String texte;
    Color couleur;
    IconData icone;

    if (saisi < loyer) {
      texte = t.partialPaymentRemaining(formatMontant(loyer - saisi));
      couleur = AppColors.danger;
      icone = Icons.warning_amber_rounded;
    } else {
      final nbMois = (saisi ~/ loyer);
      texte = nbMois > 1
          ? t.advancePayment(nbMois)
          : t.fullPayment;
      couleur = AppColors.success;
      icone = Icons.check_circle_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: couleur.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: couleur.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(icone, color: couleur, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(texte, style: TextStyle(color: couleur, fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return Container(
      decoration: BoxDecoration(
        color: context.isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cBorder),
      ),
      child: Column(
        children: ModePaiement.values.map((m) {
          final isSelected = _mode == m;
          return InkWell(
            onTap: () => setState(() => _mode = m),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                border: m != ModePaiement.values.last ? Border(bottom: BorderSide(color: context.cBorder)) : null,
              ),
              child: Row(
                children: [
                  Icon(m.icon, color: isSelected ? AppColors.blue : context.cTextSub, size: 22),
                  const SizedBox(width: 12),
                  Text(modeLabelL(m, AppLocalizations.of(context)), style: TextStyle(fontSize: 15, color: isSelected ? context.cText : context.cTextSub, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400)),
                  const Spacer(),
                  if (isSelected) const Icon(Icons.check_circle_rounded, color: AppColors.blue, size: 20),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(title.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.cHint, letterSpacing: 1.2)),
    );
  }
}

class _GlassInput extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final String? hint;
  final TextInputType type;
  final String? Function(String?)? validator;

  const _GlassInput({required this.label, required this.controller, required this.icon, this.hint, this.type = TextInputType.text, this.validator});

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return Container(
      decoration: BoxDecoration(
        color: dark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cBorder),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: type,
        style: TextStyle(color: context.cText, fontSize: 15, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: context.cHint, fontSize: 14, fontWeight: FontWeight.w500),
          hintText: hint,
          hintStyle: TextStyle(color: context.cHint.withOpacity(0.5)),
          prefixIcon: Icon(icon, color: context.cTextSub, size: 22),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        validator: validator ?? (v) => (v == null || v.isEmpty) ? AppLocalizations.of(context).required : null,
      ),
    );
  }
}
