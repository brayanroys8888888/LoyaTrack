class ApiConfig {
  // URL racine de l'API (slash final). Par défaut : alias émulateur Android → hôte.
  // Surchargeable au build : flutter run --dart-define=API_BASE=https://.../api/v1/
  static const String baseUrl = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://10.0.2.2:8000/api/v1/',
  );

  // Même base sans slash final (services qui concatènent "/...").
  static String get apiRoot =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  // Base web (espace abonnement bailleur, paiement). --dart-define=WEB_BASE=https://...
  static const String webBase = String.fromEnvironment(
    'WEB_BASE',
    defaultValue: 'http://10.0.2.2:8000',
  );

  // Page de gestion de l'abonnement (ouverte dans le navigateur).
  static String get manageSubscriptionUrl => '$webBase/abonnement/';
}
