import 'dart:ui' as import_ui;
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import '../services/notification_service.dart';

/// Libellé localisé d'un type de notification.
String notifLabelL(TypeNotif tn, AppLocalizations t) => switch (tn) {
  TypeNotif.paiement   => t.notifPayment,
  TypeNotif.retard     => t.notifLate,
  TypeNotif.penalite   => t.notifPenalty,
  TypeNotif.rappel     => t.notifReminder,
  TypeNotif.systeme    => t.notifSystem,
  TypeNotif.discussion => t.notifDiscussion,
};

// ─── Modèle Notification ─────────────────────────────────────────────────────
enum TypeNotif { paiement, retard, penalite, rappel, systeme, discussion }

class AppNotification {
  final String id, titre, corps, locataire;
  final TypeNotif type;
  final DateTime date;
  bool lue;

  AppNotification({
    required this.id, required this.titre, required this.corps,
    required this.locataire, required this.type, required this.date,
    this.lue = false,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    TypeNotif t;
    switch (json['type_notif']) {
      case 'paiement': t = TypeNotif.paiement; break;
      case 'retard': t = TypeNotif.retard; break;
      case 'penalite': t = TypeNotif.penalite; break;
      case 'rappel': t = TypeNotif.rappel; break;
      case 'discussion': t = TypeNotif.discussion; break;
      default: t = TypeNotif.systeme;
    }
    return AppNotification(
      id: json['id'].toString(),
      titre: json['titre'] ?? '',
      corps: json['corps'] ?? '',
      locataire: json['locataire_nom'] ?? 'Système',
      type: t,
      date: DateTime.parse(json['date_creation']),
      lue: json['lue'] ?? false,
    );
  }

  static List<AppNotification> get mockData => [
    AppNotification(id: 'n1', type: TypeNotif.paiement, lue: false, titre: 'Paiement reçu ✓', corps: 'Jean Dupont a effectué son paiement de 50 000 FCFA pour mai 2025.', locataire: 'Jean Dupont', date: DateTime.now().subtract(const Duration(minutes: 23))),
    AppNotification(id: 'n2', type: TypeNotif.penalite, lue: false, titre: 'Pénalité appliquée', corps: 'Paul Martin est en retard de 4 jours. Pénalité accumulée : 20 000 FCFA.', locataire: 'Paul Martin', date: DateTime.now().subtract(const Duration(hours: 2))),
    AppNotification(id: 'n3', type: TypeNotif.rappel, lue: false, titre: 'Rappel J-5 envoyé', corps: 'SMS envoyé à Marie Atangana : échéance dans 5 jours.', locataire: 'Marie Atangana', date: DateTime.now().subtract(const Duration(hours: 5))),
    AppNotification(id: 'n4', type: TypeNotif.retard, lue: true, titre: 'Loyer en retard', corps: 'Fatima Ndiaye n\'a pas payé son loyer de 60 000 FCFA. Échéance dépassée.', locataire: 'Fatima Ndiaye', date: DateTime.now().subtract(const Duration(days: 1))),
    AppNotification(id: 'n5', type: TypeNotif.rappel, lue: true, titre: 'Appel vocal IA J-1', corps: 'Appel automatique effectué auprès de Koné Diallo. Répondu avec succès.', locataire: 'Koné Diallo', date: DateTime.now().subtract(const Duration(days: 1, hours: 3))),
    AppNotification(id: 'n6', type: TypeNotif.discussion, lue: true, titre: 'Locataire en discussion', corps: 'Marie Atangana a été marquée "En discussion". Aucun rappel agressif ne sera envoyé.', locataire: 'Marie Atangana', date: DateTime.now().subtract(const Duration(days: 2))),
    AppNotification(id: 'n7', type: TypeNotif.paiement, lue: true, titre: 'Paiement reçu ✓', corps: 'Sophie Claire a effectué son paiement de 50 000 FCFA pour avril 2025.', locataire: 'Sophie Claire', date: DateTime.now().subtract(const Duration(days: 3))),
    AppNotification(id: 'n8', type: TypeNotif.systeme, lue: true, titre: 'Mise à jour de l\'application', corps: 'Papillon Gestion v1.0.1 est disponible. Nouveautés : export PDF amélioré.', locataire: 'Système', date: DateTime.now().subtract(const Duration(days: 5))),
     AppNotification(id: 'n1', type: TypeNotif.paiement, lue: false, titre: 'Paiement reçu ✓', corps: 'Jean Dupont a effectué son paiement de 50 000 FCFA pour mai 2025.', locataire: 'Jean Dupont', date: DateTime.now().subtract(const Duration(minutes: 23))),
    AppNotification(id: 'n2', type: TypeNotif.penalite, lue: false, titre: 'Pénalité appliquée', corps: 'Paul Martin est en retard de 4 jours. Pénalité accumulée : 20 000 FCFA.', locataire: 'Paul Martin', date: DateTime.now().subtract(const Duration(hours: 2))),
    AppNotification(id: 'n3', type: TypeNotif.rappel, lue: false, titre: 'Rappel J-5 envoyé', corps: 'SMS envoyé à Marie Atangana : échéance dans 5 jours.', locataire: 'Marie Atangana', date: DateTime.now().subtract(const Duration(hours: 5))),
    AppNotification(id: 'n4', type: TypeNotif.retard, lue: true, titre: 'Loyer en retard', corps: 'Fatima Ndiaye n\'a pas payé son loyer de 60 000 FCFA. Échéance dépassée.', locataire: 'Fatima Ndiaye', date: DateTime.now().subtract(const Duration(days: 1))),
    AppNotification(id: 'n5', type: TypeNotif.rappel, lue: true, titre: 'Appel vocal IA J-1', corps: 'Appel automatique effectué auprès de Koné Diallo. Répondu avec succès.', locataire: 'Koné Diallo', date: DateTime.now().subtract(const Duration(days: 1, hours: 3))),
    AppNotification(id: 'n6', type: TypeNotif.discussion, lue: true, titre: 'Locataire en discussion', corps: 'Marie Atangana a été marquée "En discussion". Aucun rappel agressif ne sera envoyé.', locataire: 'Marie Atangana', date: DateTime.now().subtract(const Duration(days: 2))),
    AppNotification(id: 'n7', type: TypeNotif.paiement, lue: true, titre: 'Paiement reçu ✓', corps: 'Sophie Claire a effectué son paiement de 50 000 FCFA pour avril 2025.', locataire: 'Sophie Claire', date: DateTime.now().subtract(const Duration(days: 3))),
    AppNotification(id: 'n8', type: TypeNotif.systeme, lue: true, titre: 'Mise à jour de l\'application', corps: 'Papillon Gestion v1.0.1 est disponible. Nouveautés : export PDF amélioré.', locataire: 'Système', date: DateTime.now().subtract(const Duration(days: 5))),
    
  ];
}

// ─── Extensions ───────────────────────────────────────────────────────────────
extension NotifExt on TypeNotif {
  IconData get icon => switch (this) {
    TypeNotif.paiement   => Icons.check_circle_rounded,
    TypeNotif.retard     => Icons.warning_amber_rounded,
    TypeNotif.penalite   => Icons.gavel_rounded,
    TypeNotif.rappel     => Icons.notifications_active_rounded,
    TypeNotif.systeme    => Icons.info_rounded,
    TypeNotif.discussion => Icons.chat_rounded,
  };
  Color get color => switch (this) {
    TypeNotif.paiement   => AppColors.success,
    TypeNotif.retard     => AppColors.danger,
    TypeNotif.penalite   => AppColors.penalty,
    TypeNotif.rappel     => AppColors.blue,
    TypeNotif.systeme    => AppColors.warning,
    TypeNotif.discussion => AppColors.warning,
  };
  String get label => switch (this) {
    TypeNotif.paiement   => 'Paiement',
    TypeNotif.retard     => 'Retard',
    TypeNotif.penalite   => 'Pénalité',
    TypeNotif.rappel     => 'Rappel',
    TypeNotif.systeme    => 'Système',
    TypeNotif.discussion => 'Discussion',
  };
  Color bgColor(BuildContext ctx) => switch (this) {
    TypeNotif.paiement   => ctx.cSuccessBg,
    TypeNotif.retard     => ctx.cDangerBg,
    TypeNotif.penalite   => ctx.cPenaltyBg,
    TypeNotif.rappel     => ctx.cBlue3,
    TypeNotif.systeme    => ctx.cWarningBg,
    TypeNotif.discussion => ctx.cWarningBg,
  };
}

// ─── Ecran Notifications ─────────────────────────────────────────────────────
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _notifs = [];
  bool _isLoading = true;
  TypeNotif? _filter;

