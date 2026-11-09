# OrgWatch — surveillance des limites Salesforce

**OrgWatch** est une application Salesforce qui surveille les **limites de l'org** (`OrgLimits` : stockage de données et de fichiers, appels API, emails, Apex asynchrone, événements plateforme, Einstein…). Elle fournit :

- un historique graphique de la consommation de chaque limite, ainsi que l'état de toutes les limites à une date donnée ;
- des alertes email quotidiennes, avec des seuils définis par chaque utilisateur ;
- une rétention et une purge automatiques des données collectées ;
- une gestion des accès intégrée (onglet Admin).

Tout tient dans un seul onglet Lightning (`OrgWatch`), qui affiche le composant LWC `orgWatchMonitoring`. L'interface est disponible en **français et en anglais**, en **thème clair ou sombre**.

- **Aucun objet de données custom.** L'historique est stocké sous forme de fichiers CSV dans une bibliothèque de fichiers Salesforce.
- **Aucun appel externe.** Aucune donnée ne sort de l'org.

Version du code : **1.0.6**, sans namespace, API **64.0**.

---

## Sommaire

1. [Fonctionnement](#fonctionnement)
2. [Les onglets](#les-onglets)
3. [Contenu du dépôt](#contenu-du-dépôt)
4. [Installation](#installation)
5. [Jobs planifiés](#jobs-planifiés)
6. [Désinstallation](#désinstallation)
7. [Tests](#tests)
8. [Construire un package](#construire-un-package)
9. [Points d'attention](#points-dattention)

---

## Fonctionnement

```
 Job planifié "OrgWatchExport_*"          Bibliothèque de fichiers           Onglet OrgWatch (LWC)
 OrgWatchExporterScheduler      ──CSV──▶  "OrgWatch Reporting"    ◀──lit──  orgWatchMonitoring
 (OrgLimits.getMap())                     (ContentWorkspace)                + OrgWatchController
                                            │
                                            ├─ OrgWatch_Export_AAAA-MM-JJ_HH-mm   (1 fichier par export)
                                            └─ OrgWatchUserPreferences.csv          (préférences de tous les utilisateurs)
                                                         │
 Job "OrgWatchAlert_Daily_*"  ◀──lit seuils + 24h──────────┘──▶ email récapitulatif à chaque utilisateur
 Job "OrgWatchPurge_Daily_*"  ──supprime les exports plus anciens que N jours
```

1. Un **job d'export** lit `OrgLimits.getMap()` et écrit un fichier CSV horodaté dans la bibliothèque **« OrgWatch Reporting »**.
2. L'onglet **Monitoring** relit ces fichiers pour construire les courbes de consommation.
3. Les préférences des utilisateurs (métriques masquées, seuils d'alerte, mode d'envoi, langue) sont stockées dans un fichier unique, `OrgWatchUserPreferences.csv`, dans la même bibliothèque.
4. Un **job d'alerte quotidien** compare les exports des dernières 24 h aux seuils de chaque utilisateur et lui envoie un email récapitulatif.
5. Un **job de purge** (facultatif) supprime les exports plus anciens que la rétention choisie.

Les fichiers consomment du **stockage de fichiers**, pas du stockage de données. Seul réglage global : le custom setting hiérarchique `OrgWatch_Settings__c.Alert_Send_Time__c`, qui fixe l'heure d'envoi des alertes (`15:00` par défaut).

### Formats de fichiers

| Fichier | Contenu |
|---|---|
| `OrgWatch_Export_AAAA-MM-JJ_HH-mm` (`.csv`, UTF-8 avec BOM, séparateur `;`) | `Catégorie;Nom de la Limite;Valeur Actuelle;Maximum;Consommation (%)`, une ligne par limite |
| `OrgWatchUserPreferences.csv` (un seul fichier, versionné) | `UserId;HiddenMetrics;MetricThresholds;EmailMode;Language;LastModified`, une ligne par utilisateur |

---

## Les onglets

| Onglet | Visible par | Rôle |
|---|---|---|
| **Monitoring** | tous | Courbe de consommation d'une métrique comparée à sa limite. Cliquer sur un point affiche l'état de toutes les limites à cet instant. Les métriques sont regroupées par catégorie et peuvent être masquées (roue crantée, préférence personnelle) |
| **Planification** | admin | Fréquence d'export : toutes les 15 min, toutes les 30 min, toutes les heures, ou quotidien à HH:MM |
| **Rétention & Purge** | admin | Liste des exports et volume occupé, purge manuelle (fichiers plus anciens que X jours), purge automatique quotidienne |
| **Alertes** | tous | Seuil par métrique ; envoi du récapitulatif uniquement en cas de dépassement (par défaut) ou tous les jours |
| **Admin** | admin | Check-list d'installation, **Initialiser OrgWatch**, gestion des accès utilisateurs, heure d'envoi des alertes, désactivation des alertes d'un utilisateur, préparation de la désinstallation, suppression des données |

Code couleur de consommation : **OK** sous 75 %, **Attention** de 75 à 89 %, **Critique** à partir de 90 %.

Toutes les actions réservées aux admins sont **contrôlées côté serveur** (`OrgWatchController.assertOrgWatchAdmin()` / `assertOrgWatchAccess()`). Masquer un onglet dans le LWC ne sert qu'à l'affichage.

---

## Contenu du dépôt

```
force-app/main/default/
├── classes/            20 classes Apex (11 + 9 classes de test)
├── customPermissions/  OrgWatch_Admin_Access
├── lwc/                orgWatchMonitoring
├── objects/            OrgWatch_Settings__c (custom setting hiérarchique)
├── permissionsets/     OrgWatch_User, OrgWatch_Admin
├── staticresources/    org_watch_logo, org_watch_logo_dark, chartjs
└── tabs/               OrgWatch
manifest/package.xml    liste complète des métadonnées
```

| Élément | Rôle |
|---|---|
| `OrgWatch` (Custom Tab) | Onglet Lightning qui affiche le LWC |
| `orgWatchMonitoring` (LWC) | Toute l'interface (5 onglets) |
| `OrgWatchController` | Lecture de l'historique et des snapshots, préférences utilisateur, contrôle des accès, nom de la bibliothèque |
| `OrgWatchExporter` + `OrgWatchExporterScheduler` | Construction du CSV des limites et écriture dans la bibliothèque |
| `OrgWatchScheduleController` | Création et suppression des jobs d'export |
| `OrgWatchAlertController` + `OrgWatchAlertScheduler` | Préférences d'alerte et envoi du récapitulatif quotidien |
| `OrgWatchPurgeController` + `OrgWatchPurgeScheduler` | Purge manuelle et automatique des exports |
| `OrgWatchAdminController` | Octroi et retrait des accès (permission sets, adhésion à la bibliothèque, email de notification) |
| `OrgWatchSetupController` | Initialisation, check-list, préparation de la désinstallation, nettoyage des données |
| `OrgWatchEmailBranding` | Gabarit HTML commun des emails (logo inliné en base64, couleurs, pied de page) |
| `OrgWatch_Settings__c` | Custom setting : heure d'envoi des alertes (`Alert_Send_Time__c`) |
| `OrgWatch_User` (Permission Set) | Accès de base : onglet et classes Apex des 4 onglets principaux. Les actions d'administration restent refusées côté serveur sans `OrgWatch_Admin` |
| `OrgWatch_Admin` (Permission Set) | Accès **additionnel** : onglets d'administration. À assigner **en plus** de `OrgWatch_User` |
| `OrgWatch_Admin_Access` (Custom Permission) | Portée par `OrgWatch_Admin`. Le code contrôle l'attribution du permission set, pas cette custom permission |
| `org_watch_logo`, `org_watch_logo_dark` | Logos (thème clair et sombre, emails) |
| `chartjs` | [Chart.js](https://www.chartjs.org) **v3.9.1**, bibliothèque tierce sous licence MIT |

---

## Installation

### 1. Déployer

```bash
sf project deploy start --manifest manifest/package.xml --target-org <alias> --test-level RunSpecifiedTests \
  --tests OrgWatchAdminControllerTest --tests OrgWatchAlertControllerTest --tests OrgWatchAlertSchedulerTest \
  --tests OrgWatchControllerTest --tests OrgWatchExporterSchedulerTest --tests OrgWatchExporterTest \
  --tests OrgWatchPurgeControllerTest --tests OrgWatchScheduleControllerTest --tests OrgWatchSetupControllerTest
```

### 2. Initialiser (obligatoire, une seule fois)

Une bibliothèque de fichiers n'est pas une métadonnée déployable, et un unlocked package n'exécute aucun script à l'installation. L'initialisation se fait donc depuis l'application :

1. S'assigner les permission sets **`OrgWatch_User` + `OrgWatch_Admin`**.
2. Ouvrir l'onglet **OrgWatch**, puis l'onglet **Admin**, et cliquer sur **Initialiser OrgWatch**. Cette action :
   - crée la bibliothèque **« OrgWatch Reporting »**, avec le créateur comme membre ;
   - planifie un **export horaire** si aucun export n'existe encore.
3. Vérifier la check-list : bibliothèque présente, `chartjs` présent, jobs planifiés, nombre d'exports.

L'action est idempotente : on peut la relancer sans risque, par exemple après une mise à jour.

### 3. Donner l'accès aux utilisateurs

Toujours **depuis l'onglet Admin d'OrgWatch**, jamais directement dans Setup. L'onglet Admin :

- assigne le permission set ;
- **ajoute l'utilisateur comme membre de la bibliothèque**, au palier le moins privilégié disponible (Viewer, sinon Author, sinon Admin) ;
- envoie un email de notification à l'utilisateur.

Un permission set assigné dans Setup ne déclenche rien de tout cela, car `PermissionSetAssignment` ne supporte ni trigger ni CDC. L'utilisateur verrait alors l'onglet, mais **aucune donnée**.

---

## Jobs planifiés

Tous les jobs portent un nom préfixé par `OrgWatch` (Setup > Tâches planifiées).

| Nom du job | Classe | Création | Par défaut |
|---|---|---|---|
| `OrgWatchExport_hourly`, `OrgWatchExport_daily_HHhMM`, `OrgWatchExport_15min_00…45`, `OrgWatchExport_30min_00/30` | `OrgWatchExporterScheduler` | Initialisation, onglet Planification | horaire |
| `OrgWatchAlert_Daily_HHhMM` | `OrgWatchAlertScheduler` | Automatique dès qu'au moins un utilisateur a un seuil ; supprimé quand plus personne n'en a | 15:00 |
| `OrgWatchPurge_Daily_HHhMM_NNj` | `OrgWatchPurgeScheduler` | Onglet Rétention & Purge | 03:00, rétention 90 jours |

Les jobs d'export et de purge **lèvent volontairement une exception** en cas d'échec : l'erreur est visible dans Setup > Tâches Apex et déclenche l'email d'erreur Apex. Un échec ne déplanifie pas le job.

Salesforce n'accepte pas de liste de minutes dans une expression cron passée à `System.schedule`. Les fréquences « 15 min » et « 30 min » sont donc réalisées par 4 ou 2 jobs horaires décalés.

---

## Désinstallation

L'ordre compte :

1. Onglet Admin > **Préparer la désinstallation** : arrête tous les jobs `OrgWatch*`. Sans cette étape, la plateforme refuse de supprimer des classes encore référencées par un job planifié.
2. *(Facultatif)* Onglet Admin > **Supprimer toutes les données OrgWatch** : suppression **définitive** des CSV (corbeille vidée) et, en option, de la bibliothèque. Les fichiers et la bibliothèque sont des données de l'org : ils **survivent à la désinstallation** et continuent d'occuper du stockage.
3. Désinstaller le package, ou supprimer les métadonnées.

---

## Tests

```bash
sf apex run test --target-org <alias> --result-format human --wait 10 \
  --class-names OrgWatchAdminControllerTest --class-names OrgWatchAlertControllerTest \
  --class-names OrgWatchAlertSchedulerTest --class-names OrgWatchControllerTest \
  --class-names OrgWatchExporterSchedulerTest --class-names OrgWatchExporterTest \
  --class-names OrgWatchPurgeControllerTest --class-names OrgWatchScheduleControllerTest \
  --class-names OrgWatchSetupControllerTest
```

En contexte de test, toutes les classes utilisent une bibliothèque distincte, **« OrgWatch Reporting TEST »**. Les objets `Content*` ne sont pas toujours annulés par le rollback des tests, et les tests écraseraient sinon les vraies préférences des utilisateurs.

---

## Construire un package

Le code est conçu pour être distribué en **unlocked package sans namespace**. Pour créer le package depuis ce dépôt, avec un Dev Hub :

```bash
sf package create --name OrgWatch --package-type Unlocked --path force-app --no-namespace --target-dev-hub <devhub>
sf package version create --package OrgWatch --installation-key-bypass --code-coverage --wait 30 --target-dev-hub <devhub>
```

`sf package create` ajoute automatiquement le package et son alias dans `sfdx-project.json`.

---

## Points d'attention

- **La visibilité d'une bibliothèque dépend uniquement de l'appartenance.** Ni les permissions de contenu, ni `without sharing`, ni `AccessLevel.SYSTEM_MODE` ne la contournent. Si « Initialiser » échoue en `DUPLICATE_VALUE`, c'est que la bibliothèque existe déjà sans que l'appelant en soit membre. L'outil tente alors de la récupérer via `ContentFolderLink`. Sinon : Fichiers > Bibliothèques > « OrgWatch Reporting » > Gérer les membres.
- **Profondeur d'historique** : le graphe lit au maximum les **1 000 exports les plus récents** (`HISTORY_FILE_LIMIT`, plafond de heap de 6 Mo). Avec un export horaire, cela représente environ **41 jours** affichés, même si la rétention est de 90 jours.
- **Nom de la bibliothèque dupliqué** : la constante `LIBRARY_NAME` est encore déclarée dans `OrgWatchController`, `OrgWatchExporter`, `OrgWatchPurgeController` et `OrgWatchAdminController`. Elle est à consolider sur `OrgWatchController.getLibraryName()`.
- **Libellés des métriques dupliqués** : `METRICS_CONFIG` (LWC) et `METRIC_LABELS` (`OrgWatchAlertScheduler`) doivent rester alignés.
- **Préférences dans un fichier CSV unique**, partagé par tous les utilisateurs : chaque sauvegarde crée une nouvelle version de `OrgWatchUserPreferences.csv`.
