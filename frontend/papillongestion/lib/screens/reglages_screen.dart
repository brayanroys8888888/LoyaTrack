import 'package:flutter/material.dart';
import 'dart:ui' as import_ui;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../core/locale_provider.dart';
import '../widgets/shared_widgets.dart';
import 'login_screen.dart';
import 'comptabilite_screen.dart';
import 'change_password_screen.dart';
import 'bailleur_info_screen.dart';
import '../services/auth_service.dart';
import '../services/parametres_service.dart';
import '../services/dashboard_service.dart';

class ReglagesScreen extends StatefulWidget {
  const ReglagesScreen({super.key});
  @override
  State<ReglagesScreen> createState() => _ReglagesScreenState();
}

class _ReglagesScreenState extends State<ReglagesScreen> {
  final _params = ParametresService();
  bool _notif = false;
  bool _rappelsAuto = true;
  String _canal = 'sms';
  int _joursAvant = 3;
  bool _deuxFa = false;
  bool _deuxFaBusy = false;
  double? _penaliteDefaut;

  // Profil réel du bailleur (header)
  String _nom = '';
  String _contact = '';
  String _initiales = '';
  int _nbBiens = 0;
  String _adresseBailleur = '';

  @override
  void initState() {
    super.initState();
    AuthService().getProfile().then((p) {
      if (p != null && mounted) {
        setState(() {
          _deuxFa = p['deux_fa_active'] == true;
          _penaliteDefaut = double.tryParse('${p['penalite_defaut']}');
          final prenom = (p['first_name'] ?? '').toString().trim();
          final nom = (p['last_name'] ?? '').toString().trim();
          _nom = '$prenom $nom'.trim();
          _contact = (p['email'] ?? '').toString().trim();
          if (_contact.isEmpty) _contact = (p['telephone'] ?? '').toString().trim();
          _initiales = _calculerInitiales(_nom, _contact);
        });
      }
    });
    DashboardService().getStats().then((s) {
      if (s != null && mounted) setState(() => _nbBiens = s.nombreBiens);
    });
    _params.getParametres().then((c) {
      if (c != null && mounted) {
        setState(() {
          _notif = c['notifications_push_actives'] == true;
          _rappelsAuto = c['rappels_automatiques_actifs'] == true;
          _canal = c['canal_rappel_prefere']?.toString() ?? 'sms';
          _joursAvant = int.tryParse('${c['jours_avant_rappel']}') ?? 3;
          _penaliteDefaut = double.tryParse('${c['penalite_defaut']}') ?? _penaliteDefaut;
          _adresseBailleur = c['adresse_bailleur']?.toString() ?? '';
        });
        // Aligne la langue de l'app sur la préférence serveur.
        context.read<LocaleProvider>().setFromBackend(c['langue_interface']?.toString());
      }
    });
  }