  @override
  void initState() {
    super.initState();
    _loadNotifs();
  }

  Future<void> _loadNotifs() async {
    setState(() => _isLoading = true);
    try {
      final data = await NotificationService.getNotifications();
      setState(() {
        _notifs = data.map((n) => AppNotification.fromJson(n)).toList();
      });
    } catch (e) {
      debugPrint('Error loading notifs: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _marquerLue(AppNotification notif) async {
    setState(() => notif.lue = true);
    try {
      await NotificationService.marquerLue(int.parse(notif.id));
    } catch (e) {
      debugPrint('Error marking as read: $e');
    }
  }

  Future<void> _marquerToutLu() async {
    setState(() {
      for (var n in _notifs) {
        n.lue = true;
      }
    });
    try {
      await NotificationService.marquerToutLu();
    } catch (e) {
      debugPrint('Error marking all as read: $e');
    }
  }

  List<AppNotification> get filtered => _filter == null
      ? _notifs
      : _notifs.where((n) => n.type == _filter).toList();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final list = filtered;
    final safeTop = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: context.bg,
      body: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _NotifHeaderDelegate(
              safeTop: safeTop,
              nonLues: _notifs.where((n) => !n.lue).length,
              onBack: () { if (Navigator.canPop(context)) Navigator.pop(context); },
              onReadAll: _marquerToutLu,
              onDeleteAll: () => setState(() => _notifs.clear()),
            ),
          ),

          SliverToBoxAdapter(
            child: Container(
              color: context.bg,
              height: 80,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _FilterChip(label: t.allLabel, active: _filter == null, onTap: () => setState(() => _filter = null)),
                    const SizedBox(width: 8),
                    ...TypeNotif.values.map((tn) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _FilterChip(label: notifLabelL(tn, t), active: _filter == tn, onTap: () => setState(() => _filter = tn)),
                    )),
                  ],
                ),
              ),
            ),
          ),

          // ── Liste ──
          if (_isLoading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (list.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text(t.noNotifications, style: TextStyle(color: context.cHint))),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _NotifCard(
                    notif: list[i],
                    onTap: () {
                      _marquerLue(list[i]);
                      _showDetail(list[i]);
                    },
                    onDismiss: () => setState(() => _notifs.remove(list[i])),
                    onMarquerLue: () => _marquerLue(list[i]),
                  ),
                  childCount: list.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showDetail(AppNotification n) {
    setState(() => n.lue = true);
    showModalBottomSheet(
      context: context,
      backgroundColor: context.cCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(n.type.icon, color: n.type.color, size: 48),
            const SizedBox(height: 16),
            Text(n.titre, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 12),
            Text(n.corps, textAlign: TextAlign.center, style: TextStyle(color: context.cTextSub)),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context).close))),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: active ? AppColors.blue : context.cCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? AppColors.blue : context.cBorder),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? Colors.white : context.cTextSub)),
    ),
  );
}

