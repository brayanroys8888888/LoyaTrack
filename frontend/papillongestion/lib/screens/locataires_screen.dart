import 'package:flutter/material.dart';
import 'dart:ui' as import_ui;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../widgets/shared_widgets.dart';
import 'detail_screen.dart';
import 'add_locataire_screen.dart';
import 'import_locataires_screen.dart';
import '../services/locataire_service.dart';

class LocatairesScreen extends StatefulWidget {
  const LocatairesScreen({super.key});
  @override
  State<LocatairesScreen> createState() => _LocatairesScreenState();
}

class _LocatairesScreenState extends State<LocatairesScreen> {
  StatutLocataire? _filter;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSearching = false;
  List<Locataire> _allLocataires = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    _allLocataires = await LocataireService().getLocataires();
    if (mounted) setState(() => _isLoading = false);
  }

  // Appel pour le RefreshIndicator (sans remettre le skeleton complet)
  Future<void> _onRefresh() async {
    final fresh = await LocataireService().getLocataires();
    if (mounted) setState(() => _allLocataires = fresh);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<Locataire> get filtered {
    var list = _allLocataires;
    if (_filter != null) list = list.where((l) => l.statut == _filter).toList();
    final query = _searchController.text.toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((l) => l.nom.toLowerCase().contains(query)).toList();
    }
    return list;
  }

  int _count(StatutLocataire s) =>
      _allLocataires.where((l) => l.statut == s).length;

  @override
  Widget build(BuildContext context) {
    final list = filtered;
    final t = AppLocalizations.of(context);
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
              controller: _scrollController,
              // IMPORTANT: sans AlwaysScrollableScrollPhysics, le RefreshIndicator
              // ne se déclenche pas quand la liste est courte
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
              // ── Header principal animé ──
              SliverPersistentHeader(
                pinned: true,
                delegate: _LocatairesHeaderDelegate(
                  safeAreaTop: safeTop,
                  searchController: _searchController,
                  isSearching: _isSearching,
                  onToggleSearch: () =>
                      setState(() => _isSearching = !_isSearching),
                  onAddTap: () async {
                    final result = await Navigator.push(
                        context,
                        modalRoute(const AddLocataireScreen()));
                    if (result == true) _fetchData();
                  },
                  onImportTap: () async {
                    final result = await Navigator.push(
                        context,
                        slideRoute(const ImportLocatairesScreen()));
                    if (result != false) _fetchData();
                  },
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
                        _chip(
                            t.filterAll(_allLocataires.length),
                            _filter == null,
                            AppColors.blue,
                            context,
                            () => setState(() => _filter = null)),
                        const SizedBox(width: 8),
                        _chip(
                            t.filterPaid(_count(StatutLocataire.paye)),
                            _filter == StatutLocataire.paye,
                            AppColors.success,
                            context,
                            () =>
                                setState(() => _filter = StatutLocataire.paye)),
                        const SizedBox(width: 8),
                        _chip(
                            t.filterLate(_count(StatutLocataire.nonPaye)),
                            _filter == StatutLocataire.nonPaye,
                            AppColors.danger,
                            context,
                            () => setState(
                                () => _filter = StatutLocataire.nonPaye)),
                        const SizedBox(width: 8),
                        _chip(
                            t.filterDiscussion,
                            _filter == StatutLocataire.enDiscussion,
                            AppColors.warning,
                            context,
                            () => setState(
                                () => _filter = StatutLocataire.enDiscussion)),
                        const SizedBox(width: 8),
                        _chip(
                            t.filterPenalty,
                            _filter == StatutLocataire.enPenalite,
                            AppColors.penalty,
                            context,
                            () => setState(
                                () => _filter = StatutLocataire.enPenalite)),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Compteur ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                      t.tenantsCount(list.length),
                      style: TextStyle(
                          fontSize: 12,
                          color: context.cTextSub,
                          fontWeight: FontWeight.w600)),
                ),
              ),

              // ── Liste ──
              if (_isLoading)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, __) => const LocataireCardSkeleton(),
                      childCount: 6,
                    ),
                  ),
                )
              else if (list.isEmpty)
                SliverToBoxAdapter(
                  child: Center(
                      child: Padding(
                          padding: const EdgeInsets.all(60),
                          child: Column(
                            children: [
                              Icon(Icons.people_alt_outlined, size: 48, color: context.cBorder),
                              const SizedBox(height: 12),
                              Text(t.noTenantsFound,
                                  style: TextStyle(color: context.cTextSub, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(t.pullToRefresh,
                                  style: TextStyle(color: context.cHint, fontSize: 12)),
                            ],
                          ))),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => LocataireCard(
                          loc: list[i],
                          onTap: () => Navigator.push(
                              context,
                              heroRoute(
                                  DetailLocataireScreen(locataire: list[i])))),
                      childCount: list.length,
                    ),
                  ),
                ),
            ],
          ),
          ),  // end RefreshIndicator
        ],
      ),
    );
  }

  Widget _chip(String label, bool active, Color color, BuildContext context,
          VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? color : context.cCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? color : context.cBorder),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : context.cTextSub)),
        ),
      );
}

