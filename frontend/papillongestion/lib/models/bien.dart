/// Modèles du module multi-biens (Propriete + UniteLogement).

class Propriete {
  final int id;
  final String titre;
  final String adresse;
  final String type;
  final int nbUnites;
  final int nbOccupees;
  final double tauxOccupation;
  final double revenusAttendus;

  const Propriete({
    required this.id,
    required this.titre,
    required this.adresse,
    required this.type,
    this.nbUnites = 0,
    this.nbOccupees = 0,
    this.tauxOccupation = 0,
    this.revenusAttendus = 0,
  });

  factory Propriete.fromJson(Map<String, dynamic> json) => Propriete(
        id: json['id'],
        titre: json['titre'] ?? '',
        adresse: json['adresse'] ?? '',
        type: json['type'] ?? 'immeuble',
        nbUnites: json['nb_unites'] ?? 0,
        nbOccupees: json['nb_occupees'] ?? 0,
        tauxOccupation: double.tryParse(json['taux_occupation']?.toString() ?? '0') ?? 0,
        revenusAttendus: double.tryParse(json['revenus_attendus']?.toString() ?? '0') ?? 0,
      );

  int get nbVacantes => nbUnites - nbOccupees;
}

class UniteLogement {
  final int id;
  final int propriete;
  final String numero;
  final double loyerStandard;
  final String statut; // 'occupe' | 'vacant'
  final String? locataireNom;

  const UniteLogement({
    required this.id,
    required this.propriete,
    required this.numero,
    required this.loyerStandard,
    required this.statut,
    this.locataireNom,
  });

  factory UniteLogement.fromJson(Map<String, dynamic> json) => UniteLogement(
        id: json['id'],
        propriete: json['propriete'],
        numero: json['numero'] ?? '',
        loyerStandard: double.tryParse(json['loyer_standard']?.toString() ?? '0') ?? 0,
        statut: json['statut'] ?? 'vacant',
        locataireNom: json['locataire_nom'],
      );

  bool get estOccupee => statut == 'occupe';
}