  /// Persiste un changement de paramètre ; restaure l'état en cas d'échec.
  Future<void> _patch(Map<String, dynamic> changes, VoidCallback rollback) async {
    final res = await _params.updateParametres(changes);
    if (res == null && mounted) {
      setState(rollback);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context).saveFailed), backgroundColor: AppColors.danger));
    }
  }

  /// Initiales depuis le nom (2 premières lettres des 2 premiers mots),
  /// repli sur le contact, puis sur « ? ».
  String _calculerInitiales(String nom, String contact) {
    final mots = nom.split(RegExp(r'\s+')).where((m) => m.isNotEmpty).toList();
    if (mots.length >= 2) return (mots[0][0] + mots[1][0]).toUpperCase();
    if (mots.length == 1) {
      return mots[0].substring(0, mots[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    final c = contact.trim();
    return c.isNotEmpty ? c.substring(0, 1).toUpperCase() : '?';
  }

  String _penaliteLabel(AppLocalizations t) => _penaliteDefaut == null
      ? '—'
      : t.dailyPenaltyValue(_penaliteDefaut!.toStringAsFixed(0));

  String _canalLabel(AppLocalizations t) => {
        'sms': t.channelSms, 'whatsapp': t.channelWhatsapp, 'appel': t.channelCall,
      }[_canal] ?? t.channelSms;

  void _changerJours(int delta) {
    final v = (_joursAvant + delta).clamp(1, 15);
    if (v == _joursAvant) return;
    final ancien = _joursAvant;
    setState(() => _joursAvant = v);
    _patch({'jours_avant_rappel': v}, () => _joursAvant = ancien);
  }

  void _choisirCanal() {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) {
        final t = AppLocalizations.of(context);
        final options = [
          ['sms', t.channelSms, Icons.sms_outlined],
          ['whatsapp', t.channelWhatsapp, Icons.chat_outlined],
          ['appel', t.channelCall, Icons.phone_outlined],
        ];
        return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 16),
          Text(t.preferredChannel, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: context.cText)),
          const SizedBox(height: 8),
          for (final e in options)
            ListTile(
              leading: Icon(e[2] as IconData, color: AppColors.blue),
              title: Text(e[1] as String, style: TextStyle(color: context.cText)),
              trailing: _canal == e[0] ? const Icon(Icons.check_rounded, color: AppColors.success) : null,
              onTap: () {
                final ancien = _canal;
                setState(() => _canal = e[0] as String);
                Navigator.pop(context);
                _patch({'canal_rappel_prefere': e[0]}, () => _canal = ancien);
              },
            ),
          const SizedBox(height: 12),
        ]),
      );
      },
    );
  }

  /// Édite l'adresse du bailleur (PATCH adresse_bailleur) — utilisée dans les documents légaux.
  void _editerAdresse() {
    final t = AppLocalizations.of(context);
    final ctrl = TextEditingController(text: _adresseBailleur);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(left: 24, right: 24, top: 20, bottom: 20 + MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.landlordAddress, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: context.cText)),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            autofocus: true,
            style: TextStyle(color: context.cText),
            decoration: InputDecoration(labelText: t.landlordAddress,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: () async {
                final v = ctrl.text.trim();
                Navigator.pop(sheetCtx);
                final ancien = _adresseBailleur;
                setState(() => _adresseBailleur = v);
                final res = await _params.updateParametres({'adresse_bailleur': v});
                if (res == null && mounted) {
                  setState(() => _adresseBailleur = ancien);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.saveFailed), backgroundColor: AppColors.danger));
                }
              },
              child: Text(t.save, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ]),
      ),
    );
  }

  /// Édite la pénalité journalière par défaut (PATCH penalite_defaut).
  void _editerPenalite() {
    final t = AppLocalizations.of(context);
    final ctrl = TextEditingController(
        text: _penaliteDefaut != null ? _penaliteDefaut!.toStringAsFixed(0) : '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
            left: 24, right: 24, top: 20,
            bottom: 20 + MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.dailyPenalty, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: context.cText)),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            style: TextStyle(color: context.cText),
            decoration: InputDecoration(
              labelText: t.amountFcfaLabel,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: () async {
                final v = double.tryParse(ctrl.text.trim());
                if (v == null || v < 0) return;
                Navigator.pop(sheetCtx);
                final ancien = _penaliteDefaut;
                setState(() => _penaliteDefaut = v);
                final res = await _params.updateParametres({'penalite_defaut': v});
                if (res == null && mounted) {
                  setState(() => _penaliteDefaut = ancien);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(t.saveFailed), backgroundColor: AppColors.danger));
                }
              },
              child: Text(t.save, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ]),
      ),
    );
  }

  IconData _themeIcon(ThemeMode m) => {
        ThemeMode.system: Icons.brightness_auto_rounded,
        ThemeMode.light: Icons.light_mode_rounded,
        ThemeMode.dark: Icons.dark_mode_rounded,
      }[m]!;

  String _themeLabel(AppLocalizations t, ThemeMode m) => {
        ThemeMode.system: t.themeSystem,
        ThemeMode.light: t.themeLight,
        ThemeMode.dark: t.themeDark,
      }[m]!;

  /// Sélecteur de thème : Système (défaut) / Clair / Sombre.
  void _choisirTheme(ThemeProvider tp) {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) {
        final t = AppLocalizations.of(context);
        final options = <List<Object>>[
          [ThemeMode.system, t.themeSystem, Icons.brightness_auto_rounded],
          [ThemeMode.light, t.themeLight, Icons.light_mode_rounded],
          [ThemeMode.dark, t.themeDark, Icons.dark_mode_rounded],
        ];
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 16),
            Text(t.theme, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: context.cText)),
            const SizedBox(height: 8),
            for (final e in options)
              ListTile(
                leading: Icon(e[2] as IconData, color: AppColors.blue),
                title: Text(e[1] as String, style: TextStyle(color: context.cText)),
                trailing: tp.themeMode == e[0] ? const Icon(Icons.check_rounded, color: AppColors.success) : null,
                onTap: () {
                  tp.setMode(e[0] as ThemeMode);
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: 12),
          ]),
        );
      },
    );
  }

  Future<void> _toggle2FA(bool v) async {
    setState(() => _deuxFaBusy = true);
    final res = await AuthService().toggle2FA(active: v);
    if (!mounted) return;
    setState(() {
      _deuxFaBusy = false;
      if (res != null) {
        _deuxFa = res;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).twoFAError),
          backgroundColor: AppColors.danger));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final localeProvider = Provider.of<LocaleProvider>(context);
    final t = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: context.bg,
      body: CustomScrollView(
        slivers: [
          // ── SliverAppBar profil adaptative custom ──────────────────────
          SliverPersistentHeader(
            pinned: true,
            delegate: _ReglagesHeaderDelegate(
              safeAreaTop: MediaQuery.of(context).padding.top,
              context: context,
              nom: _nom.isNotEmpty ? _nom : _contact,
              contact: _contact,
              initiales: _initiales.isNotEmpty ? _initiales : '?',
              roleLabel: '${t.roleLandlord} · ${t.propertiesCount(_nbBiens)}',
            ),
          ),
          // ── Body ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // ── Mon compte ─────────────────────────────────────
                _SLabel(t.settingsMyAccount, context),
                _PCard(children: [
                  _PRow(Icons.badge_outlined, context.cBlue3, AppColors.blue, t.myInfoTitle,
                      t.myInfoSettingsSub, context, onTap: () async {
                    await Navigator.push(context, slideRoute(const BailleurInfoScreen()));
                    // Recharge l'adresse + le profil (header) après édition.
                    final c = await _params.getParametres();
                    if (c != null && mounted) setState(() => _adresseBailleur = c['adresse_bailleur']?.toString() ?? '');
                    final p = await AuthService().getProfile();
                    if (p != null && mounted) {
                      setState(() {
                        final prenom = (p['first_name'] ?? '').toString().trim();
                        final nom = (p['last_name'] ?? '').toString().trim();
                        _nom = '$prenom $nom'.trim();
                        _contact = (p['email'] ?? '').toString().trim();
                        if (_contact.isEmpty) _contact = (p['telephone'] ?? '').toString().trim();
                        _initiales = _calculerInitiales(_nom, _contact);
                      });
                    }
                  }),
                  _Div(context),
                  _PRow(Icons.location_on_outlined, context.cBlue3, AppColors.blue, t.landlordAddress,
                      _adresseBailleur.isEmpty ? '—' : _adresseBailleur, context, onTap: _editerAdresse),
                  _Div(context),
                  _PRow(Icons.lock_outline_rounded, context.cSuccessBg, AppColors.success, t.changePassword, t.changePasswordSub, context,
                      onTap: () => Navigator.push(context, slideRoute(const ChangePasswordScreen()))),
                ], context: context),
                const SizedBox(height: 16),

                // ── Sécurité ───────────────────────────────────────
                _SLabel(t.security, context),
                _PCard(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    child: Row(children: [
                      Container(width: 34, height: 34, decoration: BoxDecoration(color: context.cWarningBg, borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.shield_outlined, color: AppColors.warning, size: 18)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.twoFA, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: context.cText)),
                        Text(t.twoFASub, style: TextStyle(fontSize: 11, color: context.cTextSub)),
                      ])),
                      _deuxFaBusy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : AppToggle(value: _deuxFa, onChanged: _toggle2FA),
                    ]),
                  ),
                ], context: context),
                const SizedBox(height: 16),

                // ── Apparence ──────────────────────────────────────
                _SLabel(t.appearance, context),
                _PCard(children: [
                  GestureDetector(
                    onTap: () => _choisirTheme(themeProvider),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      child: Row(children: [
                        Container(width: 34, height: 34, decoration: BoxDecoration(color: context.isDark ? context.cBlue3 : const Color(0xFF1A1A2E).withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                          child: Icon(_themeIcon(themeProvider.themeMode), color: context.isDark ? AppColors.blue : const Color(0xFF1A1A2E), size: 18)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t.theme, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: context.cText)),
                          Text(_themeLabel(t, themeProvider.themeMode), style: TextStyle(fontSize: 11, color: context.cTextSub)),
                        ])),
                        Icon(Icons.chevron_right_rounded, color: context.cBorder, size: 18),
                      ]),
                    ),
                  ),
                  _Div(context),
                  // Langue de l'application (FR / EN)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(children: [
                      Container(width: 34, height: 34, decoration: BoxDecoration(color: context.cBlue3, borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.translate_rounded, color: AppColors.blue, size: 18)),
                      const SizedBox(width: 12),
                      Expanded(child: Text(t.language, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: context.cText))),
                      ToggleButtons(
                        isSelected: [localeProvider.code == 'fr', localeProvider.code == 'en'],
                        onPressed: (i) => localeProvider.setLocale(i == 0 ? 'fr' : 'en'),
                        borderRadius: BorderRadius.circular(10),
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 34),
                        children: const [Text('FR'), Text('EN')],
                      ),
                    ]),
                  ),
                ], context: context),
                const SizedBox(height: 16),

                // ── Rappels ────────────────────────────────────────
                _SLabel(t.autoReminders, context),
                _PCard(children: [
                  _TRow(Icons.autorenew_rounded, context.cBlue3, AppColors.blue, t.autoReminders, t.autoRemindersSub, _rappelsAuto, (v) {
                    setState(() => _rappelsAuto = v);
                    _patch({'rappels_automatiques_actifs': v}, () => _rappelsAuto = !v);
                  }, context),
                  _Div(context),
                  // Canal de rappel préféré
                  GestureDetector(
                    onTap: _choisirCanal,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(children: [
                        Container(width: 34, height: 34, decoration: BoxDecoration(color: context.cBlue3, borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.send_outlined, color: AppColors.blue, size: 18)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t.preferredChannel, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: context.cText)),
                          Text(_canalLabel(t), style: TextStyle(fontSize: 11, color: context.cTextSub)),
                        ])),
                        Icon(Icons.chevron_right_rounded, color: context.cBorder, size: 18),
                      ]),
                    ),
                  ),
                  _Div(context),
                  // Jours avant l'échéance (stepper)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(children: [
                      Container(width: 34, height: 34, decoration: BoxDecoration(color: context.cWarningBg, borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.event_outlined, color: AppColors.warning, size: 18)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.daysBeforeDue, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: context.cText)),
                        Text(t.daysBeforeValue(_joursAvant), style: TextStyle(fontSize: 11, color: context.cTextSub)),
                      ])),
                      IconButton(icon: Icon(Icons.remove_circle_outline_rounded, color: context.cTextSub), onPressed: () => _changerJours(-1)),
                      Text('$_joursAvant', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: context.cText)),
                      IconButton(icon: Icon(Icons.add_circle_outline_rounded, color: AppColors.blue), onPressed: () => _changerJours(1)),
                    ]),
                  ),
                  _Div(context),
                  _TRow(Icons.notifications_outlined, context.cSuccessBg, AppColors.success, t.pushNotifications, t.pushNotificationsSub, _notif, (v) {
                    setState(() => _notif = v);
                    _patch({'notifications_push_actives': v}, () => _notif = !v);
                  }, context),
                ], context: context),
                const SizedBox(height: 16),

                // ── Pénalités ──────────────────────────────────────
                _SLabel(t.penalties, context),
                _PCard(children: [
                  _PRow(Icons.monetization_on_outlined, context.cDangerBg, AppColors.danger, t.dailyPenalty, _penaliteLabel(t), context,
                      onTap: _editerPenalite),
                ], context: context),
                const SizedBox(height: 16),

                // ── Données ────────────────────────────────────────
                _SLabel(t.data, context),
                _PCard(children: [
                  _PRow(Icons.upload_file_outlined, context.cBlue3, AppColors.blue, t.accountingExports, t.accountingExportsSub, context,
                      onTap: () => Navigator.push(context, slideRoute(const ComptabiliteScreen()))),
                  // TODO(roadmap): sauvegarde cloud non implémentée — bouton masqué.
                  // _Div(context),
                  // _PRow(Icons.cloud_upload_outlined, context.cSuccessBg, AppColors.success, t.backupOnline, t.backupOnlineSub, context),
                ], context: context),
                const SizedBox(height: 16),

                // ── À propos ───────────────────────────────────────
                // TODO(roadmap): liens CGU / Politique de confidentialité / Noter l'app
                // non branchés — section masquée jusqu'à implémentation.
                // _SLabel(t.about, context),
                // _PCard(children: [
                //   _PRow(Icons.description_outlined, context.cSurface, context.cTextSub, t.termsOfUseTitle, '', context),
                //   _Div(context),
                //   _PRow(Icons.privacy_tip_outlined, context.cSurface, context.cTextSub, t.privacyPolicyTitle, '', context),
                //   _Div(context),
                //   _PRow(Icons.star_border_rounded, context.cWarningBg, AppColors.warning, t.rateApp, '', context),
                // ], context: context),
                // const SizedBox(height: 20),

                // ── Déconnexion ────────────────────────────────────
                GestureDetector(
                  onTap: () => _confirmLogout(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      color: context.cCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.danger.withOpacity(0.3), width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.logout_rounded, color: AppColors.danger, size: 18),
                      const SizedBox(width: 8),
                      Text(t.logout, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.danger)),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                Center(child: Text('LoyaTrack v1.0.0', style: TextStyle(fontSize: 12, color: context.cHint))),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    final t = AppLocalizations.of(context);
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: context.cBorder,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Icon(Icons.logout_rounded, color: AppColors.danger, size: 44),
          const SizedBox(height: 12),
          Text(t.logoutConfirm,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: context.cText)),
          const SizedBox(height: 6),
          Text(t.logoutConfirmMsg,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: context.cTextSub)),
          const SizedBox(height: 24),
          SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))),
                onPressed: () async {
                  await AuthService().logout();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (_) => false);
                },
                child: Text(t.logout,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              )),
          const SizedBox(height: 10),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  Text(t.cancel, style: TextStyle(color: context.cTextSub))),
        ]),
      ),
    );
  }
}

