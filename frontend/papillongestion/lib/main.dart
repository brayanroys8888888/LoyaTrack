import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/firebase_service.dart';
import 'core/api_client.dart';
import 'core/locale_provider.dart';
import 'core/abonnement_provider.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/paywall_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Session perdue (refresh impossible) -> retour à l'écran de connexion.
  ApiClient.onSessionExpired = () {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
  };

  // Abonnement expiré (403 abonnement_expire) -> écran paywall bloquant.
  ApiClient.onSubscriptionExpired = () {
    abonnementProvider.rafraichir();
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    // Évite d'empiler plusieurs paywalls.
    if (ModalRoute.of(ctx)?.settings.name == 'paywall') return;
    navigatorKey.currentState?.push(MaterialPageRoute(
      builder: (_) => const PaywallScreen(),
      settings: const RouteSettings(name: 'paywall'),
    ));
  };

  // Fonction Pro requise (403 fonction_pro) -> feuille d'upsell.
  ApiClient.onProRequired = (feature) {
    final ctx = navigatorKey.currentContext;
    if (ctx != null) showProUpsell(ctx, feature: feature);
  };

  // Initialize Firebase and register background message handler
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await FirebaseService.initialize();

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: const PapillonApp(),
    ),
  );
}

class PapillonApp extends StatelessWidget {
  const PapillonApp({super.key});

  @override
  Widget build(BuildContext context) {
    final tp = Provider.of<ThemeProvider>(context);
    final lp = Provider.of<LocaleProvider>(context);
    return MaterialApp(
      title: 'LoyaTrack',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: tp.themeMode,
      locale: lp.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Applique la couleur de la barre système (statut + navigation) en
      // fonction du thème RÉSOLU (gère le mode « système »). Couvre aussi les
      // écrans sans AppBar (splash, login). Les écrans à AppBar appliquent en
      // plus leur propre style (icônes claires sur fond bleu).
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final navBar = isDark ? AppColors.bgDark : AppColors.bgLight;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
            statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: navBar,
            systemNavigationBarDividerColor: navBar,
            systemNavigationBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
          ),
          // Taper en dehors d'un champ ferme le clavier (corrige le clavier qui
          // « reste » ou réapparaît, notamment en ouvrant un bottom sheet sans
          // champ). Ne capte que les zones non interactives (deferToChild).
          child: GestureDetector(
            onTap: () {
              final f = FocusManager.instance.primaryFocus;
              if (f != null && f.hasFocus) f.unfocus();
            },
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: const SplashScreen(),
    );
  }
}
