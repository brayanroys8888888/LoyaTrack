import 'dart:ui' as import_ui;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';

/// Présente un formulaire dans un modal bottom sheet standardisé
/// (coins arrondis, scrollable, padding clavier auto). Remplace les AlertDialog.
Future<T?> showFormSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.cCard,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
          left: 20, right: 20, top: 14,
          bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom),
      child: SingleChildScrollView(child: builder(ctx)),
    ),
  );
}

/// Barre de préhension + titre pour un bottom sheet de formulaire.
Widget sheetHeader(BuildContext context, String titre) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: context.cBorder, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: 14),
        Text(titre, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: context.cText)),
        const SizedBox(height: 16),
      ],
    );

// Transition Cupertino (glissement latéral iOS) — pour tous les écrans secondaires.
Route heroRoute(Widget page) {
  return CupertinoPageRoute(builder: (context) => page);
}

Route slideRoute(Widget page) {
  return CupertinoPageRoute(builder: (context) => page);
}

/// Transition « modale » : la page **monte du bas** à l'ouverture et
/// **redescend** à la fermeture. Réservée à l'ajout locataire / paiement.
Route modalRoute(Widget page) {
  return PageRouteBuilder(
    fullscreenDialog: true,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, _, __) => page,
    transitionsBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
        child: child,
      );
    },
  );
}

// ─── Wave Clipper ─────────────────────────────────────────────────────────────
class WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final p = Path()
      ..lineTo(0, size.height - 28)
      ..quadraticBezierTo(
          size.width * .25, size.height, size.width * .5, size.height - 14)
      ..quadraticBezierTo(
          size.width * .75, size.height - 28, size.width, size.height - 14)
      ..lineTo(size.width, 0)
      ..close();
    return p;
  }

  @override
  bool shouldReclip(_) => false;
}

// ─── Gradient constant ────────────────────────────────────────────────────────
const kGradient = LinearGradient(
  colors: [Color(0xFF1565C0), Color(0xFF0D47A1), Color(0xFF2E7D32)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

// ─── Gradient Header ─────────────────────────────────────────────────────────
class GradientHeader extends StatelessWidget {
  final Widget child;
  final double bottomPadding;
  const GradientHeader(
      {required this.child, this.bottomPadding = 52, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: kGradient),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 14,
        left: 16,
        right: 16,
        bottom: bottomPadding,
      ),
      child: child,
    );
  }
}

// ─── Rounded Body ─────────────────────────────────────────────────────────────
class RoundedBody extends StatelessWidget {
  final Widget child;
  const RoundedBody({required this.child, super.key});

  @override
  Widget build(BuildContext context) => Transform.translate(
        offset: const Offset(0, -28),
        child: Container(
          decoration: BoxDecoration(
            color: context.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: child,
        ),
      );
}

// ─── App Bottom Nav ───────────────────────────────────────────────────────────
class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const AppBottomNav(
      {required this.currentIndex, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final items = [
      (Icons.home_rounded, Icons.home_outlined, t.navHome),
      (Icons.people_rounded, Icons.people_outline_rounded, t.navTenants),
      (Icons.credit_card_rounded, Icons.credit_card_outlined, t.navPayments),
      (Icons.settings_rounded, Icons.settings_outlined, t.navSettings),
    ];
    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 40),
      decoration: BoxDecoration(
        color: context.cCard.withOpacity(0.8),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: context.cBorder.withOpacity(0.5), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          )
        ]
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: import_ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SafeArea(
              top: false,
              bottom: false, // Don't let SafeArea add bottom padding inside the pill
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(items.length, (i) {
                  final active = i == currentIndex;
                  return GestureDetector(
                    onTap: () => onTap(i),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(active ? items[i].$1 : items[i].$2,
                              size: 24,
                              color: active ? AppColors.blue : context.cHint),
                          const SizedBox(height: 3),
                          Text(items[i].$3,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: active ? AppColors.blue : context.cHint)),
                          const SizedBox(height: 2),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: active ? 4 : 0,
                            height: 4,
                            decoration: const BoxDecoration(
                                shape: BoxShape.circle, color: AppColors.blue),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Status Pill ─────────────────────────────────────────────────────────────
class StatusPill extends StatelessWidget {
  final StatutLocataire statut;
  final bool small;
  const StatusPill(this.statut, {this.small = false, super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
            horizontal: small ? 8 : 10, vertical: small ? 3 : 4),
        decoration: BoxDecoration(
            color: statut.bgColor(context),
            borderRadius: BorderRadius.circular(20)),
        child: Text(
          '${statut.icon} ${statutLabelL(statut, AppLocalizations.of(context))}',
          style: TextStyle(
              color: statut.color,
              fontSize: small ? 10 : 11,
              fontWeight: FontWeight.w600),
        ),
      );
}

// ─── App Card ─────────────────────────────────────────────────────────────────
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  final double radius;
  final Color? color;
  final Border? border;
  const AppCard(
      {required this.child,
      this.padding,
      this.onTap,
      this.radius = 14,
      this.color,
      this.border,
      super.key});
  
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),  
          padding: padding ?? const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color ?? context.cCard,
            borderRadius: BorderRadius.circular(radius),
            border: border ?? Border.all(color: context.cBorder),
          ),
          child: child,
        ),
      );
}