// ─── Widgets internes ─────────────────────────────────────────────────────────
Widget _SLabel(String t, BuildContext ctx) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t.toUpperCase(),
          style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 11,
              color: ctx.cTextSub,
              letterSpacing: 0.8)),
    );

Widget _PCard(
        {required List<Widget> children, required BuildContext context}) =>
    Container(
      margin: const EdgeInsets.only(bottom: 0),
      decoration: BoxDecoration(
          color: context.cCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.cBorder)),
      child: Column(children: children),
    );

// ignore: non_constant_identifier_names
Widget _PRow(IconData icon, Color bg, Color fg, String title, String sub,
        BuildContext context, {VoidCallback? onTap}) =>
    GestureDetector(
      onTap: onTap ?? () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(children: [
          Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: bg, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: fg, size: 18)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: context.cText)),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(sub,
                      style: TextStyle(fontSize: 11, color: context.cTextSub))
                ],
              ])),
          Icon(Icons.chevron_right_rounded, color: context.cBorder, size: 18),
        ]),
      ),
    );

// ignore: non_constant_identifier_names
Widget _TRow(
        IconData icon,
        Color bg,
        Color fg,
        String title,
        String sub,
        bool value,
        ValueChanged<bool> onChanged,
        BuildContext context) =>
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        Container(
            width: 34,
            height: 34,
            decoration:
                BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: fg, size: 18)),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: context.cText)),
              Text(sub,
                  style: TextStyle(fontSize: 11, color: context.cTextSub)),
            ])),
        AppToggle(value: value, onChanged: onChanged),
      ]),
    );

