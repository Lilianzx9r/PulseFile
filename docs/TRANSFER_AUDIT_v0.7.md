# PulseFile v0.7 — Audit des transferts

## Correction apportée

L'action « Télécharger vers… » de l'explorateur FTP était encore limitée au disque local, contrairement à l'explorateur HTTP.

Elle accepte désormais :

- FTP → disque local
- FTP → FTP (y compris une autre connexion)
- FTP → HTTP

Le transfert FTP → FTP passe par un fichier temporaire local, puis est envoyé vers la destination. Les fichiers temporaires sont supprimés dans un bloc `finally`.

## Points vérifiés

- la destination est choisie avant le transfert ;
- les connexions FTP et HTTP sont chargées depuis les connexions configurées ;
- le transfert FTP → HTTP utilise `CrossConnectionTransferService.ftpToHttp` ;
- le transfert FTP → FTP utilise un fichier temporaire ;
- la destination locale conserve le comportement de téléchargement existant ;
- les erreurs ferment la boîte de progression et affichent un message.

## Incohérences restantes à traiter

Le presse-papiers universel permet déjà les copies/déplacements entre Local, FTP et HTTP, mais l'interface locale n'utilise pas encore partout un sélecteur de destination explicite pour « Copier vers… » / « Déplacer vers… ». La prochaine étape est d'unifier cette UX avec le sélecteur multi-connexions utilisé par les explorateurs distants.
