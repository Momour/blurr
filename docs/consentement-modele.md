# Modèle de formulaire de consentement éclairé

Projet : **blurr** — Logiciel libre de masquage automatique des visages dans les vidéos.

---

## 1. Finalité de la collecte

Les vidéos enregistrées dans le cadre de ce projet ont pour unique finalité l'évaluation technique et l'entraînement d'algorithmes de masquage (floutage / occultation) des visages.
- Le traitement effectue uniquement de la **détection** de visage sans identification ni **reconnaissance faciale biométrique**.
- Les vidéos brutes et les images extraites sont destinées à un **usage interne exclusif** sur machine locale sécurisée et ne feront l'objet d'aucune publication ou diffusion publique.

## 2. Durée de conservation et révision

- Les enregistrements et annotations associées sont conservés **pendant toute la durée de maintenance active du projet blurr**, afin de permettre la validation continue de non-régression des futures versions.
- Une **revue annuelle** de la conservation est menée. À chaque revue, une information de rappel est adressée aux participants par courrier électronique.

## 3. Confidentialité et sécurité des données

- Les fichiers vidéos bruts, images extraites et annotations sont stockés exclusivement sur un volume local chiffré (`blurr-data/`) ainsi que sur une sauvegarde chiffrée hors ligne.
- Aucun fichier média n'est hébergé sur des dépôts de code publics ou tiers non sécurisés.
- Les fichiers et pistes d'annotation sont pseudonymisés : seul un identifiant participant (ex. `P01`, `P02`) est rattaché aux clips. Le lien d'identité est consigné dans un registre confidentiel isolé.

## 4. Exclusion des personnes mineures

La participation est réservée aux personnes majeures, sauf autorisation écrite et conjointe expresse des deux responsables légaux pour un participant mineur.

## 5. Droit de retrait

Conformément à la réglementation sur la protection des données personnelles (RGPD) :
- Vous disposez du droit de retirer votre consentement à tout moment, sans justification ni préjudice, par simple demande auprès du responsable du projet.
- Dès notification du retrait, l'ensemble des données associées à votre identifiant sera intégralement et définitivement effacé de tous les supports (fichiers bruts, images extraites, volumes CVAT, annotations, masques calculés, rapports d'évaluation, sauvegardes).

---

## Formulaire à remplir par le / la participant(e)

Nom et Prénom : __________________________________________________  
Adresse e-mail : _________________________________________________  
Identifiant attribué (réservé administration) : `P____`  
Date : ____ / ____ / 2026  

### Cases obligatoires :
- [ ] J'atteste être majeur(e) (ou présenter l'accord écrit conjoint de mes deux représentants légaux).
- [ ] J'accepte d'être filmé(e) pour les besoins exclusifs de test interne du logiciel blurr, selon les conditions et garanties définies ci-dessus.
- [ ] J'ai pris connaissance de mon droit de retrait à tout moment.

### Case optionnelle (Jeu de test public de non-régression) :
> **Attention** : Cette case est totalement facultative et indépendante de votre participation au jeu de test interne.  
- [ ] **Autorisation d'extrait pour jeu public** : J'autorise expressément le projet blurr à inclure un extrait vidéo court me représentant dans un jeu de données public de non-régression.  
  *Je reconnais être expressément informé(e) que dans ce cadre :*
  1. Cet extrait sera publié publiquement **avec mon visage visible et non masqué** ;
  2. Il sera diffusé sous licence libre (open-source) pour une durée indéfinie ;
  3. En cas d'exercice ultérieur de mon droit de retrait, l'extrait sera retiré des versions futures du dépôt officiel du projet, mais le retrait ne pourra techniquement pas rappeler ni supprimer les copies déjà téléchargées ou republiées par des tiers.

Signature du / de la participant(e) :