// ignore: non_constant_identifier_names
Widget _Div(BuildContext context) =>
    Divider(height: 1, color: context.cBorder, indent: 62);


class _ReglagesHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double safeAreaTop;
  final BuildContext context;
  final String nom;
  final String contact;
  final String initiales;
  final String roleLabel;

  _ReglagesHeaderDelegate({
    required this.safeAreaTop,
    required this.context,
    required this.nom,
    required this.contact,
    required this.initiales,
    required this.roleLabel,
  });

  @override
  double get maxExtent => safeAreaTop + 220; 
  @override
  double get minExtent => safeAreaTop + 60;

  @override
  bool shouldRebuild(covariant _ReglagesHeaderDelegate oldDelegate) => true;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final isCollapsed = progress == 1.0;

    return Stack(
      children: [
        // Background
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: isCollapsed ? null : kGradient,
              color: isCollapsed ? context.bg.withOpacity(0.85) : null,
            ),
            child: isCollapsed
                ? ClipRect(
                    child: BackdropFilter(
                      filter: import_ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(color: Colors.transparent),
                    ),
                  )
                : null,
          ),
        ),

        // Rounded bottom corner
        if (!isCollapsed)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 28 * (1 - progress),
              decoration: BoxDecoration(
                color: context.bg,
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(24 * (1 - progress))),
              ),
            ),
          ),

        // Content : groupe centré verticalement (étendu) qui se fond vers
        // une rangée avatar + nom (réduit).
        SafeArea(
          bottom: false,
          child: Stack(
            children: [
              // ── État étendu : colonne centrée (avatar + nom + contact + rôle) ──
              if (progress < 0.98)
                Positioned.fill(
                  child: ClipRect(
                    child: Opacity(
                      opacity: (1 - progress).clamp(0.0, 1.0),
                      child: OverflowBox(
                        minHeight: 0,
                        maxHeight: 320,
                        alignment: Alignment.center,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircleAvatar2(
                                initiales: initiales,
                                bg: Colors.white.withOpacity(0.2),
                                fg: Colors.white,
                                size: 64,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                nom,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white),
                              ),
                              if (contact.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(contact, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.white70)),
                              ],
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                                decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                                child: Text(roleLabel, style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // ── État réduit : avatar + nom à gauche, centrés verticalement ──
              if (progress > 0.6)
                Positioned.fill(
                  child: Opacity(
                    opacity: ((progress - 0.6) / 0.4).clamp(0.0, 1.0),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          CircleAvatar2(
                            initiales: initiales,
                            bg: context.cBlue3,
                            fg: AppColors.blue,
                            size: 40,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              nom,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: context.cText),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
