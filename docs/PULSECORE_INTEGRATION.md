# Intégration PulseCore dans PulseFile

Cette version ajoute `pulse_core` comme dépendance locale :

```yaml
pulse_core:
  path: ../PulseCore
```

Organisation recommandée :

```text
Pulse/
├── PulseCore/
└── PulseFile/
```

L'adaptateur `lib/services/http_share_adapter.dart` implémente `PulseShare`
en déléguant les opérations actuellement disponibles à `HttpService`.

## Opérations actuellement raccordées

- list
- read
- openRead
- write
- writeStream
- delete
- createDirectory
- rename
- move

## Opérations volontairement non activées

`stat`, `copy`, `removeDirectory`, `search` et `checksum` restent désactivées
tant que le serveur PHP n'expose pas un contrat correspondant. Elles lèvent
une `PulseShareException` explicite plutôt que de simuler silencieusement un
comportement différent.

## Étape suivante

Ajouter côté serveur PHP :

- capabilities
- stat
- copy
- removeDirectory
- search
- checksum

puis activer les capacités correspondantes dans `HttpShareAdapter`.


## Validation corrections

- Le test Flutter générique `MyApp` a été remplacé par un test de démarrage de `PulseFileApp`.
- `pulse_core` n'est déclaré qu'une seule fois, dans `dependencies`.
- `cross_file` est déclaré directement comme dépendance de l'application.


## Version 0.3 — opérations HTTP complétées

`HttpShareAdapter` expose désormais également :

- `stat`
- `copy`
- `removeDirectory`
- `search`
- `checksum`

Le serveur PHP doit fournir les actions correspondantes.

## Transferts entre connexions

`CrossConnectionTransferService` fournit les premiers transferts inter-connexions :

- HTTP → FTP
- FTP → HTTP

Le transfert utilise un fichier temporaire local et peut être configuré en mode copie ou déplacement (`deleteSource: true`).
