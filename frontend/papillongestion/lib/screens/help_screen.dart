import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Guide d'utilisation : chaque fonctionnalité clé présentée en section
/// dépliable (question → explication). Contenu 100 % localisé FR/EN.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    // Paires (titre, contenu) dans l'ordre du parcours utilisateur.
    final sections = <(String, String)>[
      (t.helpQ1, t.helpA1),
      (t.helpQ2, t.helpA2),
      (t.helpQ3, t.helpA3),
      (t.helpQ4, t.helpA4),
      (t.helpQ5, t.helpA5),
      (t.helpQ6, t.helpA6),
      (t.helpQ7, t.helpA7),
      (t.helpQ8, t.helpA8),
      (t.helpQ9, t.helpA9),
    ];

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: context.cText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(t.helpTitle,
            style: TextStyle(
                color: context.cText,
                fontSize: 17,
                fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(t.helpIntro,
              style: TextStyle(
                  fontSize: 13, color: context.cTextSub, height: 1.4)),
          const SizedBox(height: 16),
          for (final (titre, corps) in sections) ...[
            _HelpTile(titre: titre, corps: corps),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.cBlue3,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              const Icon(Icons.support_agent_rounded,
                  color: AppColors.blue, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(t.helpContact,
                    style: TextStyle(
                        fontSize: 13,
                        color: context.cText,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _HelpTile extends StatelessWidget {
  final String titre;
  final String corps;
  const _HelpTile({required this.titre, required this.corps});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.cCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.cBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Retire les séparateurs par défaut de l'ExpansionTile.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: AppColors.blue,
          collapsedIconColor: context.cTextSub,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Text(titre,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.cText)),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(corps,
                  style: TextStyle(
                      fontSize: 13, color: context.cTextSub, height: 1.5)),
            ),
          ],
        ),
      ),
    );
  }
}