class _NotifCard extends StatelessWidget {
  final AppNotification notif;
  final VoidCallback onTap, onDismiss, onMarquerLue;
  const _NotifCard({required this.notif, required this.onTap, required this.onDismiss, required this.onMarquerLue});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: notif.lue ? context.cCard : notif.type.bgColor(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.cBorder),
        ),
        child: Row(
          children: [
            Icon(notif.type.icon, color: notif.type.color),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(notif.titre, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(notif.corps, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: context.cTextSub)),
            ])),
          ],
        ),
      ),
    ),
  );
}

// ─── Header Delegate ──────────────────────────────────────────────────────────
class _NotifHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double safeTop;
  final int nonLues;
  final VoidCallback onBack, onReadAll, onDeleteAll;

_NotifHeaderDelegate({
    required this.safeTop,
    required this.nonLues,
    required this.onBack,
    required this.onReadAll,
    required this.onDeleteAll,
  });

  @override double get maxExtent => (safeTop > 0 ? safeTop : 20) + 130;
  @override double get minExtent => (safeTop > 0 ? safeTop : 20) + 60;
  @override bool shouldRebuild(covariant _NotifHeaderDelegate oldDelegate) => true;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final diff = maxExtent - minExtent;
    double t = (shrinkOffset / (diff > 0 ? diff : 1)).clamp(0.0, 1.0);
    if (t.isNaN) t = 0.0;
    
    final collapsed = t >= 0.95;

    return Stack(
      children: [
        // ── Background ──
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

        // ── Rounded bottom corner (only when expanded) ──
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

        // ── Content (SafeArea + rangée centrée verticalement) ──
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Align(
              alignment: Alignment.center,
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                        color: collapsed ? context.cText : Colors.white, size: 18),
                    onPressed: onBack,
                  ),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context).notifications,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 22 - (2 * t),
                        color: collapsed ? context.cText : Colors.white,
                      ),
                    ),
                  ),
                  if (nonLues > 0)
                    IconButton(
                      onPressed: onReadAll,
                      icon: Icon(Icons.done_all_rounded,
                          color: collapsed ? AppColors.blue : Colors.white, size: 22),
                      tooltip: AppLocalizations.of(context).markAllRead,
                    ),
                  IconButton(
                    onPressed: onDeleteAll,
                    icon: Icon(Icons.delete_sweep_rounded,
                        color: collapsed ? context.cText : Colors.white, size: 22),
                    tooltip: AppLocalizations.of(context).deleteAll,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
