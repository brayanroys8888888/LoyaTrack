import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/parametres_service.dart';

/// Écran « Mes informations » : permet au bailleur de compléter toutes les
/// données nécessaires aux documents légaux (identité, contact, adresse).
/// Validation stricte : les champs indispensables doivent être renseignés.
class BailleurInfoScreen extends StatefulWidget {
  const BailleurInfoScreen({super.key});
  @override
  State<BailleurInfoScreen> createState() => _BailleurInfoScreenState();
}

class _BailleurInfoScreenState extends State<BailleurInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _prenom = TextEditingController();
  final _nom = TextEditingController();
  final _tel = TextEditingController();
  final _email = TextEditingController();
  final _adresse = TextEditingController();

  final _auth = AuthService();
  final _params = ParametresService();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final p = await _auth.getProfile();
    final c = await _params.getParametres();
    if (!mounted) return;
    setState(() {
      if (p != null) {
        _prenom.text = (p['first_name'] ?? '').toString();
        _nom.text = (p['last_name'] ?? '').toString();
        _tel.text = (p['telephone'] ?? '').toString();
        _email.text = (p['email'] ?? '').toString();
      }
      if (c != null) {
        _adresse.text = (c['adresse_bailleur'] ?? '').toString();
      }
      _loading = false;
    });
  }

  @override
  void dispose() {
    for (final c in [_prenom, _nom, _tel, _email, _adresse]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final profil = await _auth.updateProfile({
      'first_name': _prenom.text.trim(),
      'last_name': _nom.text.trim(),
      'telephone': _tel.text.trim(),
      'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
    });
    final config = await _params.updateParametres({
      'adresse_bailleur': _adresse.text.trim(),
    });

    if (!mounted) return;
    setState(() => _saving = false);

    final ok = profil != null && config != null;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? t.infoSaved : t.saveFailed),
      backgroundColor: ok ? AppColors.success : AppColors.danger,
    ));
    if (ok) Navigator.pop(context, true);
  }

  String? _obligatoire(String? v, AppLocalizations t) =>
      (v == null || v.trim().isEmpty) ? t.requiredField : null;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(title: Text(t.myInfoTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                children: [
                  Text(t.myInfoSubtitle,
                      style: TextStyle(fontSize: 13, color: context.cTextSub)),
                  const SizedBox(height: 20),
                  _label(t.firstName, context),
                  _field(_prenom,
                      hint: 'Jean',
                      validator: (v) => _obligatoire(v, t)),
                  _label(t.lastName, context),
                  _field(_nom,
                      hint: 'Dupont',
                      validator: (v) => _obligatoire(v, t)),
                  _label(t.phone, context),
                  _field(_tel,
                      hint: '+237 6 _ _ _',
                      type: TextInputType.phone,
                      validator: (v) => _obligatoire(v, t)),
                  _label(t.emailAddress, context),
                  _field(_email,
                      hint: 'jean@email.com',
                      type: TextInputType.emailAddress,
                      validator: (v) {
                        final s = (v ?? '').trim();
                        if (s.isEmpty) return null; // email facultatif
                        return s.contains('@') ? null : t.invalidEmail;
                      }),
                  _label(t.landlordAddress, context),
                  _field(_adresse,
                      hint: t.landlordAddress,
                      maxLines: 2,
                      validator: (v) => _obligatoire(v, t)),
                  const SizedBox(height: 28),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(t.save),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _label(String text, BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 14),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 11,
                color: context.cTextSub,
                letterSpacing: 0.8)),
      );

  Widget _field(TextEditingController ctrl,
          {required String hint,
          TextInputType? type,
          int maxLines = 1,
          String? Function(String?)? validator}) =>
      TextFormField(
        controller: ctrl,
        keyboardType: type,
        maxLines: maxLines,
        validator: validator,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        decoration: InputDecoration(hintText: hint),
      );
}
