import 'dart:ui' as import_ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../core/abonnement_provider.dart';
import '../core/refresh_bus.dart';
import '../widgets/shared_widgets.dart';
import 'paywall_screen.dart';
import 'detail_screen.dart';
import 'add_locataire_screen.dart';
import 'detail_paiement_screen.dart';
import 'notifications_screen.dart';
import 'biens_screen.dart';
import '../services/dashboard_service.dart';
import '../services/locataire_service.dart';
import '../services/paiement_service.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';

class DashboardScreen extends StatefulWidget {
  final void Function(int)? onNavigate;
  const DashboardScreen({this.onNavigate, super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardStats? _stats;
  List<Locataire> _recentLocataires = [];
  List<Paiement> _recentPaiements = [];
  bool _isLoading = true;
  // Header dynamique : nom/initiales du bailleur + badge notifications non lues.
  String _prenomBailleur = '';
  String _initiales = '';
  int _notifsNonLues = 0;

  @override
  void initState() {
    super.initState();
    // Réactualisation auto quand une donnée change ailleurs (ajout/modif/suppr).
    refreshBus.addListener(_onExternalRefresh);
    _fetchData();
  }

  void _onExternalRefresh() {
    if (mounted) _onRefresh();
  }

  @override
  void dispose() {
    refreshBus.removeListener(_onExternalRefresh);
    super.dispose();
  }

  /// Récupère les données du header (profil + notifications non lues).
  /// Isolé de _onData pour rester tolérant aux pannes : un échec ici ne doit
  /// pas empêcher l'affichage des stats.
  Future<void> _chargerHeader() async {
    try {
      final profil = await AuthService().getProfile();
      final notifs = await NotificationService.getNotifications();
      if (!mounted) return;
      final nonLues = notifs.where((n) => n['lue'] != true).length;
      setState(() {
        if (profil != null) {
          final prenom = (profil['first_name'] ?? '').toString().trim();
          final nom = (profil['last_name'] ?? '').toString().trim();
          final contact = (profil['email'] ?? profil['telephone'] ?? '')
              .toString()
              .trim();
          _prenomBailleur = prenom;
          _initiales = _calculerInitiales('$prenom $nom'.trim(), contact);
        }
        _notifsNonLues = nonLues;
      });
    } catch (_) {
      // Silencieux : le header retombe sur ses valeurs par défaut.
    }
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    _chargerHeader();
    final results = await Future.wait([
      DashboardService().getStats(),
      LocataireService().getLocataires(),
      PaiementService().getPaiements(),
    ]);
    if (!mounted) return;
    setState(() {
      _stats = results[0] as DashboardStats?;
      _recentLocataires = (results[1] as List<Locataire>).take(2).toList();
      _recentPaiements = (results[2] as List<Paiement>).take(3).toList();
      _isLoading = false;
    });
  }

  Future<void> _onRefresh() async {
    _chargerHeader();
    final results = await Future.wait([
      DashboardService().getStats(),
      LocataireService().getLocataires(),
      PaiementService().getPaiements(),
    ]);
    if (!mounted) return;
    setState(() {
      _stats = results[0] as DashboardStats?;
      _recentLocataires = (results[1] as List<Locataire>).take(2).toList();
      _recentPaiements = (results[2] as List<Paiement>).take(3).toList();
    });
  }

  /// Initiales à partir du nom (2 mots → 2 lettres), sinon du contact.
  String _calculerInitiales(String nom, String contact) {
    final mots =
        nom.split(RegExp(r'\s+')).where((m) => m.isNotEmpty).toList();
    if (mots.length >= 2) return (mots[0][0] + mots[1][0]).toUpperCase();
    if (mots.length == 1) {
      return mots[0].substring(0, mots[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    final c = contact.trim();
    return c.isNotEmpty ? c.substring(0, 1).toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final stats = _stats;
    final payes = stats?.loyersPayes ?? 0;
    final impayes = stats?.impayes ?? 0;
    final total = stats?.totalLocataires ?? 0;

    return Scaffold(
      backgroundColor: context.bg,
      body: Stack(children: [
        RefreshIndicator(
          onRefresh: _onRefresh,
          color: AppColors.blue,
          backgroundColor: context.cCard,
          child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _DashboardHeaderDelegate(
                safeAreaTop: MediaQuery.of(context).padding.top,
                context: context,
                prenom: _prenomBailleur,
                initiales: _initiales,
                notifsNonLues: _notifsNonLues,
                onAdd: () async {
                  final r = await Navigator.push(context, modalRoute(const AddLocataireScreen()));
                  if (r == true) _fetchData();
                },
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                child: _isLoading
                  ? const DashboardSkeleton()
                  : Column(
                  children: [
                    const _BanniereEssai(),
                    // Stats
                    Row(children: [
                      _StatCard(
                          t.navTenants,
                          '$total',
                          t.dashTotal,
                          Icons.people_alt_outlined,
                          context.cBlue3,
                          AppColors.blue,
                          context),
                      const SizedBox(width: 10),
                      _StatCard(
                          t.dashPaid,
                          '$payes',
                          t.dashThisMonth,
                          Icons.credit_card_outlined,
                          context.cSuccessBg,
                          AppColors.success,
                          context),
                      const SizedBox(width: 10),
                      _StatCard(
                          t.dashUnpaid,
                          '$impayes',
                          t.statusLate,
                          Icons.warning_amber_rounded,
                          context.cDangerBg,
                          AppColors.danger,
                          context),
                    ]),
                    const SizedBox(height: 16),
                    // Cockpit d'encaissement du mois
                    _CockpitCard(stats: stats),
                    const SizedBox(height: 18),
                    // À encaisser ce mois (liste actionnable)
                    if (stats != null && stats.aEncaisser.isNotEmpty) ...[
                      SectionHeader(t.cockpitToCollect),
                      const SizedBox(height: 10),
                      ...stats.aEncaisser.map((e) => _AEncaisserRow(
                            item: e,
                            onReminded: _fetchData,
                            onOpen: () => widget.onNavigate?.call(1),
                          )),
                      const SizedBox(height: 18),
                    ],
                    // Locataires récents
                    SectionHeader(t.recentTenants, action: t.seeAll, onAction: () => widget.onNavigate?.call(1)),
                    const SizedBox(height: 10),
                    if (_recentLocataires.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(t.noTenantsYet,
                            style: TextStyle(color: context.cTextSub, fontSize: 13)),
                      )
                    else
                      ..._recentLocataires.map((l) => LocataireCard(
                            loc: l,
                            showAmount: false,
                            onTap: () => Navigator.push(
                                context, heroRoute(DetailLocataireScreen(locataire: l))),
                          )),
                    const SizedBox(height: 16),
                    // Paiements
                    SectionHeader(t.recentPayments, action: t.seeAll, onAction: () => widget.onNavigate?.call(2)),
                    const SizedBox(height: 10),
                    if (_recentPaiements.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(t.noPaymentsYet,
                            style: TextStyle(color: context.cTextSub, fontSize: 13)),
                      )
                    else
                      ..._recentPaiements.map((p) => _PaiRow(p, context)),
                    const SizedBox(height: 16),
                    // Mes biens (taux d'occupation du parc)
                    AppCard(
                      onTap: () => Navigator.push(context, slideRoute(const BiensScreen())),
                      child: Row(children: [
                        Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                  colors: [Color(0xFF1565C0), Color(0xFF2E7D32)]),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(Icons.apartment_rounded,
                                color: Colors.white, size: 22)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(t.myProperties,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: context.cText)),
                              const SizedBox(height: 2),
                              Text(
                                  t.propertiesSummary(
                                      stats?.nombreBiens ?? 0,
                                      stats?.unitesOccupees ?? 0,
                                      stats?.totalUnites ?? 0,
                                      (stats?.tauxOccupation ?? 0).toStringAsFixed(0)),
                                  style: TextStyle(
                                      fontSize: 11, color: context.cTextSub)),
                            ])),
                        const Icon(Icons.chevron_right_rounded,
                            color: AppColors.blue, size: 20),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    // Bouton Automatisations
                    GestureDetector(
                      onTap: () async {
                        final success = await LocataireService().triggerAutomations();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(success ? t.automationsTriggered : t.networkError),
                            backgroundColor: success ? AppColors.success : AppColors.danger,
                          ),
                        );
                      },
                      child: AppCard(
                        color: AppColors.warning.withOpacity(0.1),
                        border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(children: [
                          Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                  color: AppColors.warning,
                                  borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.auto_awesome_rounded,
                                  color: Colors.white, size: 18)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(t.runAutomations,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: context.cText))),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        ),  // end RefreshIndicator
      ]),
    );
  }
}

/// Bannière d'essai : visible uniquement pendant la période d'essai.
class _BanniereEssai extends StatelessWidget {
  const _BanniereEssai();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: abonnementProvider,
      builder: (context, _) => _contenu(context),
    );
  }

  Widget _contenu(BuildContext context) {
    final ab = abonnementProvider.statut;
    if (ab.statut != 'essai') return const SizedBox.shrink();
    final t = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.cWarningBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withOpacity(0.4)),
      ),
      child: Row(children: [
        const Icon(Icons.workspace_premium_rounded, color: AppColors.warning, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(t.subTrialBanner(ab.joursRestants),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.cText)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PaywallScreen())),
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
          child: Text(t.subUpgrade, style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

class _DashboardHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double safeAreaTop;
  final BuildContext context;
  final VoidCallback onAdd;
  final String prenom;
  final String initiales;
  final int notifsNonLues;

  _DashboardHeaderDelegate({
    required this.safeAreaTop,
    required this.onAdd,
    required this.context,
    required this.prenom,
    required this.initiales,
    required this.notifsNonLues,
  });

  @override
  double get maxExtent => safeAreaTop + 100;
  @override
  double get minExtent => safeAreaTop + 60;

  @override
  bool shouldRebuild(covariant _DashboardHeaderDelegate oldDelegate) => true;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final isCollapsed = progress == 1.0;

    final double avatarSize = 46 - (14 * progress);

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
              height: 24 * (1 - progress),
              decoration: BoxDecoration(
                color: context.bg,
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(24 * (1 - progress))),
              ),
            ),
          ),

        // Content
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: 4 * progress),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar2(
                        initiales: initiales.isNotEmpty ? initiales : '·',
                        bg: Colors.white.withOpacity(0.2),
                        fg: Colors.white,
                        size: avatarSize),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          Text(
                              prenom.isNotEmpty
                                  ? AppLocalizations.of(context)
                                      .dashGreetingName(prenom)
                                  : AppLocalizations.of(context).dashGreeting,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16 - (1 * progress),
                                  color: isCollapsed ? context.cText : Colors.white)),
                          if (progress < 1.0) ...[
                            SizedBox(height: 2 * (1 - progress)),
                            Opacity(
                              opacity: 1 - progress,
                              child: Text(AppLocalizations.of(context).loginWelcome,
                                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
                            ),
                          ]
                        ])),
                    // Bouton « + » (ajouter un locataire)
                    // GestureDetector(
                    //   onTap: onAdd,
                    //   child: Container(
                    //     margin: const EdgeInsets.only(right: 8),
                    //     width: 38 - (4 * progress),
                    //     height: 38 - (4 * progress),
                    //     decoration: BoxDecoration(
                    //       shape: BoxShape.circle,
                    //       color: isCollapsed ? AppColors.blue : Colors.white.withOpacity(0.15),
                    //       border: isCollapsed ? Border.all(color: AppColors.blue) : null,
                    //     ),
                    //     child: Icon(Icons.add_rounded,
                    //         color: isCollapsed ? Colors.white : Colors.white, size: 20),
                    //   ),
                    // ),
                    GestureDetector(
                      onTap: () => Navigator.push(context, slideRoute(const NotificationsScreen())),
                      child: Stack(clipBehavior: Clip.none, children: [
                      Container(
                          width: 45 - (4 * progress),
                          height: 45 - (4 * progress),
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isCollapsed ? context.cCard : Colors.white.withOpacity(0.15),
                              border: isCollapsed ? Border.all(color: context.cBorder) : null,
                          ),
                          child: Icon(Icons.notifications_outlined,
                              color: isCollapsed ? context.cText : Colors.white, size: 20)),
                      // Badge : uniquement s'il y a des notifications non lues.
                      if (notifsNonLues > 0)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: Opacity(
                            opacity: 1 - (progress * 0.5), // Keep slightly visible or fade it
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 17),
                              height: 17,
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                  shape: BoxShape.rectangle,
                                  borderRadius: BorderRadius.circular(9),
                                  color: Colors.red.shade600,
                                  border: Border.all(
                                      color: isCollapsed ? context.bg : const Color(0xFF1565C0), width: 1.5)),
                              alignment: Alignment.center,
                              child: Text(notifsNonLues > 9 ? '9+' : '$notifsNonLues',
                                  style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                            ),
                          )),
                    ]),
                    ),
                  ],
                ),
                SizedBox(height: 24 * (1 - progress)), // push content up
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Widget _StatCard(String label, String value, String sub, IconData icon,
    Color iconBg, Color iconFg, BuildContext context) {
  return Expanded(
      child: AppCard(
    padding: const EdgeInsets.all(12),
    child:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: iconBg, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: iconFg, size: 17)),
      const SizedBox(height: 8),
      Text(value,
          style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 22,
              color: iconFg)),
      Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: context.cText)),
      Text(sub, style: TextStyle(fontSize: 9, color: context.cHint)),
    ]),
  ));
}

