import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/abonnement_provider.dart';
import '../core/api_config.dart';
import '../models/models.dart';
import '../services/abonnement_service.dart';
import '../theme/app_theme.dart';

/// Écran de blocage affiché quand l'abonnement a expiré. Aucun paiement in-app :
/// le bouton renvoie vers l'espace web (conformité Apple/Google).
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  List<PlanAbonnement> _plans = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final plans = await AbonnementService().getPlans();
    if (mounted) setState(() { _plans = plans; _loading = false; });
  }

  Future<void> _ouvrirWeb() async {
    // Magic-link personnalisé (connexion web sans mot de passe) ; repli sur l'URL statique.
    final lien = await AbonnementService().getLienWeb() ?? ApiConfig.manageSubscriptionUrl;
    final uri = Uri.parse(lien);
    // On tente directement le lancement (canLaunchUrl peu fiable selon les ROM) ;
    // repli sur le mode plateforme par défaut, puis message si rien ne s'ouvre.
    bool ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok) {
      try {
        ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (_) {}
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${AppLocalizations.of(context).subManage} : ${uri.toString()}'),
      ));
    }
  }

  Future<void> _rafraichir() async {
    await abonnementProvider.rafraichir();
    if (!mounted) return;
    if (abonnementProvider.statut.estActif) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.cSurface,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const SizedBox(height: 24),
                  Icon(Icons.lock_outline_rounded, size: 64, color: AppColors.warning),
                  const SizedBox(height: 16),
                  Text(t.subTitleExpired,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: context.cText)),
                  const SizedBox(height: 8),
                  Text(t.subBodyExpired,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: context.cTextSub)),
                  const SizedBox(height: 24),
                  ..._plans.map((p) => _carteePlan(context, p, t)),
                  const SizedBox(height: 12),
                  Text(t.subOnWebNote,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: context.cHint)),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _ouvrirWeb,
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text(t.subManage),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.blue,
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(onPressed: _rafraichir, child: Text(t.subRefreshStatus)),
                ],
              ),
      ),
    );
  }

  Widget _carteePlan(BuildContext context, PlanAbonnement p, AppLocalizations t) {
    final estPro = p.cle == 'pro';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: estPro ? AppColors.blue : context.cBorder, width: estPro ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(p.nom, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: context.cText)),
              Text('${p.mensuel} FCFA${t.subPerMonth}',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.blue)),
            ],
          ),
          Text('${p.annuel} FCFA${t.subPerYear}',
              style: TextStyle(fontSize: 12, color: context.cHint)),
          if (estPro) ...[
            const SizedBox(height: 10),
            ...p.features.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    const Icon(Icons.check_rounded, size: 16, color: AppColors.success),
                    const SizedBox(width: 8),
                    Expanded(child: Text(featureLabelL(f, t),
                        style: TextStyle(fontSize: 13, color: context.cTextSub))),
                  ]),
                )),
          ],
        ],
      ),
    );
  }
}

/// Feuille d'upsell affichée quand une fonction Pro est touchée par un utilisateur
/// Essentiel (ou via le 403 `fonction_pro`).
Future<void> showProUpsell(BuildContext context, {String? feature}) {
  final t = AppLocalizations.of(context);
  return showModalBottomSheet(
    context: context,
    backgroundColor: context.cCard,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
          left: 20, right: 20, top: 16, bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: ctx.cBorder, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: ctx.cWarningBg, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.workspace_premium_rounded, color: AppColors.warning),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(t.subProTitle,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ctx.cText))),
          ]),
          const SizedBox(height: 12),
          Text(feature != null ? '${featureLabelL(feature, t)} — ${t.subProBody}' : t.subProBody,
              style: TextStyle(fontSize: 14, color: ctx.cTextSub)),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const PaywallScreen()));
            },
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.blue, minimumSize: const Size.fromHeight(50)),
            child: Text(t.subUpgrade),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.subLater)),
        ],
      ),
    ),
  );
}