// ─── Section Header ───────────────────────────────────────────────────────────
class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionHeader(this.title, {this.action, this.onAction, super.key});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: context.cText)),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(action!,
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.blue,
                      fontWeight: FontWeight.w600)),
            ),
        ],
      );
}

// ─── FAB ─────────────────────────────────────────────────────────────────────
class AppFAB extends StatelessWidget {
  final VoidCallback? onTap;
  const AppFAB({this.onTap, super.key});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: AppColors.blue,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: AppColors.blue.withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4))
            ],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
        ),
      );
}

// ─── Locataire Card ───────────────────────────────────────────────────────────
class LocataireCard extends StatelessWidget {
  final Locataire loc;
  final VoidCallback? onTap;
  final bool showAmount;
  const LocataireCard(
      {required this.loc, this.onTap, this.showAmount = true, super.key});

  Color _avatarBg(BuildContext ctx) => switch (loc.statut) {
        StatutLocataire.paye => ctx.cBlue3,
        StatutLocataire.nonPaye => ctx.cDangerBg,
        StatutLocataire.enDiscussion => ctx.cWarningBg,
        StatutLocataire.enPenalite => ctx.cPenaltyBg,
      };
  Color _avatarFg(BuildContext ctx) => loc.statut.color;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(12),
        onTap: onTap,
        child: Row(children: [
          Hero(
            tag: 'avatar-loc-${loc.id}',
            child: Material(
              type: MaterialType.transparency,
              child: _CircleAvatar(
                  initiales: loc.initiales,
                  bg: _avatarBg(context),
                  fg: _avatarFg(context)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(loc.nom,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: context.cText),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(children: [
                  Icon(Icons.home_outlined, size: 11, color: context.cTextSub),
                  const SizedBox(width: 3),
                  Text(loc.logement,
                      style: TextStyle(fontSize: 11, color: context.cTextSub)),
                ]),
                if (showAmount) ...[
                  const SizedBox(height: 2),
                  Text(
                      '${formatMontant(loc.montantLoyer)} FCFA · ${AppLocalizations.of(context).dueShort} ${loc.jourEcheance}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.blue,
                          fontWeight: FontWeight.w600)),
                ],
              ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            StatusPill(loc.statut),
            const SizedBox(height: 6),
            Icon(Icons.chevron_right_rounded, size: 16, color: context.cBorder),
          ]),
        ]),
      );
}

// ─── Circle Avatar ────────────────────────────────────────────────────────────
class _CircleAvatar extends StatelessWidget {
  final String initiales;
  final Color bg, fg;
  final double size;
  const _CircleAvatar(
      {super.key,
      required this.initiales,
      required this.bg,
      required this.fg,
      this.size = 44});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(initiales,
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: size * .28, color: fg)),
      );
}

// Expose _CircleAvatar publicly
class CircleAvatar2 extends _CircleAvatar {
  const CircleAvatar2(
      {required super.initiales,
      required super.bg,
      required super.fg,
      super.size,
      super.key});
}

// ─── App Input Field ──────────────────────────────────────────────────────────
class AppInput extends StatelessWidget {
  final String label, hint;
  final TextEditingController controller;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool obscure;
  final TextInputType? keyboardType;
  final int? maxLines;
  final String? Function(String?)? validator;

  const AppInput({
    required this.label,
    required this.hint,
    required this.controller,
    this.prefixIcon,
    this.suffix,
    this.obscure = false,
    this.keyboardType,
    this.maxLines = 1,
    this.validator,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  color: context.cTextSub,
                  letterSpacing: 0.8)),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            maxLines: maxLines,
            validator: validator,
            style: TextStyle(fontSize: 14, color: context.cText),
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: prefixIcon != null
                  ? Icon(prefixIcon, size: 18, color: context.cHint)
                  : null,
              suffixIcon: suffix,
            ),
          ),
        ],
      );
}

// ─── Toggle Switch ────────────────────────────────────────────────────────────
class AppToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const AppToggle({required this.value, required this.onChanged, super.key});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 44,
          height: 24,
          decoration: BoxDecoration(
            color: value ? AppColors.blue : context.cBorder,
            borderRadius: BorderRadius.circular(12),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
                width: 18,
                height: 18,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle)),
          ),
        ),
      );
}

// ─── Papillon Logo (CustomPainter) ────────────────────────────────────────────
class PapillonLogo extends StatelessWidget {
  final double size;
  const PapillonLogo({this.size = 80, super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _PapillonPainter()),
      );
}

