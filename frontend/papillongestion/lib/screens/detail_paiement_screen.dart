import 'dart:ui' as import_ui;
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../widgets/shared_widgets.dart';
import '../services/paiement_service.dart';
import '../core/pdf_helper.dart';

class DetailPaiementScreen extends StatefulWidget {
  final Paiement paiement;
  const DetailPaiementScreen({required this.paiement, super.key});

  @override
  State<DetailPaiementScreen> createState() => _DetailPaiementScreenState();
}

class _DetailPaiementScreenState extends State<DetailPaiementScreen>
    with SingleTickerProviderStateMixin {
  bool _generatingPdf = false;
  bool _pdfGenerated = false;

  Paiement get p => widget.paiement;

  String _typeLabel(AppLocalizations t) => switch (p.typePaiement) {
        'partiel' => t.typePartial,
        'avance' => t.typeAdvance,
        _ => t.typeComplete,
      };

  Color _typeColor() => switch (p.typePaiement) {
        'partiel' => AppColors.warning,
        'avance' => AppColors.blue,
        _ => AppColors.success,
      };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.bg,
      body: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _DetailPaiementHeaderDelegate(
              p: p,
              safeTop: MediaQuery.of(context).padding.top,
              onBack: () => Navigator.pop(context),
              onShare: _sharePaiement,
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              color: context.bg,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                child: Column(
                  children: [
                    // ── Montant hero ──────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.success.withOpacity(0.08),
                            AppColors.green.withOpacity(0.04),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppColors.success.withOpacity(0.2)),
                      ),
                      child: Column(children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: context.cSuccessBg,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_circle_rounded,
                              color: AppColors.success, size: 30),
                        ),
                        const SizedBox(height: 14),
                        Text(t.paymentValidated.toUpperCase(),
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                                color: AppColors.success,
                                letterSpacing: 1.2)),
                        const SizedBox(height: 8),
                        Text('${formatMontant(p.montant)} FCFA',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 36,
                                color: AppColors.success,
                                letterSpacing: -1)),
                        const SizedBox(height: 6),
                        Text(p.moisConcerne,
                            style: TextStyle(
                                fontSize: 14, color: context.cTextSub)),
                      ]),
                    ),
                    const SizedBox(height: 16),

                    // ── Infos locataire ───────────────────────────
                    AppCard(
                      child: Row(children: [
                        CircleAvatar2(
                          initiales: p.initiales,
                          bg: context.cBlue3,
                          fg: AppColors.blue,
                          size: 48,
                        ),
                        const SizedBox(width: 14),
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.nomLocataire,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: context.cText)),
                              const SizedBox(height: 3),
                              Row(children: [
                                Icon(Icons.home_outlined,
                                    size: 13, color: context.cTextSub),
                                const SizedBox(width: 4),
                                Text(p.logement,
                                    style: TextStyle(
                                        fontSize: 13, color: context.cTextSub)),
                              ]),
                            ]),
                      ]),
                    ),
                    const SizedBox(height: 12),

                    // ── Détails transaction ───────────────────────
                    AppCard(
                      child: Column(children: [
                        _DetailRow(
                            t.reference,
                            p.reference.isNotEmpty
                                ? p.reference
                                : '#PAY-${p.id.toUpperCase().padLeft(6, '0')}',
                            Icons.tag_rounded,
                            context),
                        _Divider(context),
                        _DetailRow(t.paymentDate, formatDate(p.datePaiement),
                            Icons.calendar_today_rounded, context),
                        _Divider(context),
                        _DetailRow(t.monthConcerned, p.moisConcerne,
                            Icons.date_range_rounded, context),
                        _Divider(context),
                        _DetailRow(t.paymentMode, modeLabelL(p.mode, t),
                            p.mode.icon, context,
                            valueColor: p.mode.color),
                        _Divider(context),
                        // Type réel : complet / partiel / avance
                        _DetailRow(t.paymentType, _typeLabel(t),
                            Icons.category_outlined, context,
                            valueColor: _typeColor()),
                        // Période réellement couverte par le paiement
                        if (p.periodeDebut != null && p.periodeFin != null) ...[
                          _Divider(context),
                          _DetailRow(
                              t.coveredPeriod,
                              '${formatDate(p.periodeDebut!)} → ${formatDate(p.periodeFin!)}',
                              Icons.event_repeat_outlined,
                              context),
                        ],
                        if (p.nbMois > 1) ...[
                          _Divider(context),
                          _DetailRow(t.monthsCount, '${p.nbMois}',
                              Icons.calendar_view_month_outlined, context),
                        ],
                        _Divider(context),
                        _DetailRow(
                            t.amountLabel,
                            '${formatMontant(p.montant)} FCFA',
                            Icons.payments_rounded,
                            context,
                            valueColor: AppColors.success),
                        // Reste dû réel (paiement partiel)
                        if (p.resteDu > 0) ...[
                          _Divider(context),
                          _DetailRow(
                              t.amountDue,
                              '${formatMontant(p.resteDu)} FCFA',
                              Icons.account_balance_wallet_outlined,
                              context,
                              valueColor: AppColors.danger),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 24),

                    // ── Bouton télécharger reçu PDF ───────────────
                    _pdfGenerated
                        ? GestureDetector(
                            onTap: _generatePdf,
                            child: _DownloadSuccess(context: context))
                        : GestureDetector(
                            onTap: _generatingPdf ? null : _generatePdf,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                gradient: _generatingPdf
                                    ? null
                                    : const LinearGradient(
                                        colors: [
                                          Color(0xFF1565C0),
                                          Color(0xFF2E7D32)
                                        ],
                                      ),
                                color: _generatingPdf ? context.cSurface : null,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              alignment: Alignment.center,
                              child: _generatingPdf
                                  ? Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: context.cTextSub),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(t.generatingReceipt,
                                            style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                                color: context.cTextSub)),
                                      ],
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.picture_as_pdf_rounded,
                                            color: Colors.white, size: 20),
                                        const SizedBox(width: 10),
                                        Text(t.downloadReceiptPdf,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15,
                                                color: Colors.white)),
                                      ],
                                    ),
                            ),
                          ),
                    const SizedBox(height: 12),

                    // ── Bouton partager ───────────────────────────
                    GestureDetector(
                      onTap: _sharePaiement,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: context.cCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: context.cBorder),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.share_rounded,
                                color: context.cTextSub, size: 18),
                            const SizedBox(width: 8),
                            Text(t.shareReceipt,
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: context.cTextSub)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Génération RÉELLE de la quittance PDF (et ouverture) ──
  Future<void> _generatePdf() async {
    final t = AppLocalizations.of(context);
    setState(() => _generatingPdf = true);
    final bytes = await PaiementService().getQuittancePdf(p.id);
    if (!mounted) return;
    setState(() {
      _generatingPdf = false;
      _pdfGenerated = bytes != null;
    });
    if (bytes != null) {
      await ouvrirPdf(context, bytes, 'quittance_${p.id}.pdf');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t.generationError), backgroundColor: AppColors.danger));
    }
  }

  void _sharePaiement() {
    _showSnack(AppLocalizations.of(context).sharingReceipt, AppColors.blue);
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }
}

