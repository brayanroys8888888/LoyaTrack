import 'dart:ui' as import_ui;
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../widgets/shared_widgets.dart';
import '../widgets/pro_gate.dart';
import 'detail_paiement_screen.dart';
import 'add_paiement_screen.dart';
import '../services/paiement_service.dart';
import '../services/dashboard_service.dart';
import '../core/pdf_helper.dart';

class HistoriqueScreen extends StatefulWidget {
  const HistoriqueScreen({super.key});
  @override
  State<HistoriqueScreen> createState() => _HistoriqueScreenState();
}

class _HistoriqueScreenState extends State<HistoriqueScreen> {
  ModePaiement? _mode;

  List<Paiement> _allPaiements = [];
  DashboardStats? _stats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      PaiementService().getPaiements(),
      DashboardService().getStats(),
    ]);
    _allPaiements = results[0] as List<Paiement>;
    _stats = results[1] as DashboardStats?;
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _onRefresh() async {
    final results = await Future.wait([
      PaiementService().getPaiements(),
      DashboardService().getStats(),
    ]);
    if (mounted) {
      setState(() {
        _allPaiements = results[0] as List<Paiement>;
        _stats = results[1] as DashboardStats?;
      });
    }
  }

  List<Paiement> get _filtered => _mode == null
      ? _allPaiements
      : _allPaiements.where((p) => p.mode == _mode).toList();

  Map<String, List<Paiement>> get _grouped {
    final map = <String, List<Paiement>>{};
    for (final p in _filtered) {
      map.putIfAbsent(p.moisConcerne, () => []).add(p);
    }
    return map;
  }

  // Exemple: calcul du total du mois en cours
  double get _totalMoisEnCours {
    if (_allPaiements.isEmpty) return 0.0;
    // On pourrait filtrer dynamiquement par le mois actuel, ici on prend juste le mois le plus récent
    final latestMois = _allPaiements.first.moisConcerne;
    return _allPaiements
        .where((p) => p.moisConcerne == latestMois)
        .fold(0.0, (s, p) => s + p.montant);
  }
  
  String get _moisEnCoursLabel {
    if (_allPaiements.isEmpty) return '';
    return _allPaiements.first.moisConcerne;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final filtered = _filtered;
    final grouped = _grouped;
    final safeTop = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: context.bg,
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _onRefresh,
            color: AppColors.blue,
            backgroundColor: context.cCard,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
          // ── Header principal animé ──
          SliverPersistentHeader(
            pinned: true,
            delegate: _HistoriqueHeaderDelegate(
              safeAreaTop: safeTop,
              onExportTap: _exporter,
              onAddTap: () async {
                final result = await Navigator.push(context, modalRoute(const AddPaiementScreen()));
                if (result == true) _fetchData();
              },
            ),
          ),

          // ── Stats ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _statCard(context, t.dashTotal, '${formatMontant(_totalMoisEnCours)} F', _moisEnCoursLabel, context.cSuccessBg, AppColors.success)),
                      const SizedBox(width: 10),
                      Expanded(child: _statCard(context, t.histPaymentsShort, '${filtered.length}', t.histThisMonth, context.cBlue3, AppColors.blue)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _statCard(context, t.dashUnpaid, '${_stats?.impayes ?? 0}', t.histTenantsSub, context.cDangerBg, AppColors.danger)),
                      const SizedBox(width: 10),
                      Expanded(child: _statCard(context, t.histPenaltiesShort, formatMontant(_stats?.penalitesDues ?? 0), 'FCFA', context.cWarningBg, AppColors.warning)),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Filtres sticky ──
          SliverPersistentHeader(
            pinned: true,
            delegate: _FiltersHeaderDelegate(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _chip(context, t.allLabel, _mode == null, () => setState(() => _mode = null)),
                    const SizedBox(width: 8),
                    ...ModePaiement.values.map((m) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _chip(context, modeLabelL(m, t), _mode == m, () => setState(() => _mode = m)),
                        )),
                  ],
                ),
              ),
            ),
          ),

          // ── Liste ──
          if (_isLoading)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, __) => const LocataireCardSkeleton(),
                  childCount: 6,
                ),
              ),
            )
          else if (filtered.isEmpty)
            SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(60),
                  child: Column(
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 52, color: context.cHint),
                      const SizedBox(height: 12),
                      Text(t.noPayments, style: TextStyle(color: context.cTextSub, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            )
          else
            ..._buildGroupedSlivers(context, grouped),

          const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
          ), // End RefreshIndicator
        ],
      ),
    );
  }

  /// Bottom sheet de choix de format puis export+ouverture de la liste filtrée.
  Future<void> _exporter() async {
    if (!exigerFonction(context, 'comptabilite')) return;
    final t = AppLocalizations.of(context);
    final fmt = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.cCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 16),
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: context.cBorder, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Text(t.exportTitle, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: context.cText)),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.danger),
            title: const Text('PDF'),
            onTap: () => Navigator.pop(sheetCtx, 'pdf'),
          ),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined, color: AppColors.success),
            title: const Text('Excel'),
            onTap: () => Navigator.pop(sheetCtx, 'excel'),
          ),
          const SizedBox(height: 12),
        ]),
      ),
    );
    if (fmt == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(t.exportInProgress)));
    final bytes = await PaiementService().exporterPaiements(
      format: fmt,
      mode: _mode?.label, // libellé FR du mode si un filtre est actif
    );
    if (!mounted) return;
    if (bytes == null) {
      messenger.showSnackBar(SnackBar(content: Text(t.generationError), backgroundColor: AppColors.danger));
      return;
    }
    await ouvrirPdf(context, bytes, fmt == 'excel' ? 'paiements.xlsx' : 'paiements.pdf');
  }

  List<Widget> _buildGroupedSlivers(BuildContext context, Map<String, List<Paiement>> grouped) {
    final slivers = <Widget>[];
    for (final entry in grouped.entries) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          sliver: SliverToBoxAdapter(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(entry.key.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: context.cTextSub, letterSpacing: 1.0)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: context.cSuccessBg, borderRadius: BorderRadius.circular(10)),
                  child: Text('${formatMontant(entry.value.fold(0.0, (s, p) => s + p.montant))} F',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: AppColors.success)),
                ),
              ],
            ),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _paiementCard(ctx, entry.value[i]),
              childCount: entry.value.length,
            ),
          ),
        ),
      );
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 16)));
    }
    return slivers;
  }

  Widget _statCard(BuildContext context, String label, String value, String sub, Color bg, Color fg) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: context.cBorder)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: context.cTextSub, letterSpacing: 0.5), maxLines: 1),
            const SizedBox(height: 3),
            Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: fg), maxLines: 1),
            Text(sub, style: TextStyle(fontSize: 9, color: context.cTextSub), maxLines: 1),
          ]),
        ),
      );

  Widget _chip(BuildContext context, String label, bool active, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: active ? AppColors.blue : context.cCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? AppColors.blue : context.cBorder),
          ),
          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? Colors.white : context.cTextSub)),
        ),
      );

  Widget _paiementCard(BuildContext context, Paiement p) => GestureDetector(
        onTap: () => Navigator.push(context, heroRoute(DetailPaiementScreen(paiement: p))),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: context.cCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.cBorder)),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: p.mode.bgColor(context), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(p.mode.icon, color: p.mode.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.nomLocataire, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: context.cText)),
              const SizedBox(height: 3),
              Row(children: [
                Text(p.logement, style: TextStyle(fontSize: 11, color: context.cTextSub)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: p.mode.bgColor(context), borderRadius: BorderRadius.circular(6)),
                  child: Text(modeLabelL(p.mode, AppLocalizations.of(context)), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: p.mode.color)),
                ),
              ]),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('+${formatMontant(p.montant)} F', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.success)),
            const SizedBox(height: 2),
            Text(formatDate(p.datePaiement), style: TextStyle(fontSize: 10, color: context.cHint)),
          ]),
        ]),
      ));
}

