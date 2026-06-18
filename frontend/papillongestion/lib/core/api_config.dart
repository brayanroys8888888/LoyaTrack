class ApiConfig {
  // Utilisé par l'émulateur Android pour pointer vers localhost
  // Si tu utilises un appareil physique, remplace par l'IP de ta machine (ex: 'http://192.168.1.15:8000/api/v1/')
  static const String baseUrl = 'http://10.0.2.2:8000/api/v1/';

  // Espace web du bailleur (paiement de l'abonnement via CinetPay) — Phase 3.
  // À remplacer par l'URL de prod (https) au déploiement.
  static const String manageSubscriptionUrl = 'http://10.0.2.2:8000/abonnement/';
}