class _DetailPaiementHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Paiement p;
  final double safeTop;
  final VoidCallback onBack;
  final VoidCallback onShare;

  _DetailPaiementHeaderDelegate({
    required this.p,
    required this.safeTop,
    required this.onBack,
    required this.onShare,
  });

  @override
  double get maxExtent => safeTop + 140;
  @override
  double get minExtent => safeTop + 60;
  @override
  bool shouldRebuild(covariant _DetailPaiementHeaderDelegate old) => true;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final isCollapsed = progress > 0.8;

    return Stack(
      children: [
        // Background Gradient
        Positioned.fill(
          child: isCollapsed
              ? ClipRect(
                  child: BackdropFilter(
                    filter: import_ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(color: context.bg.withOpacity(0.9)),
                  ),
                )
              : Container(
                  decoration: BoxDecoration(
                    gradient: kGradient,
                    boxShadow: isCollapsed
                        ? [
                            BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                                offset: const Offset(0, 2))
                          ]
                        : null,
                  ),
                ),
        ),

        // Rounded bottom corner (only when expanded)
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

        // Title and Back button (animated)
        Positioned(
          left: 16,
          right: 16,
          top: safeTop + 10,
          child: Row(
            children: [
              GestureDetector(
                onTap: onBack,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isCollapsed
                        ? context.cCard
                        : Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        isCollapsed ? Border.all(color: context.cBorder) : null,
                  ),
                  child: Icon(Icons.arrow_back_ios_new_rounded,
                      color: isCollapsed ? context.cText : Colors.white,
                      size: 16),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: progress > 0.5 ? 1.0 : 0.0,
                  child: Text(
                    AppLocalizations.of(context).paymentDetailTitle,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: isCollapsed ? context.cText : Colors.white,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: onShare,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isCollapsed
                        ? context.cCard
                        : Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        isCollapsed ? Border.all(color: context.cBorder) : null,
                  ),
                  child: Icon(Icons.share_rounded,
                      color: isCollapsed ? context.cText : Colors.white,
                      size: 18),
                ),
              ),
            ],
          ),
        ),

        // Expanded specific content (can be customized)
        if (progress < 1.0)
          Positioned(
            left: 60,
            right: 16,
            top: safeTop + 10,
            child: Opacity(
              opacity: 1 - progress,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context).paymentDetailTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '#PAY-${p.id.toUpperCase().padLeft(6, '0')}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Sous-widgets ─────────────────────────────────────────────────────────────

Widget _DetailRow(
    String label, String value, IconData icon, BuildContext context,
    {Color? valueColor}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(children: [
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: context.cSurface,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 16, color: context.cTextSub),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(label,
            style: TextStyle(fontSize: 13, color: context.cTextSub)),
      ),
      Text(value,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: valueColor ?? context.cText,
          )),
    ]),
  );
}

Widget _Divider(BuildContext context) =>
    Divider(height: 1, color: context.cBorder, indent: 44);

class _DownloadSuccess extends StatelessWidget {
  final BuildContext context;
  const _DownloadSuccess({required this.context});

  @override
  Widget build(BuildContext ctx) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: context.cSuccessBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.success.withOpacity(0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.check_circle_rounded,
              color: AppColors.success, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(AppLocalizations.of(context).receiptPdfGenerated,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.success)),
              Text(AppLocalizations.of(context).tapToShowOptions,
                  style: TextStyle(fontSize: 11, color: context.cTextSub)),
            ]),
          ),
          const Icon(Icons.picture_as_pdf_rounded,
              color: AppColors.danger, size: 22),
        ]),
      );
}
