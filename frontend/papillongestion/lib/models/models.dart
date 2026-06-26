import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';

enum StatutLocataire { paye, nonPaye, enDiscussion, enPenalite }
enum ModePaiement    { mobileMoney, especes, virement }
enum TypeRappel      { sms, whatsapp, appel }
enum StatutRappel    { envoye, echec, enAttente }

extension StatutExt on StatutLocataire {
  String get label => switch (this) {
    StatutLocataire.paye         => 'Payé',
    StatutLocataire.nonPaye      => 'En retard',
    StatutLocataire.enDiscussion => 'En discussion',
    StatutLocataire.enPenalite   => 'Pénalité',
  };
  Color get color => switch (this) {
    StatutLocataire.paye         => AppColors.success,
    StatutLocataire.nonPaye      => AppColors.danger,
    StatutLocataire.enDiscussion => AppColors.warning,
    StatutLocataire.enPenalite   => AppColors.penalty,
  };
  Color bgColor(BuildContext ctx) => switch (this) {
    StatutLocataire.paye         => ctx.cSuccessBg,
    StatutLocataire.nonPaye      => ctx.cDangerBg,
    StatutLocataire.enDiscussion => ctx.cWarningBg,
    StatutLocataire.enPenalite   => ctx.cPenaltyBg,
  };
  String get icon => switch (this) {
    StatutLocataire.paye         => '✓',
    StatutLocataire.nonPaye      => '●',
    StatutLocataire.enDiscussion => '◐',
    StatutLocataire.enPenalite   => '⚠',
  };
}

StatutLocataire statutFromString(String status) {
  switch (status) {
    case 'Payé':          return StatutLocataire.paye;
    case 'En retard':     return StatutLocataire.nonPaye;
    case 'En discussion': return StatutLocataire.enDiscussion;
    case 'En pénalité':  return StatutLocataire.enPenalite;
    default:              return StatutLocataire.paye;
  }
}

extension ModeExt on ModePaiement {
  String get label => switch (this) {
    ModePaiement.mobileMoney => 'Mobile Money',
    ModePaiement.especes     => 'Espèces',
    ModePaiement.virement    => 'Virement',
  };
  Color get color => switch (this) {
    ModePaiement.mobileMoney => AppColors.success,
    ModePaiement.especes     => AppColors.warning,
    ModePaiement.virement    => AppColors.blue,
  };
  Color bgColor(BuildContext ctx) => switch (this) {
    ModePaiement.mobileMoney => ctx.cSuccessBg,
    ModePaiement.especes     => ctx.cWarningBg,
    ModePaiement.virement    => ctx.cBlue3,
  };
  IconData get icon => switch (this) {
    ModePaiement.mobileMoney => Icons.phone_android_rounded,
    ModePaiement.especes     => Icons.payments_rounded,
    ModePaiement.virement    => Icons.account_balance_rounded,
  };
}

ModePaiement modePaiementFromString(String mode) {
  switch (mode) {
    case 'Mobile Money': return ModePaiement.mobileMoney;
    case 'Espèces':      return ModePaiement.especes;
    case 'Virement':     return ModePaiement.virement;
    default:             return ModePaiement.especes;
  }
}

class Locataire {
  final String id, nom, telephone, logement;
  final double montantLoyer;
  final int jourEcheance;
  final StatutLocataire statut;
  final DateTime dateEntree;
  final double penaliteJournaliere;
  final String? notes;
  final String? signature;
  final bool modeTest;
  final String languePreferee; // 'fr' | 'en' — langue des rappels
  // Mentions légales (contrat / quittance)
  final String adresseLogement;
  final double chargesMensuelles;
  final int dureeBailMois;
  final String frequencePaiement; // mensuel | trimestriel | semestriel | annuel
  // Infos personnelles / identité (documents légaux)
  final String profession;
  final double? revenusMensuels;
  final String typePieceIdentite; // CNI | Passeport | Permis | ''
  final String numeroPieceIdentite;
  /// Pièces d'identité jointes (recto/verso/PDF). Chaque entrée : {id, url, libelle}.
  final List<Map<String, dynamic>> piecesIdentite;