class _PapillonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final pB = Paint()
      ..color = const Color(0xFF1565C0).withOpacity(.9)
      ..style = PaintingStyle.fill;
    final pG = Paint()
      ..color = const Color(0xFF2E7D32).withOpacity(.85)
      ..style = PaintingStyle.fill;
    final pD = Paint()
      ..color = const Color(0xFF0D47A1)
      ..style = PaintingStyle.fill;

    void wing(bool right, bool top, Paint paint) {
      final xm = right ? 1 : -1;
      final ym = top ? -1 : 1;
      final p = Path()
        ..moveTo(cx, cy)
        ..cubicTo(
            cx + xm * size.width * .15,
            cy + ym * size.height * .22,
            cx + xm * size.width * .42,
            cy + ym * size.height * .24,
            cx + xm * size.width * .44,
            cy + ym * size.height * .04)
        ..cubicTo(
            cx + xm * size.width * .46,
            cy - ym * size.height * .14,
            cx + xm * size.width * .24,
            cy - ym * size.height * .21,
            cx,
            cy - ym * size.height * .10)
        ..close();
      canvas.drawPath(p, paint);
    }

    wing(false, true, pB);
    wing(true, true, pB);
    wing(false, false, pG);
    wing(true, false, pG);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(cx, cy + size.height * .08),
              width: size.width * .07,
              height: size.height * .3),
          const Radius.circular(4)),
      pD,
    );

    final roofP = Paint()
      ..color = const Color(0xFF1565C0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .04
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
        Path()
          ..moveTo(cx - size.width * .14, cy - size.height * .10)
          ..lineTo(cx, cy - size.height * .22)
          ..lineTo(cx + size.width * .14, cy - size.height * .10),
        roofP);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(cx, cy - size.height * .06),
              width: size.width * .13,
              height: size.height * .11),
          const Radius.circular(2)),
      Paint()
        ..color = const Color(0xFF1565C0).withOpacity(.4)
        ..style = PaintingStyle.fill,
    );
    final lp = Paint()
      ..color = Colors.white
      ..strokeWidth = .8;
    canvas.drawLine(Offset(cx, cy - size.height * .115),
        Offset(cx, cy - size.height * .005), lp);
    canvas.drawLine(Offset(cx - size.width * .065, cy - size.height * .06),
        Offset(cx + size.width * .065, cy - size.height * .06), lp);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─── Skeleton Loaders ─────────────────────────────────────────────────────────

class _SkeletonBox extends StatefulWidget {
  final double width, height, radius;
  const _SkeletonBox({required this.width, required this.height, this.radius = 8});
  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    _anim = Tween<double>(begin: -1.5, end: 2.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine));
    _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final base = dark ? const Color(0xFF2A2D36) : const Color(0xFFE8ECF0);
    final shine = dark ? const Color(0xFF343740) : const Color(0xFFF5F7FA);

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [base, shine, base],
            stops: [
              (_anim.value - 0.5).clamp(0.0, 1.0),
              _anim.value.clamp(0.0, 1.0),
              (_anim.value + 0.5).clamp(0.0, 1.0),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton d'une carte locataire
class LocataireCardSkeleton extends StatelessWidget {
  const LocataireCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.cBorder),
      ),
      child: Row(children: [
        _SkeletonBox(width: 46, height: 46, radius: 14),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SkeletonBox(width: 140, height: 13),
              const SizedBox(height: 6),
              _SkeletonBox(width: 100, height: 11),
              const SizedBox(height: 8),
              _SkeletonBox(width: 70, height: 10, radius: 6),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _SkeletonBox(width: 70, height: 14),
            const SizedBox(height: 6),
            _SkeletonBox(width: 50, height: 10),
          ],
        ),
      ]),
    );
  }
}

/// Skeleton du dashboard (stats + cartes)
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Stats row
      Row(children: [
        Expanded(child: _statSkeleton(context)),
        const SizedBox(width: 10),
        Expanded(child: _statSkeleton(context)),
        const SizedBox(width: 10),
        Expanded(child: _statSkeleton(context)),
      ]),
      const SizedBox(height: 16),
      // Revenue card
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.cCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.cBorder),
        ),
        child: Row(children: [
          _SkeletonBox(width: 44, height: 44, radius: 13),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _SkeletonBox(width: 100, height: 11),
            const SizedBox(height: 8),
            _SkeletonBox(width: 160, height: 22),
            const SizedBox(height: 6),
            _SkeletonBox(width: 80, height: 11),
          ]),
        ]),
      ),
      const SizedBox(height: 24),
      // Locataires section
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _SkeletonBox(width: 130, height: 14),
        _SkeletonBox(width: 60, height: 12),
      ]),
      const SizedBox(height: 12),
      const LocataireCardSkeleton(),
      const LocataireCardSkeleton(),
    ]);
  }

  Widget _statSkeleton(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.cBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SkeletonBox(width: 30, height: 30, radius: 10),
        const SizedBox(height: 10),
        _SkeletonBox(width: 40, height: 20),
        const SizedBox(height: 4),
        _SkeletonBox(width: 55, height: 10),
      ]),
    );
  }
}
