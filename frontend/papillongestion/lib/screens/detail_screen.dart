import 'dart:ui' as import_ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../widgets/shared_widgets.dart';
import '../widgets/pro_gate.dart';
import 'add_locataire_screen.dart';
import 'add_paiement_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/paiement_service.dart';
import '../services/locataire_service.dart';
import '../core/pdf_helper.dart';
import 'gestion_locataire_screen.dart';

class DetailLocataireScreen extends StatefulWidget {
  final Locataire locataire;
  const DetailLocataireScreen({required this.locataire, super.key});

  @override
  State<DetailLocataireScreen> createState() => _DetailLocataireScreenState();
}

class _DetailLocataireScreenState extends State<DetailLocataireScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Locataire get loc => widget.locataire;

  List<Paiement> _historique = [];
  List<Rappel> _rappels = [];
  bool _loadingHist = true;
  bool _loadingRappels = true;

  bool get hasPenalite => loc.statut == StatutLocataire.enPenalite;
  double get montantPenalite => loc.penaliteJournaliere * 4;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _fetchHistorique();
    _fetchRappels();
  }

  Future<void> _fetchHistorique() async {
    final paiements = await PaiementService().getPaiements(locataireId: loc.id);
    if (mounted) setState(() { _historique = paiements; _loadingHist = false; });
  }

  Future<void> _fetchRappels() async {
    final list = await LocataireService().getRappels(loc.id);
    if (mounted) setState(() { _rappels = list; _loadingRappels = false; });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: context.bg,
      body: NestedScrollView(
        headerSliverBuilder: (ctx, innerBoxIsScrolled) => [
          // ── Header Profil Animé ──
          SliverPersistentHeader(
            pinned: true,
            delegate: _DetailHeaderDelegate(
              loc: loc,
              safeTop: safeTop,
              onBack: () => Navigator.pop(context),
              onEdit: () async {
                final result = await Navigator.push(context, modalRoute(AddLocataireScreen(locataire: loc)));
                if (result == true && context.mounted) Navigator.pop(context, true); // Pop to trigger refresh
              },
              menuWidget: _menuBtn(false, context), // On gérera la couleur dans le delegate
            ),
          ),
          
          // ── TabBar Sticky ──
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              bgColor: context.bg,
              tabBar: TabBar(
                controller: _tabs,
                labelColor: AppColors.blue,
                unselectedLabelColor: context.cTextSub,
                indicatorColor: AppColors.blue,
                indicatorWeight: 3,
                dividerColor: context.cBorder,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                tabs: [Tab(text: AppLocalizations.of(context).tabDetails), Tab(text: AppLocalizations.of(context).tabHistory), Tab(text: AppLocalizations.of(context).tabReminders)],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabs,
          children: [
            _DetailsTab(loc: loc, hasPenalite: hasPenalite, montantPenalite: montantPenalite, onRappelSent: _fetchRappels),
            _loadingHist ? const Center(child: CircularProgressIndicator()) : _HistoryTab(historique: _historique),
            _loadingRappels ? const Center(child: CircularProgressIndicator()) : _RemindersTab(rappels: _rappels),
          ],
        ),
      ),
    );
  }

  Widget _menuBtn(bool collapsed, BuildContext context) => Builder(builder: (ctx) {
        // La couleur de l'icône dépendra du builder Parent dans le delegate,
        // mais pour simplifier on passe un paramètre au delegate ou on utilise le theme.
        return PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          color: context.cCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onSelected: (val) async {
            if (val == 'statut') {
              await _choisirStatut(context);
            } else if (val == 'delete') {
              final tt = AppLocalizations.of(context);
              final confirmed = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
                title: Text(tt.delete),
                content: Text(tt.deleteTenantConfirm),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tt.cancel)),
                  TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tt.delete, style: const TextStyle(color: AppColors.danger))),
                ],
              ));
              if (confirmed == true && context.mounted) {
                final success = await LocataireService().deleteLocataire(loc.id);
                if (success && context.mounted) Navigator.pop(context, true);
              }
            }
          },
          itemBuilder: (_) => [
            _menuItem('statut', Icons.swap_horiz_rounded, AppLocalizations.of(context).changeStatus, AppColors.warning),
            _menuItem('delete', Icons.delete_outline_rounded, AppLocalizations.of(context).deleteTenant, AppColors.danger),
          ],
        );
      });

  /// Sélecteur de statut : bottom sheet listant les 4 statuts. Le changement
  /// appelle l'action backend puis referme la fiche (true) pour rafraîchir la liste.
  Future<void> _choisirStatut(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final choix = await showFormSheet<StatutLocataire>(context, builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            sheetHeader(ctx, t.changeStatus),
            const SizedBox(height: 4),
            // Seules les transitions manuelles utiles : « Payé » se fait via un
            // paiement, « Pénalité » est calculée par le moteur.
            ...[StatutLocataire.nonPaye, StatutLocataire.enDiscussion].map((s) {
              final selected = s == loc.statut;
              return ListTile(
                leading: Container(width: 14, height: 14,
                    decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                title: Text(statutLabelL(s, t),
                    style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                trailing: selected ? Icon(Icons.check_rounded, color: s.color) : null,
                onTap: () => Navigator.pop(ctx, s),
              );
            }),
            const SizedBox(height: 8),
          ],
        ));
    if (choix == null || choix == loc.statut || !context.mounted) return;
    final success = await LocataireService().changerStatut(loc.id, choix);
    if (!context.mounted) return;
    final msg = !success
        ? t.genericError
        : (choix == StatutLocataire.enDiscussion ? t.markInDiscussionDone : t.statusChanged);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? AppColors.success : AppColors.danger,
    ));
    if (success) Navigator.pop(context, true);
  }

  PopupMenuItem<String> _menuItem(String val, IconData icon, String label, Color color) => PopupMenuItem(
        value: val,
        child: Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      );
}