/// Carte cockpit : Attendu · Encaissé · Reste (mois courant) + barre de recouvrement.
class _CockpitCard extends StatelessWidget {
  final DashboardStats? stats;
  const _CockpitCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final s = stats;
    final attendu = s?.attenduMois ?? 0;
    final encaisse = s?.encaisseMois ?? 0;
    final reste = s?.resteAEncaisser ?? 0;
    final taux = s?.tauxRecouvrement ?? 0;
    final progress = attendu > 0 ? (encaisse / attendu).clamp(0.0, 1.0) : 0.0;

    return AppCard(
      color: AppColors.blue.withOpacity(0.06),
      border: Border.all(color: AppColors.blue.withOpacity(0.2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.account_balance_wallet_rounded, color: AppColors.blue, size: 18),
          const SizedBox(width: 8),
          Text(t.cockpitTitle,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: context.cText)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: AppColors.blue.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: Text(t.cockpitRecovery(taux.toStringAsFixed(0)),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: AppColors.blue)),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          _metric(context, t.cockpitExpected, attendu, context.cText),
          _metric(context, t.cockpitCollected, encaisse, AppColors.success),
          _metric(context, t.cockpitRemaining, reste, reste > 0 ? AppColors.danger : AppColors.success),
        ]),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: context.cBorder,
            valueColor: const AlwaysStoppedAnimation(AppColors.success),
          ),
        ),
      ]),
    );
  }

  Widget _metric(BuildContext context, String label, int value, Color color) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: context.cTextSub)),
          const SizedBox(height: 2),
          Text(formatMontant(value.toDouble()),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
          Text('FCFA', style: TextStyle(fontSize: 9, color: context.cHint)),
        ]),
      );
}

