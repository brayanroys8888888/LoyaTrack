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

// ── Messagerie (côté bailleur) ───────────────────────────────────────────────
class Message {
  final int id;
  final String expediteur; // 'chercheur' | 'bailleur'
  final String corps;
  final bool lu;
  final String dateEnvoi;
  const Message({
    required this.id,
    required this.expediteur,
    required this.corps,
    this.lu = false,
    this.dateEnvoi = '',
  });

  /// Côté app (bailleur) : un message du bailleur est « le mien ».
  bool get estMoi => expediteur == 'bailleur';

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        id: j['id'],
        expediteur: j['expediteur'] ?? 'chercheur',
        corps: j['corps'] ?? '',
        lu: j['lu'] ?? false,
        dateEnvoi: j['date_envoi'] ?? '',
      );
}

class Conversation {
  final int id;
  final int annonce;
  final String annonceTitre;
  final String annonceSlug;
  final String chercheurNom;
  final String statut; // ouverte | archivee | bloquee
  final String dateDernierMessage;
  final String dernierMessage;
  final int nonLus;
  final List<Message> messages;

  const Conversation({
    required this.id,
    required this.annonce,
    this.annonceTitre = '',
    this.annonceSlug = '',
    this.chercheurNom = '',
    this.statut = 'ouverte',
    this.dateDernierMessage = '',
    this.dernierMessage = '',
    this.nonLus = 0,
    this.messages = const [],
  });

  bool get estOuverte => statut == 'ouverte';

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: j['id'],
        annonce: j['annonce'] ?? 0,
        annonceTitre: j['annonce_titre'] ?? '',
        annonceSlug: j['annonce_slug'] ?? '',
        chercheurNom: j['chercheur_nom'] ?? '',
        statut: j['statut'] ?? 'ouverte',
        dateDernierMessage: j['date_dernier_message'] ?? '',
        dernierMessage: j['dernier_message'] ?? '',
        nonLus: j['non_lus'] ?? 0,
        messages: ((j['messages'] as List?) ?? const [])
            .map((m) => Message.fromJson(m))
            .toList(),
      );
}