class _FiltersHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _FiltersHeaderDelegate({required this.child});

  @override double get minExtent => 54;
  @override double get maxExtent => 54;
  @override bool shouldRebuild(covariant _FiltersHeaderDelegate old) => true;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: context.bg,
      padding: const EdgeInsets.symmetric(vertical: 8),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }
}

class _HistoriqueHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double safeAreaTop;
  final VoidCallback onExportTap;
  final VoidCallback onAddTap;

  _HistoriqueHeaderDelegate({
    required this.safeAreaTop,
    required this.onExportTap,
    required this.onAddTap,
  });

  @override double get maxExtent => safeAreaTop + 80;
  @override double get minExtent => safeAreaTop + 60;
  @override bool shouldRebuild(covariant _HistoriqueHeaderDelegate old) => true;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final t = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final collapsed = t >= 0.95;

    return Stack(
      children: [
        // Background
        Positioned.fill(
          child: collapsed
              ? ClipRect(
                  child: BackdropFilter(
                    filter: import_ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(color: context.bg.withOpacity(0.9)),
                  ),
                )
              : Container(decoration: const BoxDecoration(gradient: kGradient)),
        ),
        
        // Rounded bottom corner (only when expanded)
        if (!collapsed)
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              height: 24 * (1 - t),
              decoration: BoxDecoration(
                color: context.bg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24 * (1 - t))),
              ),
            ),
          ),

        // Content
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(AppLocalizations.of(context).tabHistory,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 22 - (2 * t),
                            color: collapsed ? context.cText : Colors.white,
                          )),
                    ),
                    
                    // Export (PDF/Excel de la liste filtrée)
                    GestureDetector(
                      onTap: onExportTap,
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: collapsed ? context.cCard : Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: collapsed ? Border.all(color: context.cBorder) : null,
                        ),
                        child: Icon(Icons.ios_share_rounded, color: collapsed ? context.cText : Colors.white, size: 18),
                      ),
                    ),
                    // Ajouter un paiement
                    GestureDetector(
                      onTap: onAddTap,
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: collapsed ? AppColors.blue : Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: collapsed ? Border.all(color: AppColors.blue) : null,
                        ),
                        child: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