/// Initiales (2 lettres max) depuis un nom complet, repli sur « ? ».
String _initiales(String nom) {
  final mots = nom.split(RegExp(r'\s+')).where((m) => m.isNotEmpty).toList();
  if (mots.length >= 2) return (mots[0][0] + mots[1][0]).toUpperCase();
  if (mots.length == 1) {
    return mots[0].substring(0, mots[0].length >= 2 ? 2 : 1).toUpperCase();
  }
  return '?';
}

/// Ligne actionnable « à encaisser » : locataire, montant dû, retard + bouton Relancer.
class _AEncaisserRow extends StatefulWidget {
  final LocataireAEncaisser item;
  final VoidCallback onReminded;
  final VoidCallback onOpen;
  const _AEncaisserRow({required this.item, required this.onReminded, required this.onOpen});

  @override
  State<_AEncaisserRow> createState() => _AEncaisserRowState();
}

class _AEncaisserRowState extends State<_AEncaisserRow> {
  bool _busy = false;

  Future<void> _relancer() async {
    setState(() => _busy = true);
    final t = AppLocalizations.of(context);
    final r = await LocataireService().envoyerRappel(widget.item.locataireId.toString());
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r != null ? t.cockpitReminderSent : t.networkError),
      backgroundColor: r != null ? AppColors.success : AppColors.danger,
    ));
    if (r != null) widget.onReminded();
  }

  /// Crée la demande d'encaissement puis ouvre la feuille de partage du lien.
  Future<void> _demander() async {
    setState(() => _busy = true);
    final t = AppLocalizations.of(context);
    final res = await PaiementService().creerDemandePaiement(widget.item.locataireId);
    if (!mounted) return;
    setState(() => _busy = false);
    final url = res['url'] as String?;
    if (url == null || url.isEmpty) {
      final err = res['error'];
      final msg = (err is String && err.contains('marchand')) ? t.merchantNotConfigured : t.networkError;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.danger));
      return;
    }
    if (!mounted) return;
    _showLienSheet(url);
  }

  void _showLienSheet(String url) {
    final t = AppLocalizations.of(context);
    final it = widget.item;
    final message = t.rentRequestMessage(formatMontant(it.montantDu.toDouble()), url);
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22),
              const SizedBox(width: 8),
              Text(t.paymentLinkCreated,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: context.cText)),
            ]),
            const SizedBox(height: 6),
            Text(it.nom, style: TextStyle(fontSize: 13, color: context.cTextSub)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () { Navigator.pop(sheetCtx); _envoyerWhatsApp(it.telephone, message); },
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
                onPressed: () { Clipboard.setData(ClipboardData(text: url)); Navigator.pop(sheetCtx);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.linkCopied))); },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: Text(t.copyLink, style: const TextStyle(fontSize: 12)),
              )),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton.icon(
                onPressed: () { Navigator.pop(sheetCtx); launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); },
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text(t.openLink, style: const TextStyle(fontSize: 12)),
              )),
            ]),
          ]),
        ),
      ),
    );
  }

  void _envoyerWhatsApp(String tel, String message) {
    var d = tel.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.isNotEmpty && !d.startsWith('237')) d = '237$d';
    final uri = Uri.parse('https://wa.me/$d?text=${Uri.encodeComponent(message)}');
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final it = widget.item;
    final retardColor = it.joursRetard > 0 ? AppColors.danger : AppColors.warning;
    return GestureDetector(
      onTap: widget.onOpen,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: context.cCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.cBorder)),
        child: Row(children: [
          CircleAvatar2(initiales: _initiales(it.nom), bg: context.cDangerBg, fg: AppColors.danger, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.nom,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: context.cText)),
              Text(t.cockpitAmountDue(formatMontant(it.montantDu.toDouble())),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.danger)),
              Text(it.partiel ? t.cockpitPartial : t.cockpitLateDays(it.joursRetard),
                  style: TextStyle(fontSize: 10, color: it.partiel ? AppColors.warning : retardColor)),
            ]),
          ),
          const SizedBox(width: 8),
          if (_busy)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Column(mainAxisSize: MainAxisSize.min, children: [
              ElevatedButton(
                onPressed: _demander,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.blue, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(t.askRent, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              GestureDetector(
                onTap: _relancer,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(t.cockpitRemind,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.blue)),
                ),
              ),
            ]),
        ]),
      ),
    );
  }
}

Widget _PaiRow(Paiement p, BuildContext context) => GestureDetector(
      onTap: () => Navigator.push(context, heroRoute(DetailPaiementScreen(paiement: p))),
      child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: context.cCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.cBorder)),
      child: Row(children: [
        CircleAvatar2(
            initiales: p.initiales,
            bg: context.cSuccessBg,
            fg: AppColors.success,
            size: 38),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.nomLocataire,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: context.cText)),
          Text(p.logement,
              style: TextStyle(fontSize: 11, color: context.cTextSub)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${formatMontant(p.montant)} FCFA',
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: AppColors.blue)),
          Text(relativeDate(p.datePaiement),
              style: TextStyle(fontSize: 10, color: context.cHint)),
        ]),
        const SizedBox(width: 8),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
                color: context.cSuccessBg,
                borderRadius: BorderRadius.circular(8)),
            child: Text(AppLocalizations.of(context).statusPaid,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success))),
      ]),
    ));
