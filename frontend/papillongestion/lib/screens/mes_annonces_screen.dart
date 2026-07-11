import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../theme/app_theme.dart';
import '../models/annonce.dart';
import '../models/models.dart' show formatMontant;
import '../services/annonce_service.dart';
import '../widgets/shared_widgets.dart';
import 'add_edit_annonce_screen.dart';
import 'messages_screen.dart';

/// Libellé + couleur d'un statut d'annonce.
(String, Color) _statut(String s, AppLocalizations t) => switch (s) {
      'publiee' => (t.adStatusPublished, AppColors.success),
      'pourvue' => (t.adStatusFilled, AppColors.blue),
      'expiree' => (t.adStatusExpired, AppColors.warning),
      'suspendue' => (t.adStatusSuspended, AppColors.danger),
      'en_moderation' => (t.adStatusModeration, AppColors.warning),
      _ => (t.adStatusDraft, Colors.grey),
    };

class MesAnnoncesScreen extends StatefulWidget {
  const MesAnnoncesScreen({super.key});
  @override
  State<MesAnnoncesScreen> createState() => _MesAnnoncesScreenState();
}

class _MesAnnoncesScreenState extends State<MesAnnoncesScreen> {
  final _service = AnnonceService();
  List<Annonce> _annonces = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final a = await _service.getAnnonces();
    if (mounted) setState(() { _annonces = a; _loading = false; });
  }

  Future<void> _nouvelle() async {
    final t = AppLocalizations.of(context);
    final draft = await _service.createAnnonce({'titre': t.adNew});
    if (draft == null || !mounted) return;
    await Navigator.push(context, slideRoute(AddEditAnnonceScreen(annonce: draft)));
    _fetch();
  }

  Future<void> _ouvrir(Annonce a) async {
    await Navigator.push(context, slideRoute(AddEditAnnonceScreen(annonce: a)));
    _fetch();
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
        title: Text(t.adMine, style: TextStyle(color: context.cText, fontSize: 18, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: t.adMessages,
            icon: const Icon(Icons.forum_outlined, color: AppColors.blue),
            onPressed: () => Navigator.push(context, slideRoute(const MessagesScreen())),
          ),
          IconButton(
            tooltip: t.adNew,
            icon: const Icon(Icons.add_rounded, color: AppColors.blue),
            onPressed: _nouvelle,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetch,
              child: _annonces.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      Icon(Icons.campaign_outlined, size: 56, color: context.cHint),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(t.adEmpty, textAlign: TextAlign.center, style: TextStyle(color: context.cTextSub)),
                      ),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      itemCount: _annonces.length,
                      itemBuilder: (_, i) => _AnnonceCard(
                        annonce: _annonces[i],
                        onTap: () => _ouvrir(_annonces[i]),
                        onShare: _annonces[i].estPubliee
                            ? () => partagerAnnonce(context, _annonces[i])
                            : null,
                      ),
                    ),
            ),
    );
  }
}

class _AnnonceCard extends StatelessWidget {
  final Annonce annonce;
  final VoidCallback onTap;
  final VoidCallback? onShare;
  const _AnnonceCard({required this.annonce, required this.onTap, this.onShare});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final (label, couleur) = _statut(annonce.statut, t);
    final cover = annonce.couverture;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.cCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.cBorder),
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: cover != null
                ? Image.network(cover.image, width: 64, height: 64, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder(context))
                : _placeholder(context),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(annonce.titre, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: context.cText)),
            const SizedBox(height: 3),
            Text('${formatMontant(annonce.loyer)} FCFA · ${annonce.villeNom.isNotEmpty ? annonce.villeNom : '—'}',
                style: const TextStyle(fontSize: 12, color: AppColors.blue, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: couleur.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: couleur)),
              ),
              if (annonce.estPubliee) ...[
                const SizedBox(width: 8),
                Icon(Icons.visibility_outlined, size: 12, color: context.cHint),
                const SizedBox(width: 2),
                Text(t.adViews(annonce.nbVues), style: TextStyle(fontSize: 11, color: context.cTextSub)),
              ],
            ]),
          ])),
          if (onShare != null)
            IconButton(
              icon: const Icon(Icons.share_rounded, size: 18, color: AppColors.blue),
              onPressed: onShare,
            )
          else
            Icon(Icons.chevron_right_rounded, size: 18, color: context.cBorder),
        ]),
      ),
    );
  }

  Widget _placeholder(BuildContext context) => Container(
        width: 64, height: 64, color: context.cBorder,
        child: Icon(Icons.image_outlined, color: context.cHint),
      );
}
