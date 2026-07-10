/// Modèles de la vitrine d'annonces (marketplace de location) — Palier 1.

class Quartier {
  final int id;
  final String nom;
  final String slug;
  const Quartier({required this.id, required this.nom, required this.slug});

  factory Quartier.fromJson(Map<String, dynamic> j) =>
      Quartier(id: j['id'], nom: j['nom'] ?? '', slug: j['slug'] ?? '');
}

class Ville {
  final int id;
  final String nom;
  final String slug;
  final String region;
  final List<Quartier> quartiers;
  const Ville({
    required this.id,
    required this.nom,
    required this.slug,
    this.region = '',
    this.quartiers = const [],
  });

  factory Ville.fromJson(Map<String, dynamic> j) => Ville(
        id: j['id'],
        nom: j['nom'] ?? '',
        slug: j['slug'] ?? '',
        region: j['region'] ?? '',
        quartiers: ((j['quartiers'] as List?) ?? const [])
            .map((q) => Quartier.fromJson(q))
            .toList(),
      );
}

class PhotoAnnonce {
  final int id;
  final String image; // URL absolue (fournie par le backend)
  final int ordre;
  final bool estCouverture;
  const PhotoAnnonce({
    required this.id,
    required this.image,
    this.ordre = 0,
    this.estCouverture = false,
  });

  factory PhotoAnnonce.fromJson(Map<String, dynamic> j) => PhotoAnnonce(
        id: j['id'],
        image: j['image'] ?? '',
        ordre: j['ordre'] ?? 0,
        estCouverture: j['est_couverture'] ?? false,
      );
}

class Annonce {
  final int id;
  final String reference;
  final String slug;
  final String urlPublique;
  final String statut; // brouillon | publiee | pourvue | expiree | suspendue | en_moderation
  final bool estVisible;
  final int? unite;
  final String typeBien;
  final int nbChambres, nbSalons, nbCuisines, nbDouches;
  final int? superficieM2;
  final bool meuble;
  final String standing;
  final int? ville;
  final String villeNom;
  final int? quartier;
  final String quartierNom;
  final String adresseIndicative;
  final double loyer, charges;
  final int cautionMois;
  final String titre, description;
  final int nbVues, nbContacts;
  final List<PhotoAnnonce> photos;

  const Annonce({
    required this.id,
    required this.reference,
    required this.slug,
    required this.urlPublique,
    required this.statut,
    this.estVisible = false,
    this.unite,
    this.typeBien = 'appartement',
    this.nbChambres = 1,
    this.nbSalons = 1,
    this.nbCuisines = 1,
    this.nbDouches = 1,
    this.superficieM2,
    this.meuble = false,
    this.standing = '',
    this.ville,
    this.villeNom = '',
    this.quartier,
    this.quartierNom = '',
    this.adresseIndicative = '',
    this.loyer = 0,
    this.charges = 0,
    this.cautionMois = 1,
    this.titre = '',
    this.description = '',
    this.nbVues = 0,
    this.nbContacts = 0,
    this.photos = const [],
  });

  bool get estPubliee => statut == 'publiee';

  static double _d(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;

  factory Annonce.fromJson(Map<String, dynamic> j) => Annonce(
        id: j['id'],
        reference: j['reference'] ?? '',
        slug: j['slug'] ?? '',
        urlPublique: j['url_publique'] ?? '',
        statut: j['statut'] ?? 'brouillon',
        estVisible: j['est_visible'] ?? false,
        unite: j['unite'],
        typeBien: j['type_bien'] ?? 'appartement',
        nbChambres: j['nb_chambres'] ?? 1,
        nbSalons: j['nb_salons'] ?? 1,
        nbCuisines: j['nb_cuisines'] ?? 1,
        nbDouches: j['nb_douches'] ?? 1,
        superficieM2: j['superficie_m2'],
        meuble: j['meuble'] ?? false,
        standing: j['standing'] ?? '',
        ville: j['ville'],
        villeNom: j['ville_nom'] ?? '',
        quartier: j['quartier'],
        quartierNom: j['quartier_nom'] ?? '',
        adresseIndicative: j['adresse_indicative'] ?? '',
        loyer: _d(j['loyer']),
        charges: _d(j['charges']),
        cautionMois: j['caution_mois'] ?? 1,
        titre: j['titre'] ?? '',
        description: j['description'] ?? '',
        nbVues: j['nb_vues'] ?? 0,
        nbContacts: j['nb_contacts'] ?? 0,
        photos: ((j['photos'] as List?) ?? const [])
            .map((p) => PhotoAnnonce.fromJson(p))
            .toList(),
      );

  PhotoAnnonce? get couverture {
    if (photos.isEmpty) return null;
    return photos.firstWhere((p) => p.estCouverture, orElse: () => photos.first);
  }
}

/// Résultat d'une tentative de publication : l'annonce à jour, ou la liste des
/// manques renvoyés par le backend (auto-checks).
class ResultatPublication {
  final Annonce? annonce;
  final List<String> erreurs;
  const ResultatPublication({this.annonce, this.erreurs = const []});
  bool get ok => annonce != null;
}
