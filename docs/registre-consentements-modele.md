# Modèle de registre des consentements (DOCUMENT STRICTEMENT HORS DÉPÔT)

> **AVERTISSEMENT DE SÉCURITÉ** :  
> Le fichier effectif `registre-consentements.csv` contient des données à caractère personnel (nom, coordonnées réelles).  
> **Il NE DOIT JAMAIS ÊTRE COMMITTÉ DANS LE DÉPÔT GIT.**  
> Il doit être conservé sur un support chiffré séparé, distinct même du volume `blurr-data/`.

---

## Structure du fichier `registre-consentements.csv`

```csv
participant_id,nom_prenom,email,date_signature,clips_concernes,autorisation_jeu_public,statut_retrait,date_retrait
P01,Participant Exemple,exemple@domaine.fr,2026-10-15,"C01,C02,C05",NON,ACTIF,
P02,Autre Personne,autre@domaine.fr,2026-10-15,"C01,C03",OUI,ACTIF,
```

### Description des champs

- `participant_id` : Identifiant pseudonymisé (ex: `P01`, `P02`). Seul cet identifiant apparaît dans `dataset/manifest.csv` et dans les annotations.
- `nom_prenom` : Nom complet du signataire.
- `email` : Adresse de contact pour la revue annuelle obligatoire.
- `date_signature` : Date de signature du formulaire (AAAA-MM-JJ).
- `clips_concernes` : Liste des clips dans lesquels le participant apparaît.
- `autorisation_jeu_public` : `OUI` si la case optionnelle d'extrait public non masqué a été cochée, `NON` sinon.
- `statut_retrait` : `ACTIF` ou `RETIRE`.
- `date_retrait` : Date de traitement de la demande de retrait le cas échéant.
