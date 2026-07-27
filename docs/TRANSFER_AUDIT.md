# Audit des transferts inter-connexions

## Correction v0.5

`Déplacer vers…` utilise maintenant le même sélecteur de destination multi-connexions que `Télécharger vers…`.

Pour une source HTTP, les destinations sont :
- stockage local ;
- une connexion FTP ;
- une autre connexion HTTP.

Le déplacement est réalisé comme une copie vers la destination suivie de la suppression de la source, uniquement après réussite du transfert.

## Points vérifiés

- destination choisie une seule fois pour un déplacement ;
- évitement du déplacement d'une entrée HTTP vers elle-même ;
- suppression de la source seulement après transfert réussi ;
- nettoyage des fichiers temporaires dans les transferts distants ;
- conservation des transferts HTTP -> FTP et HTTP -> HTTP ;
- compatibilité avec les anciennes actions de téléchargement.

## Point restant à harmoniser

Les écrans FTP et local ont encore des parcours de transfert historiquement spécifiques. La prochaine étape est de les faire passer par le même `TransferDestinationPicker`/service commun afin d'obtenir une symétrie complète dans tous les sens.


## v0.6 — Unified cross-connection transfers

Corrections:
- The universal clipboard now supports recursive directory transfers between Local, FTP and HTTP.
- Copy and Move use the same transfer pipeline regardless of source/destination type.
- A Move deletes the source only after the complete destination transfer succeeds.
- Temporary files used for remote-to-remote transfers are cleaned up in `finally`.
- The clipboard is not cleared when a cut/paste operation has errors.
- FTP/HTTP/local sources can now be used interchangeably for file and directory transfers.