class _DetailHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Locataire loc;
  final double safeTop;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final Widget menuWidget;

  _DetailHeaderDelegate({
    required this.loc,
    required this.safeTop,
    required this.onBack,
    required this.onEdit,
    required this.menuWidget,
  });

  @override double get maxExtent => safeTop + 220;
  @override double get minExtent => safeTop + 60;
  @override bool shouldRebuild(covariant _DetailHeaderDelegate old) => true;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final isCollapsed = progress == 1.0;

    return Stack(
      children: [
        // Background Premium Gradient
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: isCollapsed ? null : const LinearGradient(
                colors: [Color(0xFF1A237E), Color(0xFF0D47A1), Color(0xFF1B5E20)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              color: isCollapsed ? context.bg.withOpacity(0.85) : null,
            ),
            child: isCollapsed
                ? ClipRect(
                    child: BackdropFilter(
                      filter: import_ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(color: Colors.transparent),
                    ),
                  )
                : null,
          ),
        ),

        // Glassmorphism Overlay
        if (!isCollapsed)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.white.withOpacity(0.1), Colors.transparent],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),

        // Rounded bottom corner
        if (!isCollapsed)
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              height: 28 * (1 - progress),
              decoration: BoxDecoration(
                color: context.bg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24 * (1 - progress))),
              ),
            ),
          ),

        // Content — même animation que le header Réglages : groupe centré
        // (avatar + nom + tags) qui se fond vers une rangée avatar+nom réduite.
        SafeArea(
          bottom: false,
          child: Stack(
            children: [
              // ── Boutons haut (toujours visibles) ──
              Positioned(
                left: 0, right: 0, top: 0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios_new_rounded, color: isCollapsed ? context.cText : Colors.white, size: 18),
                      onPressed: onBack,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.edit_rounded, color: isCollapsed ? context.cText : Colors.white, size: 20),
                      onPressed: onEdit,
                    ),
                    Theme(
                      data: Theme.of(context).copyWith(
                        iconTheme: IconThemeData(color: isCollapsed ? context.cText : Colors.white),
                      ),
                      child: menuWidget,
                    ),
                  ]),
                ),
              ),

              // ── État étendu : groupe centré (avatar + nom + tags) ──
              if (progress < 0.98)
                Positioned.fill(
                  child: ClipRect(
                    child: Opacity(
                      opacity: (1 - progress).clamp(0.0, 1.0),
                      child: OverflowBox(
                        minHeight: 0, maxHeight: 360, alignment: Alignment.center,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Hero(
                                tag: 'avatar-loc-${loc.id}',
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: CircleAvatar2(
                                    initiales: loc.initiales,
                                    bg: Colors.white.withOpacity(0.2),
                                    fg: Colors.white,
                                    size: 72,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(loc.nom, textAlign: TextAlign.center,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: Colors.white)),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _tag(loc.logement, Icons.home_outlined),
                                  const SizedBox(width: 8),
                                  _tag(statutLabelL(loc.statut, AppLocalizations.of(context)), null, isStatus: true, status: loc.statut),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // ── État réduit : avatar + nom à gauche (après le bouton retour) ──
              if (progress > 0.6)
                Positioned.fill(
                  child: Opacity(
                    opacity: ((progress - 0.6) / 0.4).clamp(0.0, 1.0),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 44, right: 96),
                      child: Row(children: [
                        CircleAvatar2(initiales: loc.initiales, bg: context.cBlue3, fg: AppColors.blue, size: 36),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(loc.nom, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: context.cText)),
                        ),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tag(String text, IconData? icon, {bool isStatus = false, StatutLocataire? status}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isStatus ? status!.color.withOpacity(0.2) : Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isStatus ? status!.color.withOpacity(0.3) : Colors.white.withOpacity(0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) Icon(icon, color: Colors.white, size: 12),
          if (icon != null) const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color bgColor;

  _TabBarDelegate({required this.tabBar, required this.bgColor});

  @override double get minExtent => tabBar.preferredSize.height;
  @override double get maxExtent => tabBar.preferredSize.height;
  @override bool shouldRebuild(covariant _TabBarDelegate old) => true;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: bgColor,
      child: tabBar,
    );
  }
}

class _DetailsTab extends StatelessWidget {
  final Locataire loc;
  final bool hasPenalite;
  final double montantPenalite;
  final VoidCallback onRappelSent;
  const _DetailsTab({required this.loc, required this.hasPenalite, required this.montantPenalite, required this.onRappelSent});

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  Future<void> _sendRappel(BuildContext context, String type) async {
    final t = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.sendingReminder(type))));
    final result = await LocataireService().envoyerRappel(loc.id, typeRappel: type);
    if (!context.mounted) return;
    if (result != null && result.statut == StatutRappel.envoye) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.reminderSent(type)), backgroundColor: AppColors.success));
      onRappelSent();
    } else if (result != null) {
      // Le rappel est enregistré mais l'envoi a échoué (souvent : quota/numéro non vérifié Twilio).
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t.reminderFailedQuota(type)),
        backgroundColor: AppColors.danger));
      onRappelSent();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.reminderFailed(type)), backgroundColor: AppColors.danger));
    }
  }

  Future<void> _partagerPortail(BuildContext context, String locataireId) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(t.generatingLink)));
    final lien = await LocataireService().genererLienPortail(locataireId, envoyerSms: true);
    if (!context.mounted) return;
    if (lien == null) {
      messenger.showSnackBar(SnackBar(content: Text(t.generationError), backgroundColor: AppColors.danger));
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.cCard,
        title: Text(t.tenantPortal, style: TextStyle(color: context.cText)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.portalLinkSentMsg,
              style: TextStyle(fontSize: 13, color: context.cTextSub)),
          const SizedBox(height: 10),
          SelectableText(lien, style: const TextStyle(fontSize: 12, color: AppColors.blue)),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: lien));
              Navigator.pop(context);
              messenger.showSnackBar(SnackBar(content: Text(t.linkCopied), backgroundColor: AppColors.success));
            },
            child: Text(t.copy),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t.close)),
        ],
      ),
    );
  }

  Future<void> _demarrerTest(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t.testCycleTitle),
        content: Text(t.testCycleMsg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
            child: Text(t.start, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.testStarted), backgroundColor: AppColors.warning),
    );
    final result = await LocataireService().demarrerTest(loc.id);
    if (context.mounted) {
      if (result != null) {
        onRappelSent();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.testStartError), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Loyer Hero Card
          _GlassCard(
            child: Column(children: [
              Text(t.monthlyRent.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.cTextSub, letterSpacing: 1.5)),
              const SizedBox(height: 8),
              Text('${formatMontant(loc.montantLoyer)} FCFA', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.blue, letterSpacing: -1)),
              const SizedBox(height: 4),
              Text(t.dueOnDay(loc.jourEcheance), style: TextStyle(fontSize: 13, color: context.cTextSub)),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: _actionBtn(t.payNow, Icons.check_circle_outline, AppColors.success, () {
                  Navigator.push(context, modalRoute(AddPaiementScreen(initialLocataire: loc)));
                })),
                const SizedBox(width: 12),
                _iconActionBtn(Icons.chat_bubble_outline_rounded, AppColors.warning, () => _sendRappel(context, 'SMS')),
              ]),
            ]),
          ),
          if (hasPenalite) ...[
            const SizedBox(height: 16),
            _GlassCard(
              color: context.cPenaltyBg.withOpacity(0.5),
              borderColor: AppColors.danger.withOpacity(0.3),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 16),
                  const SizedBox(width: 6),
                  Text(t.latePenaltyTitle.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.danger, letterSpacing: 1)),
                ]),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${formatMontant(montantPenalite)} FCFA', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.danger)),
                    Text(t.daysLateCumulative(4), style: TextStyle(fontSize: 12, color: context.cTextSub)),
                  ]),
                  _iconActionBtn(Icons.info_outline, AppColors.danger, () {}),
                ]),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          // Info List
          _GlassCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              _infoRow(context, Icons.phone_outlined, t.phone, loc.telephone),
              _div(context),
              _infoRow(context, Icons.calendar_today_outlined, t.entryDate, formatDate(loc.dateEntree)),
              _div(context),
              _infoRow(context, Icons.home_outlined, t.housing, loc.logement),
              _div(context),
              _infoRow(context, Icons.money_off_csred_outlined, t.penaltyPerDay, '${formatMontant(loc.penaliteJournaliere)} F'),
              if (loc.notes != null) ...[
                _div(context),
                _infoRow(context, Icons.notes_rounded, t.notes, loc.notes!, isLast: true),
              ],
            ]),
          ),
          const SizedBox(height: 16),
          // Quick Actions
          Row(children: [
            _sqBtn(context, Icons.phone_rounded, t.call, AppColors.blue, () => _makePhoneCall(loc.telephone)),
            const SizedBox(width: 8),
            _sqBtn(context, Icons.message_rounded, t.rappelSms, AppColors.success, () => _sendRappel(context, 'SMS')),
            const SizedBox(width: 8),
            _sqBtn(context, Icons.wechat_rounded, t.rappelWhatsapp, const Color(0xFF25D366), () => _sendRappel(context, 'WhatsApp')),
            const SizedBox(width: 8),
            _sqBtn(context, Icons.smart_toy_rounded, t.callAIShort, AppColors.warning, () => _sendRappel(context, 'Appel')),
          ]),
          const SizedBox(height: 12),
          // Contrat de bail PDF (2.2)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                if (!exigerFonction(context, 'documents_legaux')) return;
                final messenger = ScaffoldMessenger.of(context);
                messenger.showSnackBar(SnackBar(content: Text(t.generatingContract)));
                final bytes = await LocataireService().getContratPdf(loc.id);
                if (!context.mounted) return;
                await ouvrirPdf(context, bytes, 'contrat_${loc.id}.pdf');
              },
              icon: const Icon(Icons.description_outlined, size: 18),
              label: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(t.downloadLease),
                const SizedBox(width: 8),
                const ProBadgeIfLocked('documents_legaux'),
              ]),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.blue,
                side: const BorderSide(color: AppColors.blue),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(context, slideRoute(GestionLocataireScreen(locataire: loc))),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: Text(t.manageTenant),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.cText,
                side: BorderSide(color: context.cBorder),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _partagerPortail(context, loc.id),
              icon: const Icon(Icons.public_rounded, size: 18),
              label: Text(t.shareTenantPortal),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.success,
                side: const BorderSide(color: AppColors.success),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          // Bouton Mode Test - visible uniquement pour les locataires test
          if (loc.modeTest) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _demarrerTest(context),
                icon: const Icon(Icons.science_rounded, size: 18),
                label: Text(t.runFullTestCycle),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: Row(children: [
                Icon(Icons.info_outline_rounded, size: 14, color: AppColors.warning),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  t.testCycleSteps,
                  style: const TextStyle(fontSize: 11, color: AppColors.warning, fontWeight: FontWeight.w600),
                )),
              ]),
            ),
          ],
          const SizedBox(height: 100),
        ],
      );
  }

  Widget _infoRow(BuildContext context, IconData icon, String label, String val, {bool isLast = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(icon, size: 18, color: context.cHint),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 13, color: context.cTextSub)),
          const Spacer(),
          Text(val, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.cText)),
        ]),
      );

  Widget _div(BuildContext context) => Divider(height: 1, color: context.cBorder, indent: 46);

  Widget _actionBtn(String text, IconData icon, Color color, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
        ),
      );

  Widget _iconActionBtn(IconData icon, Color color, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.2))),
          child: Icon(icon, color: color, size: 20),
        ),
      );

  Widget _sqBtn(BuildContext context, IconData icon, String label, Color color, [VoidCallback? onTap]) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: _GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.cTextSub)),
            ]),
          ),
        ),
      );
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? borderColor;
  const _GlassCard({required this.child, this.padding = const EdgeInsets.all(16), this.color, this.borderColor});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? context.cCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor ?? context.cBorder),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: child,
      );
}

