import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

/// Écran « À propos » : identité de l'app, version, description, mentions
/// légales et contact support. La version est figée ici (alignée sur
/// pubspec.yaml) pour éviter d'ajouter la dépendance package_info_plus.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const String _version = '1.0.0';
  static const String _supportEmail = 'support@loyatrack.com';

  Future<void> _contacterSupport() async {
    final uri = Uri(scheme: 'mailto', path: _supportEmail);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
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
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: context.cText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(t.about,
            style: TextStyle(
                color: context.cText,
                fontSize: 17,
                fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          const SizedBox(height: 12),
          // Logo + nom de marque + baseline.
          Center(
            child: Column(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset('assets/images/icon/loyatrack_icon.png',
                    width: 96, height: 96, fit: BoxFit.cover),
              ),
              const SizedBox(height: 16),
              Text('LoyaTrack',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: context.cText)),
              const SizedBox(height: 4),
              Text(t.aboutTagline,
                  style: TextStyle(fontSize: 13, color: context.cTextSub)),
              const SizedBox(height: 6),
              Text(t.aboutVersion(_version),
                  style: TextStyle(fontSize: 12, color: context.cTextSub)),
            ]),
          ),
          const SizedBox(height: 28),
          _Bloc(
            context: context,
            child: Text(t.aboutDescription,
                style: TextStyle(
                    fontSize: 13.5, color: context.cText, height: 1.55)),
          ),
          const SizedBox(height: 12),
          // Contact support (mailto).
          _Bloc(
            context: context,
            onTap: _contacterSupport,
            child: Row(children: [
              const Icon(Icons.mail_outline_rounded,
                  color: AppColors.blue, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.aboutContact,
                          style: TextStyle(
                              fontSize: 12, color: context.cTextSub)),
                      const SizedBox(height: 2),
                      Text(_supportEmail,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: context.cText)),
                    ]),
              ),
              Icon(Icons.chevron_right_rounded, color: context.cTextSub),
            ]),
          ),
          const SizedBox(height: 12),
          // Mention légale.
          _Bloc(
            context: context,
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.gavel_rounded,
                      color: AppColors.warning, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(t.aboutLegal,
                        style: TextStyle(
                            fontSize: 12,
                            color: context.cTextSub,
                            height: 1.5)),
                  ),
                ]),
          ),
          const SizedBox(height: 28),
          Center(
            child: Column(children: [
              Text(t.aboutMadeIn,
                  style: TextStyle(fontSize: 12, color: context.cTextSub)),
              const SizedBox(height: 6),
              Text(t.aboutRights,
                  style: TextStyle(fontSize: 11, color: context.cTextSub)),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Bloc extends StatelessWidget {
  final Widget child;
  final BuildContext context;
  final VoidCallback? onTap;
  const _Bloc({required this.child, required this.context, this.onTap});

  @override
  Widget build(BuildContext ctx) {
    final content = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ctx.cCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ctx.cBorder),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: content,
    );
  }
}