  const Locataire({
    required this.id, required this.nom, required this.telephone,
    required this.logement, required this.montantLoyer,
    required this.jourEcheance, required this.statut, required this.dateEntree,
    this.penaliteJournaliere = 3000, this.notes, this.signature,
    this.modeTest = false, this.languePreferee = 'fr',
    this.adresseLogement = '', this.chargesMensuelles = 0,
    this.dureeBailMois = 12, this.frequencePaiement = 'mensuel',
    this.profession = '', this.revenusMensuels,
    this.typePieceIdentite = '', this.numeroPieceIdentite = '',
    this.piecesIdentite = const [],
  });

  factory Locataire.fromJson(Map<String, dynamic> json) {
    final nomStr = json['nom'] ?? '';
    final prenomStr = json['prenom'] ?? '';
    final fullName = '$prenomStr $nomStr'.trim();

    return Locataire(
      id: json['id']?.toString() ?? '',
      nom: fullName.isNotEmpty ? fullName : 'Inconnu',
      telephone: json['telephone'] ?? '',
      logement: json['logement'] ?? 'Non assigné',
      montantLoyer: double.tryParse(json['montant_loyer']?.toString() ?? '0') ?? 0,
      jourEcheance: int.tryParse(json['jour_echeance']?.toString() ?? '1') ?? 1,
      statut: statutFromString(json['statut'] ?? 'Payé'),
      dateEntree: json['date_entree'] != null ? DateTime.parse(json['date_entree']) : DateTime.now(),
      penaliteJournaliere: double.tryParse(json['penalite_journaliere']?.toString() ?? '3000') ?? 3000,
      notes: json['notes'],
      signature: json['signature_base64'] ?? json['signature'],
      modeTest: json['mode_test'] ?? false,
      languePreferee: json['langue_preferee']?.toString() ?? 'fr',
      adresseLogement: json['adresse_logement']?.toString() ?? '',
      chargesMensuelles: double.tryParse(json['charges_mensuelles']?.toString() ?? '0') ?? 0,
      dureeBailMois: int.tryParse(json['duree_bail_mois']?.toString() ?? '12') ?? 12,
      frequencePaiement: json['frequence_paiement']?.toString() ?? 'mensuel',
      profession: json['profession']?.toString() ?? '',
      revenusMensuels: double.tryParse(json['revenus_mensuels']?.toString() ?? ''),
      typePieceIdentite: json['type_piece_identite']?.toString() ?? '',
      numeroPieceIdentite: json['numero_piece_identite']?.toString() ?? '',
      piecesIdentite: (json['pieces_identite'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
    );
  }

  String get initiales => nom.trim().split(' ').take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();

  static List<Locataire> get mockData => [
    Locataire(id:'1', nom:'Jean Dupont',    telephone:'+237 6 91 23 45 67', logement:'Chambre A1',  montantLoyer:50000, jourEcheance:5,  statut:StatutLocataire.paye,         dateEntree:DateTime(2024,1,5),  notes:'Locataire ponctuel'),
    Locataire(id:'2', nom:'Paul Martin',    telephone:'+237 6 78 90 12 34', logement:'Studio B2',   montantLoyer:75000, jourEcheance:1,  statut:StatutLocataire.enPenalite,   dateEntree:DateTime(2023,6,1),  penaliteJournaliere:5000),
    Locataire(id:'3', nom:'Marie Atangana', telephone:'+237 6 55 44 33 22', logement:'Appart. D3',  montantLoyer:90000, jourEcheance:3,  statut:StatutLocataire.enDiscussion, dateEntree:DateTime(2024,3,2),  notes:'Difficultés temporaires'),
    Locataire(id:'4', nom:'Koné Diallo',    telephone:'+237 6 12 34 56 78', logement:'Chambre E1',  montantLoyer:45000, jourEcheance:10, statut:StatutLocataire.paye,         dateEntree:DateTime(2023,10,10)),
    Locataire(id:'5', nom:'Fatima Ndiaye',  telephone:'+237 6 99 88 77 66', logement:'Studio F2',   montantLoyer:60000, jourEcheance:2,  statut:StatutLocataire.nonPaye,      dateEntree:DateTime(2024,4,3)),
    Locataire(id:'6', nom:'Sophie Claire',  telephone:'+237 6 45 67 89 01', logement:'Chambre C3',  montantLoyer:50000, jourEcheance:7,  statut:StatutLocataire.paye,         dateEntree:DateTime(2022,7,7)),
     Locataire(id:'7', nom:'Jean Dupont',    telephone:'+237 6 91 23 45 67', logement:'Chambre A1',  montantLoyer:50000, jourEcheance:5,  statut:StatutLocataire.paye,         dateEntree:DateTime(2024,1,5),  notes:'Locataire ponctuel'),
    Locataire(id:'8', nom:'Paul Martin',    telephone:'+237 6 78 90 12 34', logement:'Studio B2',   montantLoyer:75000, jourEcheance:1,  statut:StatutLocataire.enPenalite,   dateEntree:DateTime(2023,6,1),  penaliteJournaliere:5000),
    Locataire(id:'9', nom:'Marie Atangana', telephone:'+237 6 55 44 33 22', logement:'Appart. D3',  montantLoyer:90000, jourEcheance:3,  statut:StatutLocataire.enDiscussion, dateEntree:DateTime(2024,3,2),  notes:'Difficultés temporaires'),
    Locataire(id:'10', nom:'Koné Diallo',    telephone:'+237 6 12 34 56 78', logement:'Chambre E1',  montantLoyer:45000, jourEcheance:10, statut:StatutLocataire.paye,         dateEntree:DateTime(2023,10,10)),
    Locataire(id:'11', nom:'Fatima Ndiaye',  telephone:'+237 6 99 88 77 66', logement:'Studio F2',   montantLoyer:60000, jourEcheance:2,  statut:StatutLocataire.nonPaye,      dateEntree:DateTime(2024,4,3)),
    Locataire(id:'12', nom:'Sophie Claire',  telephone:'+237 6 45 67 89 01', logement:'Chambre C3',  montantLoyer:50000, jourEcheance:7,  statut:StatutLocataire.paye,         dateEntree:DateTime(2022,7,7)),
     Locataire(id:'13', nom:'Jean Dupont',    telephone:'+237 6 91 23 45 67', logement:'Chambre A1',  montantLoyer:50000, jourEcheance:5,  statut:StatutLocataire.paye,         dateEntree:DateTime(2024,1,5),  notes:'Locataire ponctuel'),
    Locataire(id:'14', nom:'Paul Martin',    telephone:'+237 6 78 90 12 34', logement:'Studio B2',   montantLoyer:75000, jourEcheance:1,  statut:StatutLocataire.enPenalite,   dateEntree:DateTime(2023,6,1),  penaliteJournaliere:5000),
    Locataire(id:'15', nom:'Marie Atangana', telephone:'+237 6 55 44 33 22', logement:'Appart. D3',  montantLoyer:90000, jourEcheance:3,  statut:StatutLocataire.enDiscussion, dateEntree:DateTime(2024,3,2),  notes:'Difficultés temporaires'),
    Locataire(id:'16', nom:'Koné Diallo',    telephone:'+237 6 12 34 56 78', logement:'Chambre E1',  montantLoyer:45000, jourEcheance:10, statut:StatutLocataire.paye,         dateEntree:DateTime(2023,10,10)),
    Locataire(id:'17', nom:'Fatima Ndiaye',  telephone:'+237 6 99 88 77 66', logement:'Studio F2',   montantLoyer:60000, jourEcheance:2,  statut:StatutLocataire.nonPaye,      dateEntree:DateTime(2024,4,3)),
    Locataire(id:'18', nom:'Sophie Claire',  telephone:'+237 6 45 67 89 01', logement:'Chambre C3',  montantLoyer:50000, jourEcheance:7,  statut:StatutLocataire.paye,         dateEntree:DateTime(2022,7,7)),
     Locataire(id:'19', nom:'Jean Dupont',    telephone:'+237 6 91 23 45 67', logement:'Chambre A1',  montantLoyer:50000, jourEcheance:5,  statut:StatutLocataire.paye,         dateEntree:DateTime(2024,1,5),  notes:'Locataire ponctuel'),
  ];
}

class Paiement {
  final String id, locataireId, nomLocataire, logement, moisConcerne;
  final double montant;
  final DateTime datePaiement;
  final ModePaiement mode;
  final String? remarque;
  // Données réelles renvoyées par appliquer_paiement() côté serveur
  final String reference;
  final String typePaiement; // complet | partiel | avance
  final double resteDu;
  final int nbMois;
  final DateTime? periodeDebut;
  final DateTime? periodeFin;

  const Paiement({
    required this.id, required this.locataireId, required this.nomLocataire,
    required this.logement, required this.montant, required this.datePaiement,
    required this.moisConcerne, required this.mode, this.remarque,
    this.reference = '', this.typePaiement = 'complet', this.resteDu = 0,
    this.nbMois = 1, this.periodeDebut, this.periodeFin,
  });

  factory Paiement.fromJson(Map<String, dynamic> json) {
    final prenom = json['locataire_prenom'] ?? '';
    final nom = json['locataire_nom'] ?? '';
    final nomComplet = '$prenom $nom'.trim();

    final dateP = json['date_paiement'] != null
        ? DateTime.parse(json['date_paiement'])
        : DateTime.now();

    // Convertir la date en mois (ex: "Mai 2025")
    const months = ['Jan.', 'Fév.', 'Mars', 'Avr.', 'Mai', 'Juin', 'Juil.', 'Août', 'Sept.', 'Oct.', 'Nov.', 'Déc.'];
    final monthStr = '${months[dateP.month - 1]} ${dateP.year}';

    DateTime? parseDate(dynamic v) =>
        (v != null && v.toString().isNotEmpty) ? DateTime.tryParse(v.toString()) : null;
    final logementReel = (json['locataire_logement'] ?? '').toString().trim();

    return Paiement(
      id: json['id']?.toString() ?? '',
      locataireId: json['locataire']?.toString() ?? '',
      nomLocataire: nomComplet.isNotEmpty ? nomComplet : 'Inconnu',
      logement: logementReel.isNotEmpty ? logementReel : 'Non assigné',
      montant: double.tryParse(json['montant']?.toString() ?? '0') ?? 0,
      datePaiement: dateP,
      moisConcerne: monthStr,
      mode: modePaiementFromString(json['mode_paiement'] ?? 'Espèces'),
      remarque: null,
      reference: json['reference']?.toString() ?? '',
      typePaiement: json['statut']?.toString() ?? 'complet',
      resteDu: double.tryParse(json['reste_du']?.toString() ?? '0') ?? 0,
      nbMois: int.tryParse(json['nb_mois']?.toString() ?? '1') ?? 1,
      periodeDebut: parseDate(json['periode_debut']),
      periodeFin: parseDate(json['periode_fin']),
    );
  }

  String get initiales => nomLocataire.trim().split(' ').take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();

  static List<Paiement> get mockData => [
    Paiement(id:'p1', locataireId:'1', nomLocataire:'Jean Dupont',    logement:'Chambre A1', montant:50000, datePaiement:DateTime(2025,5,2),  moisConcerne:'Mai 2025',   mode:ModePaiement.mobileMoney),
    Paiement(id:'p2', locataireId:'2', nomLocataire:'Paul Martin',    logement:'Studio B2',  montant:75000, datePaiement:DateTime(2025,5,1),  moisConcerne:'Mai 2025',   mode:ModePaiement.especes),
    Paiement(id:'p3', locataireId:'4', nomLocataire:'Koné Diallo',    logement:'Chambre E1', montant:45000, datePaiement:DateTime(2025,5,3),  moisConcerne:'Mai 2025',   mode:ModePaiement.virement),
    Paiement(id:'p4', locataireId:'6', nomLocataire:'Sophie Claire',  logement:'Chambre C3', montant:50000, datePaiement:DateTime(2025,4,28), moisConcerne:'Avr. 2025',  mode:ModePaiement.mobileMoney),
    Paiement(id:'p5', locataireId:'1', nomLocataire:'Jean Dupont',    logement:'Chambre A1', montant:50000, datePaiement:DateTime(2025,4,4),  moisConcerne:'Avr. 2025',  mode:ModePaiement.mobileMoney),
    Paiement(id:'p6', locataireId:'3', nomLocataire:'Marie Atangana', logement:'Appart. D3', montant:90000, datePaiement:DateTime(2025,4,5),  moisConcerne:'Avr. 2025',  mode:ModePaiement.especes),
    Paiement(id:'p7', locataireId:'5', nomLocataire:'Fatima Ndiaye',  logement:'Studio F2',  montant:60000, datePaiement:DateTime(2025,3,3),  moisConcerne:'Mars 2025',  mode:ModePaiement.virement),
    Paiement(id:'p8', locataireId:'4', nomLocataire:'Koné Diallo',    logement:'Chambre E1', montant:45000, datePaiement:DateTime(2025,3,9),  moisConcerne:'Mars 2025',  mode:ModePaiement.mobileMoney),
    Paiement(id:'p9', locataireId:'2', nomLocataire:'Paul Martin',    logement:'Studio B2',  montant:75000, datePaiement:DateTime(2025,3,2),  moisConcerne:'Mars 2025',  mode:ModePaiement.especes),
  ];
}

class Rappel {
  final String id, locataireId;
  final TypeRappel type;
  final StatutRappel statut;
  final DateTime dateEnvoi;
  final String message;
  final String statutLivraison; // queued/sent/delivered/read/failed/undelivered (webhook Twilio)

  const Rappel({required this.id, required this.locataireId, required this.type, required this.statut, required this.dateEnvoi, required this.message, this.statutLivraison = ''});

  factory Rappel.fromJson(Map<String, dynamic> json) {
    TypeRappel parseType(String t) {
      if (t == 'WhatsApp') return TypeRappel.whatsapp;
      if (t == 'Appel') return TypeRappel.appel;
      return TypeRappel.sms;
    }
    
    StatutRappel parseStatut(String s) {
      if (s == 'Envoyé') return StatutRappel.envoye;
      if (s == 'En attente') return StatutRappel.enAttente;
      return StatutRappel.echec;
    }

    return Rappel(
      id: json['id']?.toString() ?? '',
      locataireId: json['locataire']?.toString() ?? '',
      type: parseType(json['type_rappel'] ?? 'SMS'),
      statut: parseStatut(json['statut'] ?? 'En attente'),
      dateEnvoi: json['date_envoi'] != null ? DateTime.parse(json['date_envoi']) : DateTime.now(),
      message: 'Rappel automatique envoyé via API',
      statutLivraison: json['statut_livraison'] ?? '',
    );
  }

  /// Libellé lisible de l'accusé de réception Twilio (2.6).
  String get livraisonLabel => switch (statutLivraison) {
    'delivered' => 'Livré',
    'read'      => 'Lu',
    'sent'      => 'Envoyé',
    'queued'    => 'En file',
    'failed' || 'undelivered' => 'Échec livraison',
    _ => '',
  };

  String get typeLabel => switch (type) {
    TypeRappel.sms      => 'SMS',
    TypeRappel.whatsapp => 'WhatsApp',
    TypeRappel.appel    => 'Appel vocal IA',
  };
  String get statutLabel => switch (statut) {
    StatutRappel.envoye    => 'Délivré ✓',
    StatutRappel.echec     => 'Échec ✗',
    StatutRappel.enAttente => 'En attente…',
  };
  Color get statutColor => switch (statut) {
    StatutRappel.envoye    => AppColors.success,
    StatutRappel.echec     => AppColors.danger,
    StatutRappel.enAttente => AppColors.warning,
  };

  static List<Rappel> forLocataire(String id) => [
    Rappel(id:'r1', locataireId:id, type:TypeRappel.whatsapp, statut:StatutRappel.envoye,  dateEnvoi:DateTime(2025,4,26), message:'Votre loyer arrive à échéance dans 5 jours.'),
    Rappel(id:'r2', locataireId:id, type:TypeRappel.appel,    statut:StatutRappel.envoye,  dateEnvoi:DateTime(2025,4,30), message:'Votre loyer est dû demain.'),
    Rappel(id:'r3', locataireId:id, type:TypeRappel.sms,      statut:StatutRappel.enAttente, dateEnvoi:DateTime(2025,5,1),  message:'Rappel de retard de paiement.'),
  ];
}

class Penalite {
  final String id, locataireId;
  final DateTime dateDebut;
  final DateTime? dateFin;
  final double montantJournalier;
  final double montantTotal;
  final int nbJours;
  final bool active;

  const Penalite({required this.id, required this.locataireId, required this.dateDebut, this.dateFin, required this.montantJournalier, required this.montantTotal, required this.nbJours, required this.active});
}

// ─── Helpers ─────────────────────────────────────────────────────────────────
String formatMontant(double v) {
  final s = v.toInt().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return buf.toString();
}

String formatDate(DateTime d) => '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';

String relativeDate(DateTime d) {
  final diff = DateTime.now().difference(d).inDays;
  if (diff == 0) return "Aujourd'hui";
  if (diff == 1) return 'Hier';
  return '${d.day} ${_months[d.month - 1]}';
}

const _months = ['jan.','fév.','mars','avr.','mai','juin','juil.','août','sep.','oct.','nov.','déc.'];
const _monthsEn = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

// ─── Helpers localisés (FR/EN) ───────────────────────────────────────────────
String relativeDateL(DateTime d, AppLocalizations t, String lang) {
  final diff = DateTime.now().difference(d).inDays;
  if (diff == 0) return t.today;
  if (diff == 1) return t.yesterday;
  final months = lang == 'en' ? _monthsEn : _months;
  return '${d.day} ${months[d.month - 1]}';
}

String statutLabelL(StatutLocataire s, AppLocalizations t) => switch (s) {
  StatutLocataire.paye         => t.statusPaid,
  StatutLocataire.nonPaye      => t.statusLate,
  StatutLocataire.enDiscussion => t.statusDiscussion,
  StatutLocataire.enPenalite   => t.statusPenalty,
};

String modeLabelL(ModePaiement m, AppLocalizations t) => switch (m) {
  ModePaiement.mobileMoney => t.modeMobileMoney,
  ModePaiement.especes     => t.modeCash,
  ModePaiement.virement    => t.modeTransfer,
};

String rappelTypeLabelL(TypeRappel ty, AppLocalizations t) => switch (ty) {
  TypeRappel.sms      => t.rappelSms,
  TypeRappel.whatsapp => t.rappelWhatsapp,
  TypeRappel.appel    => t.rappelCallAI,
};

String rappelStatutLabelL(StatutRappel st, AppLocalizations t) => switch (st) {
  StatutRappel.envoye    => t.rappelDelivered,
  StatutRappel.echec     => t.rappelFailed,
  StatutRappel.enAttente => t.rappelPending,
};

// ─── Abonnement (monétisation) ───────────────────────────────────────────────
/// Statut d'abonnement du bailleur, lu depuis l'API (`GET /abonnement/`).
/// L'app ne contient aucun paiement : le règlement se fait sur le web.
class Abonnement {
  final String plan;          // 'essentiel' | 'pro'
  final String statut;        // 'essai' | 'actif' | 'grace' | 'expire' | 'annule'
  final String? droits;       // 'pro' | 'essentiel' | null (expiré)
  final bool estActif;
  final int joursRestants;
  final List<String> features; // fonctions Pro débloquées
  final int? maxBiens;        // null = illimité

  const Abonnement({
    required this.plan,
    required this.statut,
    required this.droits,
    required this.estActif,
    required this.joursRestants,
    required this.features,
    required this.maxBiens,
  });

  bool aDroit(String feature) => features.contains(feature);
  bool get estEssai => statut == 'essai';
  bool get estPro => droits == 'pro';

  factory Abonnement.fromJson(Map<String, dynamic> j) => Abonnement(
        plan: j['plan'] ?? 'essentiel',
        statut: j['statut'] ?? 'expire',
        droits: j['droits'],
        estActif: j['est_actif'] ?? false,
        joursRestants: j['jours_restants'] ?? 0,
        features: List<String>.from(j['features'] ?? const []),
        maxBiens: j['max_biens'],
      );

  /// État de repli quand l'API est injoignable : on n'enferme pas l'utilisateur.
  static const Abonnement inconnu = Abonnement(
    plan: 'pro', statut: 'actif', droits: 'pro', estActif: true,
    joursRestants: 0, features: [
      'rappels_auto','penalites_auto','multi_biens','comptabilite',
      'documents_legaux','portail','import_masse',
    ], maxBiens: null,
  );
}

/// Libellé localisé d'une fonctionnalité Pro (clé technique → texte).
String featureLabelL(String f, AppLocalizations t) => switch (f) {
  'rappels_auto'     => t.featRappelsAuto,
  'penalites_auto'   => t.featPenalitesAuto,
  'multi_biens'      => t.featMultiBiens,
  'comptabilite'     => t.featComptabilite,
  'documents_legaux' => t.featDocumentsLegaux,
  'portail'          => t.featPortail,
  'import_masse'     => t.featImportMasse,
  _                  => f,
};