class _FiltersHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _FiltersHeaderDelegate({required this.child});

  @override
  double get minExtent => 54;
  @override
  double get maxExtent => 54;
  @override
  bool shouldRebuild(covariant _FiltersHeaderDelegate old) => true;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: context.bg,
      padding: const EdgeInsets.symmetric(vertical: 8),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }
}

class _LocatairesHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double safeAreaTop;
  final TextEditingController searchController;
  final bool isSearching;
  final VoidCallback onToggleSearch;
  final VoidCallback onAddTap;
  final VoidCallback onImportTap;

  _LocatairesHeaderDelegate({
    required this.safeAreaTop,
    required this.searchController,
    required this.isSearching,
    required this.onToggleSearch,
    required this.onAddTap,
    required this.onImportTap,
  });

  @override
  double get maxExtent => safeAreaTop + 130;
  @override
  double get minExtent => safeAreaTop + 116;
  @override
  bool shouldRebuild(covariant _LocatairesHeaderDelegate old) => true;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
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
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 24 * (1 - t),
              decoration: BoxDecoration(
                color: context.bg,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24 * (1 - t))),
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
                      child: Text(AppLocalizations.of(context).tenantsTitle,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 22 - (2 * t),
                            color: collapsed ? context.cText : Colors.white,
                          )),
                    ),
                    // Import button
                    GestureDetector(
                      onTap: onImportTap,
                      child: Container(
                        width: 36, height: 36,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: collapsed ? context.cCard : Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: collapsed ? Border.all(color: context.cBorder) : null,
                        ),
                        child: Icon(Icons.upload_file_rounded,
                            color: collapsed ? context.cText : Colors.white, size: 18),
                      ),
                    ),
                    // Add button
                    GestureDetector(
                      onTap: onAddTap,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: collapsed
                              ? AppColors.blue
                              : Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: collapsed
                              ? Border.all(color: AppColors.blue)
                              : null,
                        ),
                        child: const Icon(Icons.add_rounded,
                            color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
                // Full Search Bar (always visible)
                Container(
                  height: 44,
                  margin: const EdgeInsets.only(top: 12),
                  child: _fullSearch(context, collapsed),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _fullSearch(BuildContext context, bool collapsed) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: import_ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: collapsed ? context.cCard : Colors.white.withOpacity(0.15),
            border: Border.all(color: collapsed ? context.cBorder : Colors.white.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: collapsed ? AppColors.blue : Colors.white70, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: searchController,
                  style: TextStyle(color: collapsed ? context.cText : Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context).searchTenant,
                    hintStyle: TextStyle(color: collapsed ? context.cHint : Colors.white70),
                    fillColor: Colors.transparent,
                    focusColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              if (searchController.text.isNotEmpty)
                GestureDetector(
                  onTap: () => searchController.clear(),
                  child: Icon(Icons.cancel_rounded,
                      color: collapsed ? context.cHint : Colors.white70, size: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
