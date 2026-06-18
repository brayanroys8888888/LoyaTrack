import 'dart:ui' as import_ui;
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../core/abonnement_provider.dart';
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

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final stats = _stats;
    final payes = stats?.loyersPayes ?? 0;
    final impayes = stats?.impayes ?? 0;
    final total = stats?.totalLocataires ?? 0;
    final revenu = stats?.revenusEncaisses ?? 0;

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
                    // Revenu card
                    AppCard(
                      color: AppColors.blue.withOpacity(0.08),
                      border: Border.all(color: AppColors.blue.withOpacity(0.2)),
                      child: Row(children: [
                        Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                                color: AppColors.blue,
                                borderRadius: BorderRadius.circular(13)),
                            child: const Icon(Icons.bar_chart_rounded,
                                color: Colors.white, size: 24)),
                        const SizedBox(width: 12),
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.revenueThisMonth,
                                  style: TextStyle(
                                      fontSize: 11, color: context.cTextSub)),
                              Text('${formatMontant(revenu)} FCFA',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 20,
                                      color: AppColors.blue)),
                              Text(t.paymentsReceived(payes),
                                  style: TextStyle(
                                      fontSize: 11, color: context.cTextSub)),
                            ]),
                        const Spacer(),
                        const Icon(Icons.trending_up_rounded,
                            color: AppColors.success, size: 22),
                      ]),
                    ),
                    const SizedBox(height: 18),
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

  _DashboardHeaderDelegate({
    required this.safeAreaTop,
    required this.onAdd,
    required this.context,
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
                        initiales: 'BR',
                        bg: Colors.white.withOpacity(0.2),
                        fg: Colors.white,
                        size: avatarSize),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          Text(AppLocalizations.of(context).dashGreeting,
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
                      Positioned(
                          top: -2,
                          right: -2,
                          child: Opacity(
                            opacity: 1 - (progress * 0.5), // Keep slightly visible or fade it
                            child: Container(
                              width: 17,
                              height: 17,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.red.shade600,
                                  border: Border.all(
                                      color: isCollapsed ? context.bg : const Color(0xFF1565C0), width: 1.5)),
                              alignment: Alignment.center,
                              child: const Text('3',
                                  style: TextStyle(
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