class _HistoryTab extends StatelessWidget {
  final List<Paiement> historique;
  const _HistoryTab({required this.historique});
  @override
  Widget build(BuildContext context) => ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: historique.length,
        itemBuilder: (ctx, i) => _payItem(ctx, historique[i]),
      );
  Widget _payItem(BuildContext context, Paiement p) => _GlassCard(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: p.mode.bgColor(context), shape: BoxShape.circle), child: Icon(p.mode.icon, color: p.mode.color, size: 18)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.moisConcerne, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: context.cText)),
            Text(formatDate(p.datePaiement), style: TextStyle(fontSize: 11, color: context.cHint)),
          ])),
          Text('+${formatMontant(p.montant)} F', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.success)),
        ]),
      );
}

class _RemindersTab extends StatelessWidget {
  final List<Rappel> rappels;
  const _RemindersTab({required this.rappels});
  @override
  Widget build(BuildContext context) => ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: rappels.length,
        itemBuilder: (ctx, i) => _remItem(ctx, rappels[i]),
      );
  Widget _remItem(BuildContext context, Rappel r) => _GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(r.type == TypeRappel.sms ? Icons.sms_outlined : (r.type == TypeRappel.whatsapp ? Icons.chat_outlined : Icons.phone_outlined), size: 16, color: context.cTextSub),
            const SizedBox(width: 8),
            Text(rappelTypeLabelL(r.type, AppLocalizations.of(context)), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.cTextSub)),
            const Spacer(),
            Text(formatDate(r.dateEnvoi), style: TextStyle(fontSize: 11, color: context.cHint)),
          ]),
          const SizedBox(height: 8),
          Text(r.message, style: TextStyle(fontSize: 13, color: context.cText)),
          const SizedBox(height: 10),
          Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: r.statutColor, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(rappelStatutLabelL(r.statut, AppLocalizations.of(context)), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: r.statutColor)),
            if (r.livraisonLabel.isNotEmpty) ...[
              const Spacer(),
              Icon(Icons.done_all_rounded, size: 13,
                  color: (r.statutLivraison == 'read' || r.statutLivraison == 'delivered') ? AppColors.success : context.cHint),
              const SizedBox(width: 4),
              Text(r.livraisonLabel, style: TextStyle(fontSize: 10, color: context.cTextSub)),
            ],
          ]),
        ]),
      );
}
