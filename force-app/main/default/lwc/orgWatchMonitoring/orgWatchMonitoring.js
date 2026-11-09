import { LightningElement, wire, track } from 'lwc';
import CURRENT_USER_ID from '@salesforce/user/Id';
import { refreshApex } from '@salesforce/apex';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import chartjs from '@salesforce/resourceUrl/chartjs';
import ORGWATCH_LOGO from '@salesforce/resourceUrl/org_watch_logo';
import ORGWATCH_LOGO_DARK from '@salesforce/resourceUrl/org_watch_logo_dark';
import getLimitsHistory from '@salesforce/apex/OrgWatchController.getLimitsHistory';
import getSnapshotAtTime from '@salesforce/apex/OrgWatchController.getSnapshotAtTime';
import getUserPreferences from '@salesforce/apex/OrgWatchController.getUserPreferences';
import saveUserPreferences from '@salesforce/apex/OrgWatchController.saveUserPreferences';
import getIsAdminUser from '@salesforce/apex/OrgWatchController.isAdminUser';
import getHasOrgWatchAccess from '@salesforce/apex/OrgWatchController.hasOrgWatchAccessForCurrentUser';
import getMyAccessState from '@salesforce/apex/OrgWatchController.getMyAccessState';
import saveLanguagePreference from '@salesforce/apex/OrgWatchController.saveLanguagePreference';
import getAdminDirectory from '@salesforce/apex/OrgWatchController.getAdminDirectory';

import getActiveSchedules from '@salesforce/apex/OrgWatchScheduleController.getActiveSchedules';
import createSchedule from '@salesforce/apex/OrgWatchScheduleController.createSchedule';
import deleteSchedule from '@salesforce/apex/OrgWatchScheduleController.deleteSchedule';

import getDataFilesInfo from '@salesforce/apex/OrgWatchPurgeController.getDataFilesInfo';
import purgeFilesOlderThan from '@salesforce/apex/OrgWatchPurgeController.purgeFilesOlderThan';
import getActivePurgeSchedule from '@salesforce/apex/OrgWatchPurgeController.getActivePurgeSchedule';
import createPurgeSchedule from '@salesforce/apex/OrgWatchPurgeController.createPurgeSchedule';
import deletePurgeSchedule from '@salesforce/apex/OrgWatchPurgeController.deletePurgeSchedule';

import getAlertPreferences from '@salesforce/apex/OrgWatchAlertController.getAlertPreferences';
import saveAlertPreferences from '@salesforce/apex/OrgWatchAlertController.saveAlertPreferences';
import disableAllAlerts from '@salesforce/apex/OrgWatchAlertController.disableAllAlerts';

import getUserAccessOverview from '@salesforce/apex/OrgWatchAdminController.getUserAccessOverview';
import searchAdminUsers from '@salesforce/apex/OrgWatchAdminController.searchUsers';
import setPermissionSetAssignment from '@salesforce/apex/OrgWatchAdminController.setPermissionSetAssignment';
import disableUserAlerts from '@salesforce/apex/OrgWatchAdminController.disableUserAlerts';
import setAlertScheduleTime from '@salesforce/apex/OrgWatchAdminController.setAlertScheduleTime';

import getSetupStatus from '@salesforce/apex/OrgWatchSetupController.getSetupStatus';
import runOrgWatchSetup from '@salesforce/apex/OrgWatchSetupController.runSetup';
import ensureDefaultExportSchedule from '@salesforce/apex/OrgWatchSetupController.ensureDefaultExportSchedule';
import prepareUninstall from '@salesforce/apex/OrgWatchSetupController.prepareUninstall';
import deleteAllOrgWatchData from '@salesforce/apex/OrgWatchSetupController.deleteAllOrgWatchData';

const THEME_STORAGE_KEY = 'orgWatchTheme';
const LANGUAGE_STORAGE_KEY = 'orgWatchLanguage';

// Metrics configuration: friendly labels/descriptions/categories per language.
const METRICS_CONFIG = {
    'DataStorageMB': { fr: { label: 'Stockage de Données', description: 'Espace utilisé pour stocker les enregistrements Salesforce', category: 'Stockage' }, en: { label: 'Data Storage', description: 'Space used to store Salesforce records', category: 'Storage' } },
    'FileStorageMB': { fr: { label: 'Stockage de Fichiers', description: 'Espace utilisé pour les fichiers et pièces jointes', category: 'Stockage' }, en: { label: 'File Storage', description: 'Space used for files and attachments', category: 'Storage' } },
    'SingleEmail': { fr: { label: 'Emails Unitaires', description: 'Nombre d\'emails individuels envoyés', category: 'Communication' }, en: { label: 'Single Emails', description: 'Number of individual emails sent', category: 'Communication' } },
    'MassEmail': { fr: { label: 'Emails en Masse', description: 'Emails envoyés via des campagnes marketing', category: 'Communication' }, en: { label: 'Mass Emails', description: 'Emails sent via marketing campaigns', category: 'Communication' } },
    'DailyApiRequests': { fr: { label: 'Appels API Quotidiens', description: 'Requêtes API par jour', category: 'API & Intégrations' }, en: { label: 'Daily API Calls', description: 'API requests per day', category: 'API & Integrations' } },
    'DailyBulkApiRequests': { fr: { label: 'API Bulk Quotidienne', description: 'Requêtes API Bulk', category: 'API & Intégrations' }, en: { label: 'Daily Bulk API', description: 'Bulk API requests', category: 'API & Integrations' } },
    'DailyDurableStreamingApiEvents': { fr: { label: 'Événements Streaming', description: 'Événements temps réel via Streaming API', category: 'API & Intégrations' }, en: { label: 'Streaming Events', description: 'Real-time events via Streaming API', category: 'API & Integrations' } },
    'DailyStreamingApiEvents': { fr: { label: 'Événements Streaming Standard', description: 'Flux d\'événements temps réel', category: 'API & Intégrations' }, en: { label: 'Standard Streaming Events', description: 'Real-time event stream', category: 'API & Integrations' } },
    'DurableStreamingApiConcurrentClients': { fr: { label: 'Clients Streaming Actifs', description: 'Connexions simultanées Streaming API', category: 'API & Intégrations' }, en: { label: 'Active Streaming Clients', description: 'Concurrent Streaming API connections', category: 'API & Integrations' } },
    'StreamingApiConcurrentClients': { fr: { label: 'Clients Streaming Standard', description: 'Connexions streaming standard', category: 'API & Intégrations' }, en: { label: 'Standard Streaming Clients', description: 'Standard streaming connections', category: 'API & Integrations' } },
    'DailyAsyncApexExecutions': { fr: { label: 'Exécutions Apex Asynchrones', description: 'Jobs Apex en arrière-plan', category: 'Développement' }, en: { label: 'Async Apex Executions', description: 'Background Apex jobs', category: 'Development' } },
    'DailyWorkflowEmails': { fr: { label: 'Emails Automatiques', description: 'Emails envoyés par workflows', category: 'Automatisation' }, en: { label: 'Automated Emails', description: 'Emails sent by workflows', category: 'Automation' } },
    'HourlyPublishedPlatformEvents': { fr: { label: 'Événements Plateforme/Heure', description: 'Platform Events publiés', category: 'Événements' }, en: { label: 'Platform Events/Hour', description: 'Platform Events published', category: 'Events' } },
    'HourlyPublishedStandardVolumePlatformEvents': { fr: { label: 'Événements Standard/Heure', description: 'Platform Events standard', category: 'Événements' }, en: { label: 'Standard Events/Hour', description: 'Standard Platform Events', category: 'Events' } },
    'PermissionSets': { fr: { label: 'Ensembles de Permissions', description: 'Ensembles de permissions créés', category: 'Sécurité' }, en: { label: 'Permission Sets', description: 'Permission sets created', category: 'Security' } },
    'DailyGenericStreamingApiEvents': { fr: { label: 'Événements Streaming Génériques', description: 'Événements streaming personnalisés', category: 'API & Intégrations' }, en: { label: 'Generic Streaming Events', description: 'Custom streaming events', category: 'API & Integrations' } },
    'ConcurrentAsyncGetReportInstances': { fr: { label: 'Rapports Asynchrones Actifs', description: 'Génération simultanée de rapports', category: 'Rapports' }, en: { label: 'Active Async Reports', description: 'Concurrent report generation', category: 'Reports' } },
    'ConcurrentEinsteinDataInsightsStoryCreation': { fr: { label: 'Création Stories Einstein', description: 'Analyses Einstein simultanées', category: 'Analytics' }, en: { label: 'Einstein Stories Creation', description: 'Concurrent Einstein analyses', category: 'Analytics' } },
    'ConcurrentEinsteinDiscoveryStoryCreation': { fr: { label: 'Discovery Einstein Actif', description: 'Analyses prédictives Einstein', category: 'Analytics' }, en: { label: 'Active Einstein Discovery', description: 'Predictive Einstein analyses', category: 'Analytics' } },
    'DailyEinsteinDiscoveryPredictAPICalls': { fr: { label: 'Prédictions Einstein/Jour', description: 'Appels API prédictions Einstein', category: 'Analytics' }, en: { label: 'Einstein Predictions/Day', description: 'Einstein prediction API calls', category: 'Analytics' } },
    'MonthlyEinsteinDiscoveryStoryCreation': { fr: { label: 'Stories Einstein/Mois', description: 'Stories Einstein mensuelles', category: 'Analytics' }, en: { label: 'Einstein Stories/Month', description: 'Monthly Einstein stories', category: 'Analytics' } },
    'ScheduledFlowRunLimit': { fr: { label: 'Flows Planifiés', description: 'Flows automatisés exécutés quotidiennement', category: 'Automatisation' }, en: { label: 'Scheduled Flows', description: 'Automated flows run daily', category: 'Automation' } },
    'DailyBulkV2QueryJobs': { fr: { label: 'Jobs Bulk Query V2', description: 'Requêtes extraction en masse v2', category: 'API & Intégrations' }, en: { label: 'Bulk Query V2 Jobs', description: 'Bulk extraction requests v2', category: 'API & Integrations' } },
    'DailyBulkV2QueryFileStorageMB': { fr: { label: 'Stockage Bulk Query V2', description: 'Espace stockage exports Bulk API', category: 'API & Intégrations' }, en: { label: 'Bulk Query V2 Storage', description: 'Bulk API export storage space', category: 'API & Integrations' } }
};

const TRANSLATIONS = {
    fr: {
        cardTitle: 'OrgWatch',
        settingsAlt: 'Paramètres',
        tabMonitoring: 'Monitoring',
        tabSchedule: 'Planification',
        tabPurge: 'Rétention & Purge',
        tabAlerts: 'Alertes',
        tabAdmin: 'Admin',
        genericMetric: 'Métrique Salesforce',
        otherCategory: 'Autre',

        monitoringSpinner: 'Chargement du monitoring des limites...',
        selectMetric: 'Sélectionnez une métrique',
        snapshotTitle: 'Snapshot des Limites',
        closeAlt: 'Fermer',
        chartLegendCurrent: 'Consommation Réelle',
        chartLegendMax: 'Limite Théorique',
        chartTooltipHint: 'Cliquez pour voir tous les détails',
        chartValueLabelPrefix: 'Conso : ',
        chartjsLoadError: 'Erreur lors du chargement de Chart.js : ',
        noDataError: 'Aucune donnée disponible. Veuillez vérifier que la bibliothèque "OrgWatch Reporting" existe et contient des fichiers CSV d\'export. Si c\'est la première utilisation de l\'outil, un administrateur doit d\'abord initialiser l\'application depuis l\'onglet Admin.',
        unitMegabytes: 'Mo',
        selectedMetricAlt: 'Métrique affichée sur le graphique',
        selectMetricOnChartAlt: 'Cliquer pour afficher cette métrique sur le graphique',
        accessDeniedTitle: 'Accès non autorisé',
        accessDeniedMessage: 'Vous n\'avez pas accès à OrgWatch. Un administrateur doit vous attribuer le Permission Set "OrgWatch - Utilisateur" (ou "OrgWatch - Admin") pour que vous puissiez consulter les limites de l\'org et configurer vos alertes.',
        apexError: 'Erreur Apex : ',
        snapshotLoadError: 'Erreur lors du chargement du snapshot : ',

        activeSchedulesTitle: 'Exports Planifiés Actifs',
        refresh: 'Rafraîchir',
        loading: 'Chargement...',
        colJobName: 'Nom du Job',
        colFrequency: 'Fréquence',
        colNextRun: 'Prochaine Exécution',
        colStatus: 'Statut',
        colActions: 'Actions',
        deleteAlt: 'Supprimer',
        noActiveSchedule: 'Aucun export planifié actif',
        maintenanceTitle: 'Installation & maintenance',
        maintenanceHint: 'À utiliser après l\'installation du package dans cette org, et avant de le désinstaller.',
        maintenanceLibraryLabel: 'Bibliothèque de fichiers',
        maintenanceChartLabel: 'Bibliothèque de graphiques (chartjs)',
        maintenanceJobsLabel: 'Jobs planifiés OrgWatch',
        maintenanceFilesLabel: 'Fichiers stockés',
        maintenancePresent: 'Présente',
        maintenanceMissing: 'Absente',
        maintenanceRunSetup: 'Initialiser OrgWatch',
        maintenanceRunSetupHint: 'Crée la bibliothèque de fichiers si elle n\'existe pas. Sans effet si tout est déjà en place.',
        maintenanceSetupDone: 'Initialisation terminée.',
        maintenanceSetupAlready: 'Tout était déjà en place, rien à créer.',
        maintenanceLibraryAdopted: 'La bibliothèque existait déjà sans aucun membre (donc invisible) : elle a été récupérée et vous en êtes désormais administrateur.',
        maintenanceScheduleActivated: 'Un export horaire a été activé pour commencer à collecter des données.',
        maintenanceScheduleAlready: 'Un export était déjà planifié, la fréquence en place a été conservée.',
        maintenanceScheduleError: 'La bibliothèque est prête, mais la planification automatique a échoué : configurez-la depuis l\'onglet Planification.',
        maintenanceUninstallTitle: 'Préparer la désinstallation',
        maintenanceUninstallHint: 'Arrête tous les jobs planifiés OrgWatch. Obligatoire avant de désinstaller le package : sinon la suppression des classes Apex encore planifiées est refusée et la désinstallation échoue.',
        maintenanceUninstallButton: 'Arrêter tous les jobs OrgWatch',
        maintenanceUninstallDone: 'Jobs arrêtés : ',
        maintenanceUninstallNone: 'Aucun job planifié à arrêter.',
        maintenancePurgeAllTitle: 'Supprimer les données résiduelles',
        maintenancePurgeAllHint: 'Les fichiers CSV et la bibliothèque sont des données de l\'org : ils survivent à la désinstallation du package et continuent d\'occuper du stockage. Cette action les supprime définitivement.',
        maintenancePurgeAllButton: 'Supprimer tous les fichiers OrgWatch',
        maintenancePurgeAllConfirm: 'Supprimer définitivement tous les fichiers OrgWatch de cette org ?',
        maintenancePurgeAllCheckbox: 'Je comprends que cette suppression est définitive',
        maintenancePurgeAllAlsoLibrary: 'Supprimer aussi la bibliothèque elle-même',
        maintenancePurgeAllDone: 'Fichiers supprimés : ',
        maintenancePurgeAllLibraryQueued: ' La bibliothèque va être supprimée dans quelques instants (rafraîchissez la check-list pour confirmer).',
        maintenanceRefresh: 'Rafraîchir',
        configureBelowHint: 'Configurez un nouveau planning ci-dessous',
        newScheduleTitle: 'Configurer un Nouveau Planning',
        attentionTitle: 'Attention',
        disableExistingHint: 'Vous devez d\'abord désactiver les plannings existants pour éviter les doublons.',
        exportFrequencyLegend: 'Fréquence d\'Export',
        chooseFrequency: 'Choisissez la fréquence',
        freq15min: 'Toutes les 15 minutes',
        freq30min: 'Toutes les 30 minutes',
        freqHourly: 'Toutes les heures',
        freqDaily: 'Quotidien',
        dailyTimeLabel: 'Heure d\'exécution quotidienne',
        selectTimePlaceholder: 'Sélectionnez l\'heure',
        scheduleSummaryTitle: 'Résumé de la Planification',
        activateSchedule: 'Activer la Planification',
        summaryIntro: 'Les exports seront créés ',
        summary15min: 'toutes les 15 minutes (à :00, :15, :30, :45 de chaque heure).',
        summary30min: 'toutes les 30 minutes (à :00 et :30 de chaque heure).',
        summaryHourly: 'toutes les heures (à chaque heure pile).',
        summaryDailyWithTime: 'tous les jours à {time}.',
        summaryDailyNoTime: 'tous les jours à l\'heure que vous sélectionnerez.',
        scheduleLoadError: 'Impossible de charger les plannings',
        scheduleCreated: 'Planning créé avec succès',
        scheduleDeleted: 'Planning supprimé avec succès',

        statFilesPresent: 'Fichiers de données présents',
        statTotalSize: 'Espace total occupé',
        statOldestFile: 'Fichier le plus ancien',
        purgeAutoTitle: 'Purge automatique',
        purgeAutoActivePrefix: 'Purge automatique ',
        purgeAutoDaily: 'quotidienne',
        purgeAutoActiveMid: ' active, à ',
        purgeAutoActiveSuffix: ' — supprime les fichiers de plus de ',
        purgeAutoDaysSuffix: ' jour(s).',
        nextRunLabel: 'Prochaine exécution : ',
        lastRunSuccessPrefix: 'Dernière exécution réussie le ',
        lastRunFailedPrefix: 'Échec de la dernière exécution (',
        lastRunFailedMid: ') : ',
        disableAutoPurgeAlt: 'Désactiver la purge automatique',
        deleteOlderThanLabel: 'Supprimer les fichiers de plus de (jours)',
        activateAutoPurge: 'Activer la purge automatique quotidienne',
        manualPurgeTitle: 'Purger les anciens fichiers (manuelle)',
        manualPurgeHint: 'Sélectionnez un seuil d\'ancienneté : tous les fichiers créés avant cette date seront supprimés définitivement.',
        sliderLabelPrefix: 'Supprimer les fichiers de plus de ',
        sliderLabelSuffix: ' jour(s)',
        preset7: '7 jours',
        preset15: '15 jours',
        preset30: '30 jours',
        preset60: '60 jours',
        preset90: '90 jours',
        preset180: '180 jours',
        preset365: '365 jours',
        filesOlderThan: 'Fichiers antérieurs au ',
        keptLegend: ' conservé(s) — ',
        purgeLegend: ' à supprimer — ',
        purgeSelected: 'Purger les fichiers sélectionnés',
        noDataFiles: 'Aucun fichier de données à gérer',
        dataFilesLoadError: 'Erreur lors du chargement des fichiers : ',
        filesDeletedPart: ' fichier(s) supprimé(s)',
        filesAlreadyDeletedPart: ' déjà supprimé(s) entretemps',
        partialPurgeTitle: 'Purge partielle',
        purgeFailedPart: ' échec(s) : ',
        noFilesToDelete: 'Aucun fichier à supprimer.',
        purgeFailedPrefix: 'La purge a échoué : ',
        autoPurgeActivated: 'Purge automatique quotidienne activée',
        autoPurgeDisabled: 'Purge automatique désactivée',
        byteUnits: ['octets', 'Ko', 'Mo', 'Go'],

        alertStatusLabel: 'État des alertes',
        alertsActive: 'Alertes actives',
        alertsInactive: 'Alertes désactivées',
        alertMailInfoPrefix: 'Le mail récapitulatif est envoyé chaque jour vers ',
        alertMailInfoSuffix: ' (à titre informatif)',
        noExportForAlertsWarning: 'Aucun export planifié actif : les alertes ont besoin de données régulières pour fonctionner. Configurez un export dans l\'onglet Planification.',
        globalThresholdTitle: 'Seuil global',
        globalThresholdHint: 'Pré-remplit rapidement toutes vos métriques affichées avec la même valeur — chaque métrique reste modifiable ou désactivable individuellement ci-dessous.',
        thresholdPercentLabel: 'Seuil (%)',
        applyToAllVisible: 'Appliquer à toutes les métriques affichées',
        perMetricThresholdsTitle: 'Seuils par métrique',
        disableAll: 'Tout désactiver',
        noAlertPlaceholder: 'Pas d\'alerte',
        noMetricsForAlerts: 'Aucune métrique disponible pour le moment — soit il n\'y a pas encore de données d\'export (voir l\'onglet Planification), soit tout est masqué dans les Paramètres de l\'onglet Monitoring.',
        sendTimeLabel: 'Heure d\'envoi prévue',
        sendTimeAdminOnly: 'modifiable par un administrateur OrgWatch',
        sendTimeWhoAlt: 'Qui peut modifier l\'heure d\'envoi ?',
        adminDirectoryTitle: 'Administrateurs OrgWatch',
        adminDirectoryIntro: 'Ces personnes peuvent modifier l\'heure d\'envoi du récapitulatif quotidien et gérer les accès à OrgWatch :',
        adminDirectoryEmpty: 'Aucun administrateur OrgWatch n\'est désigné dans cette org : personne ne peut donc modifier l\'heure d\'envoi ni gérer les accès pour l\'instant.',
        adminDirectoryPermissionSetPrefix: 'Pour devenir administrateur OrgWatch, il faut se voir attribuer le Permission Set ',
        adminDirectoryPermissionSetSuffix: '(à assigner par un administrateur Salesforce depuis Configuration > Ensembles d\'autorisations).',
        emailFrequencyTitle: 'Fréquence d\'envoi du mail',
        receiveDigestLabel: 'Recevoir le récapitulatif',
        emailModeAlways: 'Tous les jours',
        emailModeOnBreach: 'Uniquement si un seuil est dépassé',
        save: 'Enregistrer',
        alertPrefsSaved: 'Préférences d\'alertes enregistrées',
        allAlertsDisabled: 'Toutes les alertes ont été désactivées',


        selectMetricsTitle: 'Sélection des Métriques à Afficher',
        selectAll: 'Tout sélectionner',
        selectNone: 'Tout désélectionner',
        noMetricsAvailable: 'Aucune métrique disponible pour le moment — il n\'y a pas (ou plus) de données d\'export. Vérifiez qu\'un export a bien tourné dans l\'onglet Planification.',
        categoryAll: 'Tout',
        categoryNone: 'Aucun',
        metricsSelectedSuffix: ' métrique(s) sélectionnée(s)',
        apply: 'Appliquer',

        confirmPurgeTitle: 'Confirmer la purge',
        irreversibleWarning: 'Cette action est irréversible.',
        purgeConfirmTextPrefix: 'Vous vous apprêtez à supprimer ',
        purgeConfirmTextMid1: ' fichier(s), représentant ',
        purgeConfirmTextMid2: ', créés avant le ',
        confirmDeleteFilesLabel: 'Je confirme vouloir supprimer définitivement ces fichiers',
        cancel: 'Annuler',
        deletePermanently: 'Supprimer définitivement',

        confirmAutoPurgeTitle: 'Confirmer la purge automatique',
        autoPurgeWarning: 'Cette purge s\'exécutera tous les jours et supprimera définitivement les fichiers concernés.',
        autoPurgeConfirmTextPrefix: 'Tous les jours à ',
        autoPurgeConfirmTextMid: ', les fichiers créés il y a plus de ',
        autoPurgeConfirmTextSuffix: ' jour(s) seront supprimés automatiquement.',
        confirmActivateAutoPurgeLabel: 'Je confirme vouloir activer cette purge automatique',
        activate: 'Activer',

        disableAllAlertsTitle: 'Désactiver toutes les alertes ?',
        disableAllAlertsText: 'Tous vos seuils configurés seront supprimés. Vous ne recevrez plus le mail récapitulatif tant que vous n\'aurez pas reconfiguré au moins une alerte.',
        disableAllConfirmBtn: 'Désactiver tout',

        unsavedChangesTitle: 'Quitter sans enregistrer ?',
        unsavedChangesText: 'Vous avez des modifications non enregistrées dans l\'onglet Alertes. Si vous quittez maintenant, elles seront perdues.',
        stayOnTab: 'Rester sur cet onglet',
        leaveWithoutSaving: 'Quitter sans enregistrer',

        success: 'Succès',
        error: 'Erreur',
        prefsSaved: 'Vos préférences ont été enregistrées',
        prefsSaveFailedPrefix: 'Échec de la sauvegarde: ',
        prefsSaveFailedSuffix: '. Veuillez réessayer plus tard.',
        prefsSaveFailedGeneric: 'Échec de la sauvegarde de vos préférences. Veuillez réessayer plus tard.',

        chartLegendThreshold: 'Seuil d\'alerte',

        adminSearchPlaceholder: 'Rechercher un utilisateur par nom...',
        adminSearchButton: 'Rechercher',
        adminColName: 'Nom',
        adminColEmail: 'Email',
        adminColUserPS: 'OrgWatch - User',
        adminColAdminPS: 'OrgWatch - Admin',
        adminColAlerts: 'Alertes',
        adminColActions: 'Actions',
        adminAlertsYes: 'Oui',
        adminAlertsNo: 'Non',
        toggleActive: 'Actif',
        toggleInactive: 'Inactif',
        adminDisableAlertsBtn: 'Désactiver les alertes',
        adminNoUsers: 'Aucun utilisateur avec un accès OrgWatch pour le moment. Utilisez la recherche ci-dessus pour en ajouter un.',
        adminNoSearchResults: 'Aucun utilisateur trouvé.',
        adminLoadError: 'Impossible de charger la liste des utilisateurs',
        adminSearchError: 'Erreur lors de la recherche',
        adminPsUpdateError: 'Erreur lors de la mise à jour des droits',
        adminPsGranted: 'Accès accordé',
        adminPsRevoked: 'Accès retiré',
        selfAdminRevokedTitle: 'Vos droits ont changé',
        selfAdminRevoked: 'Vous venez de retirer votre propre accès Admin : les onglets d\'administration ne sont plus disponibles.',
        selfAccessRevoked: 'Vous venez de retirer votre propre accès à OrgWatch.',
        adminUserAlertsDisabled: 'Alertes désactivées',
        adminAlertScheduleTitle: 'Heure d\'envoi du mail d\'alertes',
        adminAlertScheduleHint: 'Heure à laquelle le mail récapitulatif quotidien est envoyé à tous les utilisateurs ayant des alertes configurées.',
        adminAlertSendTimeLabel: 'Heure d\'envoi',
        adminAlertSendTimeSaved: 'Heure d\'envoi enregistrée',
        adminAlertSendTimeError: 'Erreur lors de l\'enregistrement de l\'heure d\'envoi',

        revokeConfirmTitle: 'Retirer cet accès ?',
        revokeConfirmPrefix: 'Vous êtes sur le point de retirer l\'accès ',
        revokeConfirmToUser: ' à ',
        revokeConfirmAlsoAdmin: '. Comme "OrgWatch - Admin" ne fonctionne pas sans cet accès de base, il sera retiré en même temps.',
        revokeConfirmSuffix: '.',
        revokeConfirmButton: 'Retirer',

        disableUserAlertsTitle: 'Désactiver les alertes ?',
        disableUserAlertsTextPrefix: 'Les seuils configurés pour ',
        disableUserAlertsTextSuffix: ' seront supprimés. Cette personne ne recevra plus le mail récapitulatif tant qu\'un seuil n\'aura pas été reconfiguré.',
        notifyCheckboxPrefix: 'Notifier ',
        notifyCheckboxSuffix: ' par email de cette désactivation',

        dateLocale: 'fr-FR',
        numberLocale: 'fr-FR'
    },
    en: {
        cardTitle: 'OrgWatch',
        settingsAlt: 'Settings',
        tabMonitoring: 'Monitoring',
        tabSchedule: 'Scheduling',
        tabPurge: 'Retention & Purge',
        tabAlerts: 'Alerts',
        tabAdmin: 'Admin',
        genericMetric: 'Salesforce Metric',
        otherCategory: 'Other',

        monitoringSpinner: 'Loading limits monitoring...',
        selectMetric: 'Select a metric',
        snapshotTitle: 'Limits Snapshot',
        closeAlt: 'Close',
        chartLegendCurrent: 'Actual Usage',
        chartLegendMax: 'Theoretical Limit',
        chartTooltipHint: 'Click to see all details',
        chartValueLabelPrefix: 'Usage: ',
        chartjsLoadError: 'Error loading Chart.js: ',
        noDataError: 'No data available. Please check that the "OrgWatch Reporting" library exists and contains export CSV files. If this is the first time using the tool, an administrator must first initialize the application from the Admin tab.',
        unitMegabytes: 'MB',
        selectedMetricAlt: 'Metric shown on the chart',
        selectMetricOnChartAlt: 'Click to show this metric on the chart',
        accessDeniedTitle: 'Access denied',
        accessDeniedMessage: 'You do not have access to OrgWatch. An administrator must assign you the "OrgWatch - User" (or "OrgWatch - Admin") permission set so you can view the org limits and configure your alerts.',
        apexError: 'Apex error: ',
        snapshotLoadError: 'Error loading snapshot: ',

        activeSchedulesTitle: 'Active Scheduled Exports',
        refresh: 'Refresh',
        loading: 'Loading...',
        colJobName: 'Job Name',
        colFrequency: 'Frequency',
        colNextRun: 'Next Run',
        colStatus: 'Status',
        colActions: 'Actions',
        deleteAlt: 'Delete',
        noActiveSchedule: 'No active scheduled export',
        maintenanceTitle: 'Setup & maintenance',
        maintenanceHint: 'Use after installing the package in this org, and before uninstalling it.',
        maintenanceLibraryLabel: 'File library',
        maintenanceChartLabel: 'Charting library (chartjs)',
        maintenanceJobsLabel: 'OrgWatch scheduled jobs',
        maintenanceFilesLabel: 'Stored files',
        maintenancePresent: 'Present',
        maintenanceMissing: 'Missing',
        maintenanceRunSetup: 'Initialize OrgWatch',
        maintenanceRunSetupHint: 'Creates the file library if it does not exist. Does nothing if everything is already in place.',
        maintenanceSetupDone: 'Setup complete.',
        maintenanceSetupAlready: 'Everything was already in place, nothing to create.',
        maintenanceLibraryAdopted: 'The library already existed with no members (hence invisible): it has been recovered and you are now one of its administrators.',
        maintenanceScheduleActivated: 'An hourly export was activated to start collecting data.',
        maintenanceScheduleAlready: 'An export was already scheduled, the existing frequency was kept.',
        maintenanceScheduleError: 'The library is ready, but automatic scheduling failed: set it up from the Scheduling tab.',
        maintenanceUninstallTitle: 'Prepare uninstall',
        maintenanceUninstallHint: 'Stops every OrgWatch scheduled job. Required before uninstalling the package: otherwise deleting the still-scheduled Apex classes is refused and the uninstall fails.',
        maintenanceUninstallButton: 'Stop all OrgWatch jobs',
        maintenanceUninstallDone: 'Jobs stopped: ',
        maintenanceUninstallNone: 'No scheduled job to stop.',
        maintenancePurgeAllTitle: 'Delete leftover data',
        maintenancePurgeAllHint: 'The CSV files and the library are org data: they survive the package uninstall and keep using file storage. This action deletes them permanently.',
        maintenancePurgeAllButton: 'Delete all OrgWatch files',
        maintenancePurgeAllConfirm: 'Permanently delete every OrgWatch file in this org?',
        maintenancePurgeAllCheckbox: 'I understand this deletion is permanent',
        maintenancePurgeAllAlsoLibrary: 'Also delete the library itself',
        maintenancePurgeAllDone: 'Files deleted: ',
        maintenancePurgeAllLibraryQueued: ' The library will be deleted shortly (refresh the checklist to confirm).',
        maintenanceRefresh: 'Refresh',
        configureBelowHint: 'Set up a new schedule below',
        newScheduleTitle: 'Configure a New Schedule',
        attentionTitle: 'Attention',
        disableExistingHint: 'You must first disable existing schedules to avoid duplicates.',
        exportFrequencyLegend: 'Export Frequency',
        chooseFrequency: 'Choose a frequency',
        freq15min: 'Every 15 minutes',
        freq30min: 'Every 30 minutes',
        freqHourly: 'Every hour',
        freqDaily: 'Daily',
        dailyTimeLabel: 'Daily run time',
        selectTimePlaceholder: 'Select a time',
        scheduleSummaryTitle: 'Schedule Summary',
        activateSchedule: 'Activate Schedule',
        summaryIntro: 'Exports will be created ',
        summary15min: 'every 15 minutes (at :00, :15, :30, :45 of each hour).',
        summary30min: 'every 30 minutes (at :00 and :30 of each hour).',
        summaryHourly: 'every hour (on the hour).',
        summaryDailyWithTime: 'every day at {time}.',
        summaryDailyNoTime: 'every day at the time you select.',
        scheduleLoadError: 'Unable to load schedules',
        scheduleCreated: 'Schedule created successfully',
        scheduleDeleted: 'Schedule deleted successfully',

        statFilesPresent: 'Data files present',
        statTotalSize: 'Total space used',
        statOldestFile: 'Oldest file',
        purgeAutoTitle: 'Automatic purge',
        purgeAutoActivePrefix: 'Automatic ',
        purgeAutoDaily: 'daily',
        purgeAutoActiveMid: ' purge active, at ',
        purgeAutoActiveSuffix: ' — deletes files older than ',
        purgeAutoDaysSuffix: ' day(s).',
        nextRunLabel: 'Next run: ',
        lastRunSuccessPrefix: 'Last run succeeded on ',
        lastRunFailedPrefix: 'Last run failed (',
        lastRunFailedMid: '): ',
        disableAutoPurgeAlt: 'Disable automatic purge',
        deleteOlderThanLabel: 'Delete files older than (days)',
        activateAutoPurge: 'Enable daily automatic purge',
        manualPurgeTitle: 'Purge old files (manual)',
        manualPurgeHint: 'Choose an age threshold: every file created before that date will be permanently deleted.',
        sliderLabelPrefix: 'Delete files older than ',
        sliderLabelSuffix: ' day(s)',
        preset7: '7 days',
        preset15: '15 days',
        preset30: '30 days',
        preset60: '60 days',
        preset90: '90 days',
        preset180: '180 days',
        preset365: '365 days',
        filesOlderThan: 'Files older than ',
        keptLegend: ' kept — ',
        purgeLegend: ' to delete — ',
        purgeSelected: 'Purge selected files',
        noDataFiles: 'No data files to manage',
        dataFilesLoadError: 'Error loading files: ',
        filesDeletedPart: ' file(s) deleted',
        filesAlreadyDeletedPart: ' already deleted in the meantime',
        partialPurgeTitle: 'Partial purge',
        purgeFailedPart: ' failure(s): ',
        noFilesToDelete: 'No files to delete.',
        purgeFailedPrefix: 'Purge failed: ',
        autoPurgeActivated: 'Daily automatic purge enabled',
        autoPurgeDisabled: 'Automatic purge disabled',
        byteUnits: ['bytes', 'KB', 'MB', 'GB'],

        alertStatusLabel: 'Alert status',
        alertsActive: 'Alerts active',
        alertsInactive: 'Alerts disabled',
        alertMailInfoPrefix: 'The summary email is sent every day around ',
        alertMailInfoSuffix: ' (for information only)',
        noExportForAlertsWarning: 'No active scheduled export: alerts need regular data to work. Set up an export in the Scheduling tab.',
        globalThresholdTitle: 'Global threshold',
        globalThresholdHint: 'Quickly pre-fills all your visible metrics with the same value — each metric can still be adjusted or disabled individually below.',
        thresholdPercentLabel: 'Threshold (%)',
        applyToAllVisible: 'Apply to all visible metrics',
        perMetricThresholdsTitle: 'Per-metric thresholds',
        disableAll: 'Disable all',
        noAlertPlaceholder: 'No alert',
        noMetricsForAlerts: 'No metrics available yet — either there is no export data yet (see the Scheduling tab), or everything is hidden in the Monitoring tab\'s Settings.',
        sendTimeLabel: 'Scheduled send time',
        sendTimeAdminOnly: 'editable by an OrgWatch administrator',
        sendTimeWhoAlt: 'Who can change the send time?',
        adminDirectoryTitle: 'OrgWatch administrators',
        adminDirectoryIntro: 'These people can change the daily summary send time and manage access to OrgWatch:',
        adminDirectoryEmpty: 'No OrgWatch administrator is designated in this org, so nobody can change the send time or manage access at the moment.',
        adminDirectoryPermissionSetPrefix: 'To become an OrgWatch administrator, you need to be assigned the permission set ',
        adminDirectoryPermissionSetSuffix: '(assigned by a Salesforce administrator from Setup > Permission Sets).',
        emailFrequencyTitle: 'Email frequency',
        receiveDigestLabel: 'Receive the summary',
        emailModeAlways: 'Every day',
        emailModeOnBreach: 'Only when a threshold is exceeded',
        save: 'Save',
        alertPrefsSaved: 'Alert preferences saved',
        allAlertsDisabled: 'All alerts have been disabled',


        selectMetricsTitle: 'Select Metrics to Display',
        selectAll: 'Select all',
        selectNone: 'Deselect all',
        noMetricsAvailable: 'No metrics available yet — there is no (or no longer any) export data. Check that an export has run in the Scheduling tab.',
        categoryAll: 'All',
        categoryNone: 'None',
        metricsSelectedSuffix: ' metric(s) selected',
        apply: 'Apply',

        confirmPurgeTitle: 'Confirm purge',
        irreversibleWarning: 'This action is irreversible.',
        purgeConfirmTextPrefix: 'You are about to delete ',
        purgeConfirmTextMid1: ' file(s), representing ',
        purgeConfirmTextMid2: ', created before ',
        confirmDeleteFilesLabel: 'I confirm I want to permanently delete these files',
        cancel: 'Cancel',
        deletePermanently: 'Delete permanently',

        confirmAutoPurgeTitle: 'Confirm automatic purge',
        autoPurgeWarning: 'This purge will run every day and will permanently delete the files concerned.',
        autoPurgeConfirmTextPrefix: 'Every day at ',
        autoPurgeConfirmTextMid: ', files created more than ',
        autoPurgeConfirmTextSuffix: ' day(s) ago will be deleted automatically.',
        confirmActivateAutoPurgeLabel: 'I confirm I want to enable this automatic purge',
        activate: 'Enable',

        disableAllAlertsTitle: 'Disable all alerts?',
        disableAllAlertsText: 'All your configured thresholds will be removed. You will no longer receive the summary email until you reconfigure at least one alert.',
        disableAllConfirmBtn: 'Disable all',

        unsavedChangesTitle: 'Leave without saving?',
        unsavedChangesText: 'You have unsaved changes in the Alerts tab. If you leave now, they will be lost.',
        stayOnTab: 'Stay on this tab',
        leaveWithoutSaving: 'Leave without saving',

        success: 'Success',
        error: 'Error',
        prefsSaved: 'Your preferences have been saved',
        prefsSaveFailedPrefix: 'Save failed: ',
        prefsSaveFailedSuffix: '. Please try again later.',
        prefsSaveFailedGeneric: 'Failed to save your preferences. Please try again later.',

        chartLegendThreshold: 'Alert threshold',

        adminSearchPlaceholder: 'Search for a user by name...',
        adminSearchButton: 'Search',
        adminColName: 'Name',
        adminColEmail: 'Email',
        adminColUserPS: 'OrgWatch - User',
        adminColAdminPS: 'OrgWatch - Admin',
        adminColAlerts: 'Alerts',
        adminColActions: 'Actions',
        adminAlertsYes: 'Yes',
        adminAlertsNo: 'No',
        toggleActive: 'Active',
        toggleInactive: 'Inactive',
        adminDisableAlertsBtn: 'Disable alerts',
        adminNoUsers: 'No user has OrgWatch access yet. Use the search above to add one.',
        adminNoSearchResults: 'No user found.',
        adminLoadError: 'Unable to load the user list',
        adminSearchError: 'Search error',
        adminPsUpdateError: 'Error updating access rights',
        adminPsGranted: 'Access granted',
        adminPsRevoked: 'Access removed',
        selfAdminRevokedTitle: 'Your permissions changed',
        selfAdminRevoked: 'You just removed your own Admin access: the administration tabs are no longer available.',
        selfAccessRevoked: 'You just removed your own access to OrgWatch.',
        adminUserAlertsDisabled: 'Alerts disabled',
        adminAlertScheduleTitle: 'Alert email send time',
        adminAlertScheduleHint: 'Time at which the daily summary email is sent to every user with alerts configured.',
        adminAlertSendTimeLabel: 'Send time',
        adminAlertSendTimeSaved: 'Send time saved',
        adminAlertSendTimeError: 'Error saving the send time',

        revokeConfirmTitle: 'Remove this access?',
        revokeConfirmPrefix: 'You are about to remove ',
        revokeConfirmToUser: ' access for ',
        revokeConfirmAlsoAdmin: '. Since "OrgWatch - Admin" does not work without this base access, it will be removed at the same time.',
        revokeConfirmSuffix: '.',
        revokeConfirmButton: 'Remove',

        disableUserAlertsTitle: 'Disable alerts?',
        disableUserAlertsTextPrefix: 'The configured thresholds for ',
        disableUserAlertsTextSuffix: ' will be removed. This person will no longer receive the summary email until a threshold has been reconfigured.',
        notifyCheckboxPrefix: 'Notify ',
        notifyCheckboxSuffix: ' by email about this change',

        dateLocale: 'en-US',
        numberLocale: 'en-US'
    }
};

export default class OrgWatchMonitoring extends LightningElement {
    // Theme & language
    @track isDarkMode = false;
    @track currentLanguage = 'fr';

    // Tab management
    @track activeTab = 'monitoring';
    @track scheduleTabInitialized = false;
    @track isAdminUser = false;

    // Accès à OrgWatch tout court (l'un des deux Permission Sets). Faux par
    // défaut et tant que le contrôle serveur n'a pas répondu : on n'affiche
    // aucun onglet à quelqu'un dont on ne sait pas encore s'il a le droit.
    @track hasOrgWatchAccess = false;
    @track accessChecked = false;

    // Monitoring tab
    @track selectedLimit = 'SingleEmail';
    @track limitOptions = [];
    @track error;
    @track selectedSnapshot = null;
    @track snapshotMetrics = [];
    @track selectedPointIndex = null;
    @track showSettings = false;
    @track hiddenMetrics = new Set();
    hiddenMetricsSnapshot = new Set();
    @track showInitialSpinner = true;
    dataResolved = false;
    // Résultat du @wire getLimitsHistory, conservé pour refreshApex().
    wiredHistoryResult;
    chartReady = false;
    minDelayElapsed = false;

    chart;
    chartjsInitialized = false;
    chartThemeAppliedForDarkMode;
    allHistoryData;
    preferencesLoaded = false;

    // Schedule tab
    @track activeSchedules = [];
    @track loadingSchedules = false;
    @track selectedFrequency = '';
    @track selectedTime = '';
    @track scheduleSummary = '';

        // Purge tab
    @track dataFilesInfo = [];
    @track loadingDataFiles = false;
    @track dataFilesError;
    @track purgeAgeDays = 90;
    @track showPurgeConfirm = false;
    @track purgeConfirmed = false;
    purgeTabInitialized = false;

    // Purge automatique (planifiée)
    @track activePurgeSchedule = null;
    @track loadingPurgeSchedule = false;
    @track scheduledPurgeAgeDays = 90;
    @track scheduledPurgeTime = '03:00';
    @track showCreatePurgeScheduleConfirm = false;
    @track createPurgeScheduleConfirmed = false;

    // Alertes
    @track alertThresholds = {};
    @track alertEmailMode = 'OnlyOnBreach';
    @track hasActiveExportSchedule = true;
    @track loadingAlertPrefs = false;
    @track globalThresholdInput = 80;
    @track showDisableAllAlertsConfirm = false;
    @track showUnsavedAlertChangesConfirm = false;
    pendingTabValue = null;
    savedMetricThresholdsString = '';
    savedAlertEmailMode = 'OnlyOnBreach';
    alertTabInitialized = false;
    // Popup "qui peut modifier l'heure d'envoi ?" de l'onglet Alertes.
    @track showAdminDirectory = false;
    @track adminDirectory = null;
    @track loadingAdminDirectory = false;
    // Un export planifie cree/arrete ailleurs invalide l'avertissement de
    // l'onglet Alertes : cf. renderedCallback.
    alertsTabNeedsRefresh = false;

    // Admin
    @track adminUserRows = [];
    @track loadingAdminUsers = false;
    @track adminSearchTerm = '';
    @track searchingAdminUsers = false;
    @track adminSearchSuggestions = [];
    @track showAdminSearchDropdown = false;
    adminSearchDebounceTimer = null;
    adminSearchBlurTimer = null;
    spinnerDelayTimer = null;
    // Interrupteurs dont l'état visuel doit être restauré si la confirmation
    // est annulée (cf. handleTogglePS / handleAlertStatusToggleChange).
    revokeToggleElement = null;
    alertStatusToggleElement = null;

    // Installation / maintenance (onglet Admin)
    @track setupStatus = null;
    @track loadingSetupStatus = false;
    @track runningSetup = false;
    @track runningUninstallPrep = false;
    @track showDeleteAllDataConfirm = false;
    @track deleteAllDataConfirmed = false;
    @track deleteAllDataIncludeLibrary = false;
    @track deletingAllData = false;
    @track showRevokeConfirm = false;
    revokeTargetRow = null;
    revokePermissionSetName = null;
    revokeAlsoRemovesAdmin = false;
    @track showDisableUserAlertsConfirm = false;
    disableAlertsTargetRow = null;
    @track notifyUserOnDisable = true;
    adminTabInitialized = false;
    @track adminAlertSendTime = '15:00';
    // Heure d'envoi REELLEMENT enregistree. Distincte de
    // adminAlertSendTime, qui est le brouillon lie a la liste deroulante
    // de l'onglet Admin : sans cette separation, une valeur choisie mais
    // non sauvegardee s'afficherait ailleurs comme si elle etait active.
    @track savedAlertSendTime = '15:00';
    @track savingAlertSendTime = false;

    connectedCallback() {
        // Thème et langue sont de simples préférences locales : elles peuvent
        // être appliquées avant de savoir si l'utilisateur a accès, pour que
        // le message de refus s'affiche déjà dans le bon thème.
        this.loadThemePreference();
        this.loadLanguagePreference();

        // Aucun autre chargement avant la réponse du contrôle d'accès : sans
        // ça, un utilisateur sans Permission Set voyait les onglets s'afficher
        // (les appels de données échouant seulement une fois à l'intérieur).
        getHasOrgWatchAccess()
            .then(result => {
                this.hasOrgWatchAccess = result === true;
                this.accessChecked = true;

                if (this.hasOrgWatchAccess) {
                    this.initializeAuthorizedUser();
                }
            })
            .catch(error => {
                console.error('Error checking OrgWatch access:', error);
                this.hasOrgWatchAccess = false;
                this.accessChecked = true;
            });
    }

    initializeAuthorizedUser() {
        this.loadUserPreferences();

        // Chargé ici en plus du chargement paresseux existant (déclenché à
        // l'activation de l'onglet Alertes) pour que la ligne de seuil soit
        // disponible sur le graphique dès l'arrivée sur l'onglet Monitoring.
        this.loadAlertPreferences();

        getIsAdminUser()
            .then(result => {
                this.isAdminUser = result;
            })
            .catch(error => {
                console.error('Error checking admin permission:', error);
                this.isAdminUser = false;
            });

        // Durée minimale d'affichage du spinner : évite un flash imperceptible
        // quand la donnée Apex et Chart.js se chargent trop vite (cache).
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.spinnerDelayTimer = setTimeout(() => {
            this.spinnerDelayTimer = null;
            this.minDelayElapsed = true;
            this.updateSpinnerVisibility();
        }, 600);
    }

    get showAccessDenied() {
        return this.accessChecked && !this.hasOrgWatchAccess;
    }

    /**
     * La navigation Lightning démonte le composant sans recharger la page :
     * sans ce nettoyage, chaque visite laisse derrière elle une instance
     * Chart.js (et ses écouteurs sur le canvas) plus les timers en attente.
     */
    disconnectedCallback() {
        [this.spinnerDelayTimer, this.adminSearchDebounceTimer, this.adminSearchBlurTimer].forEach(timer => {
            if (timer) {
                clearTimeout(timer);
            }
        });
        this.spinnerDelayTimer = null;
        this.adminSearchDebounceTimer = null;
        this.adminSearchBlurTimer = null;

        if (this.chart) {
            this.chart.destroy();
            this.chart = null;
        }
    }

    renderedCallback() {
        this.template.host.classList.toggle('dark-theme', this.isDarkMode);

        if (this.chart && this.chartThemeAppliedForDarkMode !== this.isDarkMode) {
            this.chartThemeAppliedForDarkMode = this.isDarkMode;
            this.applyChartTheme();
        }

        // Initialize Chart.js only once, et seulement une fois l'accès
        // confirmé : avant ça le template ne rend rien, donc le canvas
        // n'existe pas encore et le drapeau "initialisé" serait posé pour
        // rien (le graphique ne serait jamais créé après l'autorisation).
        if (!this.chartjsInitialized && this.hasOrgWatchAccess) {
            this.chartjsInitialized = true;

            loadScript(this, chartjs)
                .then(() => {
                    const canvas = this.template.querySelector('canvas.linechart');
                    if (canvas) {
                        const ctx = canvas.getContext('2d');
                        this.initializeChart(ctx);
                    }
                    this.chartReady = true;
                    this.updateSpinnerVisibility();
                })
                .catch(err => {
                    this.error = this.labels.chartjsLoadError + err;
                    this.chartReady = true;
                    this.updateSpinnerVisibility();
                });
        }

        // Load schedules if on schedule tab and not yet initialized
        if (this.activeTab === 'schedule' && !this.scheduleTabInitialized) {
            this.scheduleTabInitialized = true;
            this.refreshSchedules();
        }

        if (this.activeTab === 'purge' && !this.purgeTabInitialized) {
            this.purgeTabInitialized = true;
            this.loadDataFilesInfo();
            this.loadPurgeSchedule();
        }

        if (this.activeTab === 'alerts' && !this.alertTabInitialized) {
            this.alertTabInitialized = true;
            this.loadAlertPreferences();
        } else if (this.activeTab === 'alerts' && !this.loadingAlertPrefs && this.alertsTabNeedsRefresh) {
            // L'avertissement « aucun export planifié » de cet onglet dépend
            // d'un état modifiable depuis l'onglet Planification : il doit
            // être réévalué à chaque retour ici, sinon il reste faux après
            // l'activation d'un export.
            this.alertsTabNeedsRefresh = false;
            this.loadAlertPreferences();
        }

        if (this.activeTab === 'admin' && !this.adminTabInitialized) {
            this.adminTabInitialized = true;
            this.loadAdminUsers();
            this.loadSetupStatus();
        }
    }

    // ========== THEME & LANGUAGE ==========

    get labels() {
        return TRANSLATIONS[this.currentLanguage];
    }

    get isFr() {
        return this.currentLanguage === 'fr';
    }

    get isEn() {
        return this.currentLanguage === 'en';
    }

    get frButtonClass() {
        return this.isFr ? 'active' : '';
    }

    get enButtonClass() {
        return this.isEn ? 'active' : '';
    }

    get logoUrl() {
        return this.isDarkMode ? ORGWATCH_LOGO_DARK : ORGWATCH_LOGO;
    }

    // ========== NAV BAR (onglets custom, alignés sur la même ligne que le logo) ==========

    get isMonitoringTabActive() {
        return this.activeTab === 'monitoring';
    }

    // Contrairement aux autres onglets (démontés/remontés sans risque via
    // template if:true, leur état vit dans des champs JS réactifs), l'onglet
    // Monitoring doit rester monté en permanence : son <canvas> est piloté
    // manuellement par Chart.js (lwc:dom="manual") et n'est initialisé
    // qu'une seule fois (chartjsInitialized). Le démonter le détruirait et
    // le graphique resterait vide au retour sur l'onglet. On le masque donc
    // en CSS plutôt que de le retirer du DOM.
    get monitoringTabWrapperClass() {
        return this.isMonitoringTabActive ? 'slds-is-relative' : 'slds-is-relative tab-panel-hidden';
    }

    // Planification et Purge pilotent des traitements qui s'appliquent à toute
    // l'org : ces deux onglets sont réservés aux admins OrgWatch. La condition
    // est répétée ici (et pas seulement sur les boutons de navigation) pour que
    // le contenu ne puisse pas s'afficher si activeTab est positionné
    // autrement. La véritable protection reste côté serveur
    // (OrgWatchController.assertOrgWatchAdmin).
    get isScheduleTabActive() {
        return this.activeTab === 'schedule' && this.isAdminUser;
    }

    get isPurgeTabActive() {
        return this.activeTab === 'purge' && this.isAdminUser;
    }

    get isAlertsTabActive() {
        return this.activeTab === 'alerts';
    }

    get isAdminTabActive() {
        return this.activeTab === 'admin';
    }

    get monitoringTabClass() {
        return this.tabNavClass(this.isMonitoringTabActive);
    }

    get scheduleTabClass() {
        return this.tabNavClass(this.isScheduleTabActive);
    }

    get purgeTabClass() {
        return this.tabNavClass(this.isPurgeTabActive);
    }

    get alertsTabClass() {
        return this.tabNavClass(this.isAlertsTabActive);
    }

    get adminTabClass() {
        return this.tabNavClass(this.isAdminTabActive);
    }

    tabNavClass(isActive) {
        return isActive ? 'tab-nav-item active' : 'tab-nav-item';
    }

    get darkModeAlt() {
        return this.isDarkMode
            ? (this.isFr ? 'Passer au thème clair' : 'Switch to light theme')
            : (this.isFr ? 'Passer au thème sombre' : 'Switch to dark theme');
    }

    loadThemePreference() {
        try {
            this.isDarkMode = localStorage.getItem(THEME_STORAGE_KEY) === 'dark';
        } catch (e) {
            this.isDarkMode = false;
        }
    }

    loadLanguagePreference() {
        try {
            const stored = localStorage.getItem(LANGUAGE_STORAGE_KEY);
            this.currentLanguage = stored === 'en' ? 'en' : 'fr';
        } catch (e) {
            this.currentLanguage = 'fr';
        }
    }

    toggleDarkMode() {
        this.isDarkMode = !this.isDarkMode;
        try {
            localStorage.setItem(THEME_STORAGE_KEY, this.isDarkMode ? 'dark' : 'light');
        } catch (e) {
            // localStorage indisponible (navigation privée, quota...) : on continue sans persister
        }
    }

    setLanguageFr() {
        this.applyLanguage('fr');
    }

    setLanguageEn() {
        this.applyLanguage('en');
    }

    /**
     * Le graphique est redessiné explicitement : son contenu (légende, unité
     * des graduations, infobulle) vit dans un canvas Chart.js, hors du cycle
     * de rendu réactif de LWC. Sans cet appel, changer de langue laissait la
     * légende et les libellés du graphique dans la langue précédente alors que
     * tout le reste de l'interface avait basculé.
     */
    applyLanguage(language) {
        this.currentLanguage = language;
        this.persistLanguage();
        this.refreshLimitOptions();
        this.updateChart();

        // Le panneau de détail d'un point est construit une fois au clic :
        // ses libellés, unités et date doivent être recalculés dans la
        // nouvelle langue, sinon il reste figé jusqu'au prochain clic.
        if (this.selectedSnapshot) {
            this.selectedSnapshot = {
                ...this.selectedSnapshot,
                formattedDate: new Date(this.selectedSnapshot.timestamp).toLocaleString(this.labels.dateLocale)
            };
        }

        if (this.snapshotMetrics && this.snapshotMetrics.length) {
            this.snapshotMetrics = this.snapshotMetrics.map(metric => ({
                ...metric,
                ...this.selectionMarkers(metric.name),
                friendlyName: this.getFriendlyLabel(metric.name),
                description: this.getDescription(metric.name),
                currentDisplay: this.formatWithUnit(metric.current, metric.name),
                maxDisplay: this.formatWithUnit(metric.max, metric.name)
            }));
        }
    }

    persistLanguage() {
        try {
            localStorage.setItem(LANGUAGE_STORAGE_KEY, this.currentLanguage);
        } catch (e) {
            // localStorage indisponible : on continue sans persister
        }

        // En plus du localStorage (qui pilote l'UI instantanément) : le batch
        // d'alerting quotidien tourne sans contexte navigateur et ne peut
        // connaître la langue choisie que si elle est aussi enregistrée côté
        // serveur. Best-effort, ne bloque pas l'UI.
        saveLanguagePreference({ language: this.currentLanguage })
            .catch(error => {
                console.error('Error saving language preference:', error);
            });
    }

    getFriendlyLabel(technicalName) {
        return METRICS_CONFIG[technicalName]?.[this.currentLanguage]?.label || technicalName;
    }

    getDescription(technicalName) {
        return METRICS_CONFIG[technicalName]?.[this.currentLanguage]?.description || this.labels.genericMetric;
    }

    getCategory(technicalName) {
        return METRICS_CONFIG[technicalName]?.[this.currentLanguage]?.category || this.labels.otherCategory;
    }

    /**
     * Unité d'une métrique, déduite de son nom d'API plutôt que déclarée
     * métrique par métrique : l'API OrgLimits de Salesforce exprime en
     * mégaoctets, et seulement en mégaoctets, les limites dont le nom se
     * termine par "MB" (DataStorageMB, FileStorageMB...). Toutes les autres
     * sont des décomptes, sans unité à afficher.
     */
    getUnit(technicalName) {
        return technicalName && technicalName.endsWith('MB') ? this.labels.unitMegabytes : '';
    }

    formatWithUnit(value, technicalName) {
        const formatted = Number(value).toLocaleString(this.labels.numberLocale);
        const unit = this.getUnit(technicalName);
        return unit ? `${formatted} ${unit}` : formatted;
    }

    get selectedMetricUnit() {
        return this.getUnit(this.selectedLimit);
    }

    updateSpinnerVisibility() {
        this.showInitialSpinner = !(this.dataResolved && this.chartReady && this.minDelayElapsed);
    }

    handleTabChange(event) {
        const targetTab = event.currentTarget.dataset.tab;

        if (this.activeTab === 'alerts' && targetTab !== 'alerts' && this.isAlertFormDirty) {
            this.pendingTabValue = targetTab;
            this.showUnsavedAlertChangesConfirm = true;
            return;
        }

        this.applyTabChange(targetTab);
    }

    applyTabChange(targetTab) {
        this.activeTab = targetTab;
    }

    closeUnsavedAlertChangesConfirm() {
        this.showUnsavedAlertChangesConfirm = false;
        this.pendingTabValue = null;

        this.activeTab = null;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            requestAnimationFrame(() => {
                this.activeTab = 'alerts';
            });
        });
    }

    confirmLeaveAlertsTabDiscardingChanges() {
        const target = this.pendingTabValue;
        this.showUnsavedAlertChangesConfirm = false;
        this.pendingTabValue = null;

        // Recharge depuis le serveur pour annuler les modifications non enregistrées
        this.loadAlertPreferences();
        this.applyTabChange(target);
    }

    // ========== MONITORING TAB LOGIC ==========

    loadUserPreferences() {
        getUserPreferences()
            .then(result => {
                try {
                    if (result && result.length > 0) {
                        const cleanResult = result.replace(/[\r\n]/g, '').trim();

                        if (cleanResult.length > 0) {
                            const hiddenList = cleanResult.split(',')
                                .map(m => m.trim())
                                .filter(m => m.length > 0);

                            this.hiddenMetrics = new Set(hiddenList);
                        } else {
                            this.hiddenMetrics = new Set();
                        }
                    } else {
                        this.hiddenMetrics = new Set();
                    }
                } catch (parseError) {
                    console.error('Error parsing user preferences:', parseError);
                    this.hiddenMetrics = new Set();
                }

                this.preferencesLoaded = true;

                if (this.allHistoryData) {
                    this.refreshLimitOptions();
                }
            })
            .catch(error => {
                console.error('Error loading preferences:', error);
                this.hiddenMetrics = new Set();
                this.preferencesLoaded = true;
            });
    }

    @wire(getLimitsHistory)
    wiredHistory(result) {
        // Référence conservée pour pouvoir forcer un rechargement via
        // refreshApex() après une purge : sans ça, les graphes et les listes
        // continuent d'afficher les exports supprimés jusqu'au rechargement
        // complet de la page.
        this.wiredHistoryResult = result;
        const { error, data } = result;

        // Le wire peut être invoqué une première fois avec data et error tous
        // les deux undefined avant que la vraie réponse Apex n'arrive : on
        // l'ignore pour ne pas fermer le spinner prématurément.
        if (data === undefined && error === undefined) {
            return;
        }

        this.dataResolved = true;
        this.updateSpinnerVisibility();

        if (data) {
            this.allHistoryData = data;

            if (Object.keys(data).length === 0) {
                this.error = this.labels.noDataError;
                this.limitOptions = [];
                return;
            }

            // Une purge peut avoir vidé puis re-rempli l'historique : on efface
            // le message "aucune donnée" resté affiché du chargement précédent.
            this.error = undefined;

            if (this.preferencesLoaded) {
                this.refreshLimitOptions();
            }

            if (this.chart) {
                this.updateChart();
            }
        } else if (error) {
            this.error = this.labels.apexError + this.extractErrorMessage(error);
        }
    }

    // Volontairement supprimé : ce composant écrivait un stub ResizeObserver
    // sur `window`, ce qui pollue la page hôte de tous les autres composants
    // Lightning (inacceptable pour un composant packagé livré chez un client).
    // ResizeObserver est supporté par tous les navigateurs pris en charge par
    // Salesforce, le polyfill n'a plus de raison d'être.

    initializeChart(ctx) {
        const self = this;

        const config = {
            type: 'line',
            data: {
                labels: [],
                datasets: [
                    {
                        label: this.labels.chartLegendCurrent,
                        backgroundColor: 'rgba(54, 162, 235, 0.2)',
                        borderColor: 'rgba(54, 162, 235, 1)',
                        data: [],
                        fill: true,
                        tension: 0.3,
                        pointRadius: 5,
                        pointHoverRadius: 8
                    },
                    {
                        label: this.labels.chartLegendMax,
                        backgroundColor: 'rgba(255, 99, 132, 0.2)',
                        borderColor: 'rgba(255, 99, 132, 1)',
                        data: [],
                        borderDash: [5, 5],
                        fill: false,
                        pointRadius: 5,
                        pointHoverRadius: 8
                    },
                    {
                        label: this.labels.chartLegendThreshold,
                        backgroundColor: 'rgba(224, 165, 66, 0.15)',
                        borderColor: 'rgba(224, 165, 66, 0.9)',
                        data: [],
                        borderDash: [3, 3],
                        borderWidth: 1.5,
                        fill: false,
                        pointRadius: 0,
                        pointHoverRadius: 0
                    }
                ]
            },
            options: {
                responsive: false,
                maintainAspectRatio: false,
                scales: {
                    x: { ticks: {}, grid: {} },
                    y: {
                        beginAtZero: true,
                        // Unité sur les graduations : sans elle, un stockage
                        // affiche "1024" sans dire de quoi il s'agit.
                        // applyChartTheme() ne remplace que .color, ce callback
                        // survit donc aux changements de thème.
                        ticks: {
                            callback: value => self.formatWithUnit(value, self.selectedLimit)
                        },
                        grid: {}
                    }
                },
                onClick: function(event, activeElements) {
                    if (activeElements && activeElements.length > 0) {
                        const index = activeElements[0].index;
                        self.handlePointClick(index);
                    }
                },
                plugins: {
                    legend: {
                        labels: {}
                    },
                    tooltip: {
                        callbacks: {
                            label: context => context.dataset.label + ' : '
                                + self.formatWithUnit(context.parsed.y, self.selectedLimit),
                            afterLabel: () => self.labels.chartTooltipHint
                        }
                    }
                }
            }
        };

        this.chart = new window.Chart(ctx, config);
        this.applyChartTheme();
        this.chartThemeAppliedForDarkMode = this.isDarkMode;
        if (this.allHistoryData) {
            this.updateChart();
        }
    }

    // Chart.js dessine sur un <canvas> : ses couleurs sont des pixels figés à
    // la création, pas du CSS, donc invisibles/illisibles en thème sombre tant
    // qu'on ne les recalcule pas explicitement à partir des tokens --ow-*
    // (axes, grille, légende). Rappelée depuis renderedCallback() à chaque
    // changement de thème pour re-colorer un graphique déjà créé.
    applyChartTheme() {
        if (!this.chart) return;

        const styles = getComputedStyle(this.template.host);
        const textColor = styles.getPropertyValue('--ow-text-secondary').trim();
        const gridColor = styles.getPropertyValue('--ow-border').trim();

        const { x, y } = this.chart.options.scales;
        x.ticks.color = textColor;
        x.grid.color = gridColor;
        y.ticks.color = textColor;
        y.grid.color = gridColor;
        this.chart.options.plugins.legend.labels.color = textColor;

        this.chart.update();
    }

    handleLimitChange(event) {
        this.selectMetric(event.detail.value);
    }

    /**
     * Sélection depuis le panneau de détail : cliquer une métrique la trace
     * sur le graphique, met à jour la liste déroulante et déplace le repère.
     * `currentTarget` et non `target` : le clic peut venir d'un enfant de la
     * ligne (le libellé, l'icône d'aide), qui ne porte pas l'attribut.
     */
    handleSnapshotMetricClick(event) {
        this.selectMetric(event.currentTarget.dataset.metric);
    }

    handleSnapshotMetricKeydown(event) {
        // Rendue focalisable et activable au clavier : la ligne est un <div>,
        // elle n'a donc pas le comportement natif d'un bouton.
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.selectMetric(event.currentTarget.dataset.metric);
        }
    }

    selectMetric(metricName) {
        if (!metricName || metricName === this.selectedLimit) {
            return;
        }
        this.selectedLimit = metricName;
        this.updateChart();
        this.refreshSnapshotSelectionMarkers();
    }

    /**
     * Le panneau de détail reste ouvert sur le même instantané quand on change
     * de métrique : le repère doit suivre celle désormais tracée, sinon il
     * continue de désigner la précédente.
     */
    refreshSnapshotSelectionMarkers() {
        if (!this.snapshotMetrics || !this.snapshotMetrics.length) {
            return;
        }
        this.snapshotMetrics = this.snapshotMetrics.map(metric => ({
            ...metric,
            ...this.selectionMarkers(metric.name)
        }));
    }

    updateChart() {
        // Appelable depuis l'onglet Alertes (mise à jour de la ligne de seuil)
        // alors que Chart.js peut ne pas être encore chargé, ou après le
        // démontage du composant : sans ce garde-fou, this.chart est null.
        if (!this.chart) return;
        if (!this.allHistoryData || !this.allHistoryData[this.selectedLimit]) return;

        const dataPoints = this.allHistoryData[this.selectedLimit];
        const locale = this.labels.dateLocale;

        const labels = dataPoints.map(dp => {
            const date = new Date(dp.timestamp);
            return date.toLocaleDateString(locale) + ' ' + date.toLocaleTimeString(locale, {hour: '2-digit', minute:'2-digit'});
        });

        const currentValues = dataPoints.map(dp => dp.current);
        const maxValues = dataPoints.map(dp => dp.max);

        this.chart.data.labels = labels;
        this.chart.data.datasets[0].data = currentValues;
        this.chart.data.datasets[0].label = this.labels.chartValueLabelPrefix + this.getFriendlyLabel(this.selectedLimit);
        this.chart.data.datasets[1].data = maxValues;
        // Réécrit à chaque mise à jour, et pas seulement à la création du
        // graphique : les libellés de la légende sont figés dans le canvas au
        // moment où les jeux de données sont construits, donc un changement de
        // langue les laissait sinon dans l'ancienne langue.
        this.chart.data.datasets[1].label = this.labels.chartLegendMax;

        const thresholdPercent = this.alertThresholds[this.selectedLimit];
        if (thresholdPercent !== undefined && thresholdPercent !== null) {
            this.chart.data.datasets[2].data = maxValues.map(m => (m * thresholdPercent) / 100);
            this.chart.data.datasets[2].label = `${this.labels.chartLegendThreshold} (${thresholdPercent}%)`;
        } else {
            this.chart.data.datasets[2].data = [];
            this.chart.data.datasets[2].label = this.labels.chartLegendThreshold;
        }

        this.chart.update();
    }

    handlePointClick(index) {
        if (!this.allHistoryData || !this.allHistoryData[this.selectedLimit]) return;

        this.selectedPointIndex = index;

        const dataPoints = this.allHistoryData[this.selectedLimit];
        const selectedPoint = dataPoints[index];

        this.selectedSnapshot = {
            timestamp: selectedPoint.timestamp,
            formattedDate: new Date(selectedPoint.timestamp).toLocaleString(this.labels.dateLocale)
        };

        this.highlightPoint(index);

        getSnapshotAtTime({ targetTimestamp: selectedPoint.timestamp })
            .then(result => {
                this.snapshotMetrics = this.mapSnapshotMetrics(result);
            })
            .catch(error => {
                console.error('Error loading snapshot:', error);
                this.error = this.labels.snapshotLoadError +
                    (error.body ? error.body.message : error.message);
            });
    }

    /**
     * Met en évidence, dans le panneau de détail, la métrique actuellement
     * tracée sur le graphique. La classe est calculée ici car un template LWC
     * ne peut pas concaténer de classes conditionnelles.
     */
    selectionMarkers(metricName) {
        const isSelected = metricName === this.selectedLimit;
        return {
            rowClass: isSelected ? 'metric-row metric-row_selected' : 'metric-row',
            // L'information ne repose ainsi pas sur la seule couleur, et les
            // autres lignes annoncent qu'elles sont cliquables.
            rowTitle: isSelected ? this.labels.selectedMetricAlt : this.labels.selectMetricOnChartAlt
        };
    }

    mapSnapshotMetrics(result) {
        return result
            .filter(metric => !this.hiddenMetrics.has(metric.name))
            .map(metric => {
                const percentage = metric.max > 0
                    ? Math.round((metric.current / metric.max) * 100)
                    : 0;

                return {
                    name: metric.name,
                    ...this.selectionMarkers(metric.name),
                    friendlyName: this.getFriendlyLabel(metric.name),
                    description: this.getDescription(metric.name),
                    current: metric.current,
                    max: metric.max,
                    // Valeurs formatées avec l'unité : sans elle, un stockage
                    // de "1024" ne dit pas s'il s'agit de Mo, de Go ou d'un
                    // nombre d'enregistrements.
                    currentDisplay: this.formatWithUnit(metric.current, metric.name),
                    maxDisplay: this.formatWithUnit(metric.max, metric.name),
                    percentage: percentage,
                    statusClass: this.getStatusClass(percentage),
                    progressStyle: `width: ${Math.min(percentage, 100)}%`
                };
            });
    }

    highlightPoint(index) {
        if (!this.chart) return;

        this.chart.data.datasets[0].pointRadius = this.chart.data.labels.map(() => 5);
        this.chart.data.datasets[0].pointBackgroundColor = this.chart.data.labels.map(() => 'rgba(54, 162, 235, 1)');

        this.chart.data.datasets[0].pointRadius[index] = 10;
        this.chart.data.datasets[0].pointBackgroundColor[index] = '#FFD700';
        this.chart.data.datasets[0].pointBorderColor = this.chart.data.labels.map(() => 'rgba(54, 162, 235, 1)');
        this.chart.data.datasets[0].pointBorderColor[index] = '#FF6B00';
        this.chart.data.datasets[0].pointBorderWidth = this.chart.data.labels.map(() => 2);
        this.chart.data.datasets[0].pointBorderWidth[index] = 3;

        this.chart.update();
    }

    getStatusClass(percentage) {
        if (percentage >= 90) return 'status-critical';
        if (percentage >= 75) return 'status-warning';
        return 'status-ok';
    }

    get hasSnapshot() {
        return this.selectedSnapshot !== null && this.snapshotMetrics.length > 0;
    }

    get leftPanelClass() {
        return this.hasSnapshot ? 'slds-col slds-size_7-of-12' : 'slds-col slds-size_1-of-1';
    }

    get metricsByCategory() {
        if (!this.allHistoryData) return [];

        const categories = {};
        const sortedMetricKeys = Object.keys(this.allHistoryData).sort();

        sortedMetricKeys.forEach(key => {
            const category = this.getCategory(key);
            if (!categories[category]) {
                categories[category] = [];
            }
            categories[category].push({
                name: key,
                label: this.getFriendlyLabel(key),
                description: this.getDescription(key),
                checked: !this.hiddenMetrics.has(key),
                itemClass: 'metric-item'
            });
        });

        return Object.keys(categories)
            .sort()
            .map(catName => ({
                name: catName,
                metrics: categories[catName]
            }));
    }

    get selectedCount() {
        if (!this.allHistoryData) return 0;
        // hiddenMetrics peut contenir des métriques qui n'existent plus dans
        // les données actuelles (ex: après une purge qui a supprimé tous les
        // exports) : on ne compte que celles réellement disponibles pour
        // éviter un total négatif.
        const availableKeys = Object.keys(this.allHistoryData);
        const hiddenAmongAvailable = availableKeys.filter(key => this.hiddenMetrics.has(key)).length;
        return availableKeys.length - hiddenAmongAvailable;
    }

    selectAll() {
        this.hiddenMetrics.clear();
        this.hiddenMetrics = new Set();
        this.refreshLimitOptions();

        if (this.selectedSnapshot && this.selectedPointIndex !== null) {
            this.refreshSnapshot();
        }
    }

    selectNone() {
        if (!this.allHistoryData) return;
        this.hiddenMetrics = new Set(Object.keys(this.allHistoryData));
        this.refreshLimitOptions();

        if (this.selectedSnapshot) {
            this.closeSnapshot();
        }
    }

    selectAllInCategory(event) {
        const categoryName = event.target.dataset.category;
        if (!this.allHistoryData) return;

        Object.keys(this.allHistoryData).forEach(key => {
            if (this.getCategory(key) === categoryName) {
                this.hiddenMetrics.delete(key);
            }
        });

        this.refreshLimitOptions();

        if (this.selectedSnapshot && this.selectedPointIndex !== null) {
            this.refreshSnapshot();
        }
    }

    selectNoneInCategory(event) {
        const categoryName = event.target.dataset.category;
        if (!this.allHistoryData) return;

        Object.keys(this.allHistoryData).forEach(key => {
            if (this.getCategory(key) === categoryName) {
                this.hiddenMetrics.add(key);
            }
        });

        this.refreshLimitOptions();

        if (this.selectedSnapshot && this.selectedPointIndex !== null) {
            this.refreshSnapshot();
        }
    }

    handleMetricToggle(event) {
        const metricName = event.target.dataset.metric;
        const isChecked = event.target.checked;

        if (isChecked) {
            this.hiddenMetrics.delete(metricName);
        } else {
            this.hiddenMetrics.add(metricName);
        }

        this.refreshLimitOptions();

        if (this.selectedSnapshot && this.selectedPointIndex !== null) {
            this.refreshSnapshot();
        }
    }

    refreshLimitOptions() {
        if (!this.allHistoryData) return;

        this.hiddenMetrics = new Set(this.hiddenMetrics);

        this.limitOptions = Object.keys(this.allHistoryData)
            .filter(key => !this.hiddenMetrics.has(key))
            .map(key => {
                return {
                    label: this.getFriendlyLabel(key),
                    value: key
                };
            })
            .sort((a, b) => a.label.localeCompare(b.label));
    }

    refreshSnapshot() {
        if (!this.selectedSnapshot || this.selectedPointIndex === null) return;

        const timestamp = this.selectedSnapshot.timestamp;

        getSnapshotAtTime({ targetTimestamp: timestamp })
            .then(result => {
                this.snapshotMetrics = this.mapSnapshotMetrics(result);

                if (this.snapshotMetrics.length === 0) {
                    this.closeSnapshot();
                }
            })
            .catch(error => {
                console.error('Error refreshing snapshot:', error);
            });
    }

    openSettings() {
        this.hiddenMetricsSnapshot = new Set(this.hiddenMetrics);
        this.showSettings = true;
    }

    closeSettings() {
        this.savePreferences();
        this.finishClosingSettings();
    }

    // Annule : les cases cochées/décochées pendant que la modale était ouverte
    // (handleMetricToggle mute hiddenMetrics en direct) sont abandonnées au
    // profit de l'état capturé à l'ouverture par openSettings().
    cancelSettings() {
        this.hiddenMetrics = new Set(this.hiddenMetricsSnapshot);
        this.finishClosingSettings();
    }

    finishClosingSettings() {
        this.showSettings = false;

        this.refreshLimitOptions();

        if (this.hiddenMetrics.has(this.selectedLimit) && this.limitOptions.length > 0) {
            this.selectedLimit = this.limitOptions[0].value;
            this.updateChart();
        }

        if (this.selectedSnapshot && this.selectedPointIndex !== null) {
            this.refreshSnapshot();
        }
    }

    savePreferences() {
        const hiddenList = Array.from(this.hiddenMetrics).join(',');

        saveUserPreferences({ hiddenMetricsList: hiddenList })
            .then(result => {
                if (result === 'SUCCESS') {
                    this.showToast(this.labels.success, this.labels.prefsSaved, 'success');
                } else {
                    this.showToast(this.labels.error, this.labels.prefsSaveFailedPrefix + result + this.labels.prefsSaveFailedSuffix, 'error');
                }
            })
            .catch(error => {
                console.error('Error saving preferences:', error);
                this.showToast(this.labels.error, this.labels.prefsSaveFailedGeneric, 'error');
            });
    }

    closeSnapshot() {
        this.selectedSnapshot = null;
        this.snapshotMetrics = [];
        this.selectedPointIndex = null;

        if (this.chart) {
            this.chart.data.datasets[0].pointRadius = this.chart.data.labels.map(() => 5);
            this.chart.data.datasets[0].pointBackgroundColor = this.chart.data.labels.map(() => 'rgba(54, 162, 235, 1)');
            this.chart.data.datasets[0].pointBorderWidth = this.chart.data.labels.map(() => 2);
            this.chart.update();
        }
    }

    // ========== SCHEDULE TAB LOGIC ==========

    freqButtonClass(value) {
        return this.selectedFrequency === value ? 'ow-btn-group-item active' : 'ow-btn-group-item';
    }

    get freq15minClass() {
        return this.freqButtonClass('15min');
    }

    get freq30minClass() {
        return this.freqButtonClass('30min');
    }

    get freqHourlyClass() {
        return this.freqButtonClass('hourly');
    }

    get freqDailyClass() {
        return this.freqButtonClass('daily');
    }

    refreshSchedules() {
        this.loadingSchedules = true;

        getActiveSchedules()
            .then(result => {
                this.activeSchedules = result.map(schedule => {
                    return {
                        ...schedule,
                        badgeVariant: this.getScheduleBadgeVariant(schedule.state),
                        nextRun: schedule.nextRun ? new Date(schedule.nextRun).toLocaleString(this.labels.dateLocale) : 'N/A'
                    };
                });
                this.loadingSchedules = false;
            })
            .catch(error => {
                console.error('Error loading schedules:', error);
                this.showToast(this.labels.error, this.labels.scheduleLoadError, 'error');
                this.loadingSchedules = false;
            });
    }

    get hasActiveSchedules() {
        return this.activeSchedules && this.activeSchedules.length > 0;
    }

    get showTimeSelector() {
        return this.selectedFrequency === 'daily';
    }

    get timeSelectorLabel() {
        return this.labels.dailyTimeLabel;
    }

    get timeOptions() {
        const options = [];
        for (let h = 0; h < 24; h++) {
            const hour = h.toString().padStart(2, '0');
            options.push({ label: `${hour}:00`, value: `${hour}:00` });
            options.push({ label: `${hour}:30`, value: `${hour}:30` });
        }
        return options;
    }

    get isScheduleButtonDisabled() {
        if (!this.selectedFrequency) return true;
        if (this.selectedFrequency === 'daily' && !this.selectedTime) return true;
        return false;
    }

    handleFrequencyChange(event) {
        this.selectedFrequency = event.currentTarget.dataset.value;
        this.updateScheduleSummary();
    }

    handleTimeChange(event) {
        this.selectedTime = event.detail.value;
        this.updateScheduleSummary();
    }

    updateScheduleSummary() {
        if (!this.selectedFrequency) {
            this.scheduleSummary = '';
            return;
        }

        let summary = this.labels.summaryIntro;

        switch(this.selectedFrequency) {
            case '15min':
                summary += this.labels.summary15min;
                break;
            case '30min':
                summary += this.labels.summary30min;
                break;
            case 'hourly':
                summary += this.labels.summaryHourly;
                break;
            case 'daily':
                if (this.selectedTime) {
                    summary += this.labels.summaryDailyWithTime.replace('{time}', this.selectedTime);
                } else {
                    summary += this.labels.summaryDailyNoTime;
                }
                break;
        }

        this.scheduleSummary = summary;
    }

    createSchedule() {
        createSchedule({
            frequency: this.selectedFrequency,
            timeValue: this.selectedTime || ''
        })
            .then(jobId => {
                this.showToast(this.labels.success, this.labels.scheduleCreated, 'success');
                this.selectedFrequency = '';
                this.selectedTime = '';
                this.scheduleSummary = '';
                this.alertsTabNeedsRefresh = true;

                this.refreshSchedules();
            })
            .catch(error => {
                console.error('Error creating schedule:', error);
                this.showToast(this.labels.error, this.extractErrorMessage(error), 'error');
            });
    }

    deleteSchedule(event) {
        const jobId = event.target.dataset.jobId;

        deleteSchedule({ jobId: jobId })
            .then(() => {
                this.showToast(this.labels.success, this.labels.scheduleDeleted, 'success');
                this.alertsTabNeedsRefresh = true;

                this.refreshSchedules();
            })
            .catch(error => {
                console.error('Error deleting schedule:', error);
                this.showToast(this.labels.error, this.extractErrorMessage(error), 'error');
            });
    }

    getScheduleBadgeVariant(state) {
        switch(state) {
            case 'WAITING':
            case 'ACQUIRED':
                return 'success';
            case 'EXECUTING':
                return 'warning';
            case 'PAUSED':
                return 'light';
            default:
                return '';
        }
    }


    // ========== PURGE TAB LOGIC ==========

loadDataFilesInfo() {
    this.loadingDataFiles = true;
    this.dataFilesError = undefined;

    getDataFilesInfo()
        .then(result => {
            this.dataFilesInfo = (result || []).map(f => ({
                docId: f.docId,
                createdDate: f.createdDate,
                sizeBytes: f.sizeBytes || 0
            }));

            // Recale le curseur si la plage disponible a changé (ex: purge précédente)
            if (this.purgeAgeDays > this.maxAgeDays) {
                this.purgeAgeDays = this.maxAgeDays;
            }

            this.loadingDataFiles = false;
        })
        .catch(error => {
            console.error('Error loading data files info:', error);
            this.dataFilesError = this.labels.dataFilesLoadError +
                (error.body ? error.body.message : error.message);
            this.dataFilesInfo = [];
            this.loadingDataFiles = false;
        });
}

get hasDataFiles() {
    return this.dataFilesInfo && this.dataFilesInfo.length > 0;
}

get totalFileCount() {
    return this.dataFilesInfo.length;
}

get totalSizeBytes() {
    return this.dataFilesInfo.reduce((sum, f) => sum + f.sizeBytes, 0);
}

get totalSizeFormatted() {
    return this.formatBytes(this.totalSizeBytes);
}

get oldestFileDate() {
    if (!this.hasDataFiles) return null;
    return this.dataFilesInfo.reduce((oldest, f) =>
        new Date(f.createdDate) < new Date(oldest.createdDate) ? f : oldest
    , this.dataFilesInfo[0]).createdDate;
}

get oldestFileDateFormatted() {
    const d = this.oldestFileDate;
    return d ? new Date(d).toLocaleDateString(this.labels.dateLocale) : '—';
}

get maxAgeDays() {
    if (!this.oldestFileDate) return 0;
    const diffMs = Date.now() - new Date(this.oldestFileDate).getTime();
    return Math.max(Math.ceil(diffMs / (1000 * 60 * 60 * 24)), 1);
}

get agePresets() {
    return [
        { label: this.labels.preset7, value: 7 },
        { label: this.labels.preset15, value: 15 },
        { label: this.labels.preset30, value: 30 },
        { label: this.labels.preset60, value: 60 },
        { label: this.labels.preset90, value: 90 },
        { label: this.labels.preset180, value: 180 },
        { label: this.labels.preset365, value: 365 }
    ];
}

get sliderLabel() {
    return this.labels.sliderLabelPrefix + this.purgeAgeDays + this.labels.sliderLabelSuffix;
}

get cutoffDate() {
    const d = new Date();
    d.setHours(0, 0, 0, 0);
    d.setDate(d.getDate() - Number(this.purgeAgeDays));
    return d;
}

get cutoffDateFormatted() {
    return this.cutoffDate.toLocaleDateString(this.labels.dateLocale);
}

get filesToPurge() {
    const cutoff = this.cutoffDate.getTime();
    return this.dataFilesInfo.filter(f => new Date(f.createdDate).getTime() < cutoff);
}

get filesToPurgeCount() {
    return this.filesToPurge.length;
}

get filesToKeepCount() {
    return this.totalFileCount - this.filesToPurgeCount;
}

get sizeToPurgeBytes() {
    return this.filesToPurge.reduce((sum, f) => sum + f.sizeBytes, 0);
}

get sizeToPurgeFormatted() {
    return this.formatBytes(this.sizeToPurgeBytes);
}

get sizeToKeepFormatted() {
    return this.formatBytes(this.totalSizeBytes - this.sizeToPurgeBytes);
}

get purgePercent() {
    if (this.totalSizeBytes === 0) return 0;
    return Math.round((this.sizeToPurgeBytes / this.totalSizeBytes) * 100);
}

get purgeBarStyle() {
    return `width: ${this.purgePercent}%`;
}

get keptBarStyle() {
    return `width: ${100 - this.purgePercent}%`;
}

get isPurgeButtonDisabled() {
    return this.filesToPurgeCount === 0;
}

get isConfirmPurgeDisabled() {
    return !this.purgeConfirmed;
}

handleAgeSliderChange(event) {
    this.purgeAgeDays = Number(event.target.value);
}

handlePresetClick(event) {
    this.purgeAgeDays = Number(event.target.dataset.value);
}

openPurgeConfirm() {
    this.purgeConfirmed = false;
    this.showPurgeConfirm = true;
}

closePurgeConfirm() {
    this.showPurgeConfirm = false;
    this.purgeConfirmed = false;
}

handlePurgeConfirmCheckbox(event) {
    this.purgeConfirmed = event.target.checked;
}

confirmPurge() {
    if (!this.purgeConfirmed) return;

    const cutoff = this.cutoffDate;

    purgeFilesOlderThan({ cutoffDate: cutoff.toISOString() })
        .then(result => {
            this.showPurgeConfirm = false;
            this.purgeConfirmed = false;

            const parts = [];
            if (result.deletedCount) parts.push(`${result.deletedCount}${this.labels.filesDeletedPart}`);
            if (result.alreadyDeletedCount) parts.push(`${result.alreadyDeletedCount}${this.labels.filesAlreadyDeletedPart}`);

            if (result.failedCount > 0) {
                this.showToast(
                    this.labels.partialPurgeTitle,
                    `${parts.join(', ')}. ${result.failedCount}${this.labels.purgeFailedPart}${result.errors.join(' | ')}`,
                    'warning'
                );
            } else {
                this.showToast(
                    this.labels.success,
                    parts.length ? parts.join(', ') + '.' : this.labels.noFilesToDelete,
                    'success'
                );
            }

            this.loadDataFilesInfo();
            // Les exports purgés alimentaient les graphes et la liste des
            // métriques : sans ce refresh, l'onglet Monitoring continue
            // d'afficher des données qui n'existent plus.
            if (this.wiredHistoryResult) {
                refreshApex(this.wiredHistoryResult);
            }
        })
        .catch(error => {
            console.error('Error purging files:', error);
            this.showPurgeConfirm = false;
            this.showToast(
                this.labels.error,
                this.labels.purgeFailedPrefix + this.extractErrorMessage(error),
                'error'
            );
        });
}

formatBytes(bytes) {
    const units = this.labels.byteUnits;
    if (!bytes || bytes <= 0) return `0 ${units[0]}`;
    let value = bytes;
    let unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
        value /= 1024;
        unitIndex++;
    }
    return value.toLocaleString(this.labels.numberLocale, { maximumFractionDigits: 2 }) + ' ' + units[unitIndex];
}

    // ========== PURGE AUTOMATIQUE (PLANIFIÉE) ==========

    get hasActivePurgeSchedule() {
        return this.activePurgeSchedule !== null;
    }

    loadPurgeSchedule() {
        this.loadingPurgeSchedule = true;

        getActivePurgeSchedule()
            .then(result => {
                this.activePurgeSchedule = result
                    ? {
                        ...result,
                        nextRunFormatted: result.nextRun ? new Date(result.nextRun).toLocaleString(this.labels.dateLocale) : 'N/A',
                        lastRunFormatted: result.lastRunDate ? new Date(result.lastRunDate).toLocaleString(this.labels.dateLocale) : null,
                        lastRunFailed: result.lastRunStatus === 'Failed'
                    }
                    : null;
                this.loadingPurgeSchedule = false;
            })
            .catch(error => {
                console.error('Error loading purge schedule:', error);
                this.activePurgeSchedule = null;
                this.loadingPurgeSchedule = false;
            });
    }

    handleScheduledPurgeAgeChange(event) {
        this.scheduledPurgeAgeDays = Number(event.detail.value);
    }

    handleScheduledPurgeTimeChange(event) {
        this.scheduledPurgeTime = event.detail.value;
    }

    get isCreatePurgeScheduleDisabled() {
        return !this.scheduledPurgeTime || !this.scheduledPurgeAgeDays || this.scheduledPurgeAgeDays < 1;
    }

    get isConfirmCreatePurgeScheduleDisabled() {
        return !this.createPurgeScheduleConfirmed;
    }

    openCreatePurgeScheduleConfirm() {
        this.createPurgeScheduleConfirmed = false;
        this.showCreatePurgeScheduleConfirm = true;
    }

    closeCreatePurgeScheduleConfirm() {
        this.showCreatePurgeScheduleConfirm = false;
        this.createPurgeScheduleConfirmed = false;
    }

    handleCreatePurgeScheduleConfirmCheckbox(event) {
        this.createPurgeScheduleConfirmed = event.target.checked;
    }

    confirmCreatePurgeSchedule() {
        if (!this.createPurgeScheduleConfirmed) return;

        createPurgeSchedule({ ageDays: this.scheduledPurgeAgeDays, timeValue: this.scheduledPurgeTime })
            .then(() => {
                this.showCreatePurgeScheduleConfirm = false;
                this.createPurgeScheduleConfirmed = false;
                this.showToast(this.labels.success, this.labels.autoPurgeActivated, 'success');
                this.loadPurgeSchedule();
            })
            .catch(error => {
                console.error('Error creating purge schedule:', error);
                this.showCreatePurgeScheduleConfirm = false;
                this.showToast(this.labels.error, this.extractErrorMessage(error), 'error');
            });
    }

    deletePurgeSchedule() {
        if (!this.activePurgeSchedule) return;

        deletePurgeSchedule({ jobId: this.activePurgeSchedule.jobId })
            .then(() => {
                this.showToast(this.labels.success, this.labels.autoPurgeDisabled, 'success');
                this.loadPurgeSchedule();
            })
            .catch(error => {
                console.error('Error deleting purge schedule:', error);
                this.showToast(this.labels.error, this.extractErrorMessage(error), 'error');
            });
    }

    // ========== ALERTES ==========

    loadAlertPreferences() {
        this.loadingAlertPrefs = true;

        getAlertPreferences()
            .then(result => {
                this.hasActiveExportSchedule = result.hasActiveExportSchedule;
                this.alertEmailMode = result.emailMode || 'OnlyOnBreach';
                this.adminAlertSendTime = result.alertSendTime || '15:00';
                this.savedAlertSendTime = this.adminAlertSendTime;

                const thresholds = {};
                (result.metricThresholds || '')
                    .split(',')
                    .filter(pair => pair.includes(':'))
                    .forEach(pair => {
                        const [name, value] = pair.split(':');
                        if (name && value && !Number.isNaN(Number(value))) {
                            thresholds[name.trim()] = Number(value.trim());
                        }
                    });
                this.alertThresholds = thresholds;

                // Référence pour détecter les modifications non enregistrées
                this.savedMetricThresholdsString = this.metricThresholdsString;
                this.savedAlertEmailMode = this.alertEmailMode;

                this.loadingAlertPrefs = false;
            })
            .catch(error => {
                console.error('Error loading alert preferences:', error);
                this.loadingAlertPrefs = false;
            });
    }

    get alertMailInfo() {
        return this.labels.alertMailInfoPrefix + this.savedAlertSendTime + this.labels.alertMailInfoSuffix;
    }

    get isAlertFormDirty() {
        return this.metricThresholdsString !== this.savedMetricThresholdsString
            || this.alertEmailMode !== this.savedAlertEmailMode;
    }

    get alertMetricRows() {
        if (!this.allHistoryData) return [];

        return Object.keys(this.allHistoryData)
            .filter(key => !this.hiddenMetrics.has(key))
            .sort((a, b) => this.getFriendlyLabel(a).localeCompare(this.getFriendlyLabel(b)))
            .map(key => ({
                name: key,
                label: this.getFriendlyLabel(key),
                threshold: this.alertThresholds[key] !== undefined ? this.alertThresholds[key] : null
            }));
    }

    get hasAnyAlertConfigured() {
        return Object.keys(this.alertThresholds).length > 0;
    }

    get isDisableAllAlertsDisabled() {
        return !this.hasAnyAlertConfigured;
    }

    get metricThresholdsString() {
        return Object.keys(this.alertThresholds)
            .map(name => `${name}:${this.alertThresholds[name]}`)
            .join(',');
    }

    get emailModeAlwaysClass() {
        return this.alertEmailMode === 'Always' ? 'ow-btn-group-item active' : 'ow-btn-group-item';
    }

    get emailModeOnBreachClass() {
        return this.alertEmailMode === 'OnlyOnBreach' ? 'ow-btn-group-item active' : 'ow-btn-group-item';
    }

    handleEmailModeClick(event) {
        this.alertEmailMode = event.currentTarget.dataset.value;
    }

    get alertStatusToggleText() {
        return this.hasAnyAlertConfigured ? this.labels.alertsActive : this.labels.alertsInactive;
    }

    handleMetricThresholdChange(event) {
        const metric = event.target.dataset.metric;
        const rawValue = event.detail.value;
        const updated = { ...this.alertThresholds };

        if (rawValue === '' || rawValue === null || rawValue === undefined) {
            delete updated[metric];
        } else {
            updated[metric] = Number(rawValue);
        }

        this.alertThresholds = updated;
        // La 3e série du graphe Monitoring est la ligne de seuil : sans ça elle
        // reste sur l'ancienne valeur jusqu'au prochain changement de métrique.
        this.updateChart();
    }

    handleGlobalThresholdChange(event) {
        this.globalThresholdInput = Number(event.detail.value);
    }

    applyGlobalThreshold() {
        const updated = { ...this.alertThresholds };
        this.alertMetricRows.forEach(row => {
            updated[row.name] = this.globalThresholdInput;
        });
        this.alertThresholds = updated;
        this.updateChart();
    }

    saveAlertSettings() {
        saveAlertPreferences({
            metricThresholds: this.metricThresholdsString,
            emailMode: this.alertEmailMode
        })
            .then(() => {
                this.savedMetricThresholdsString = this.metricThresholdsString;
                this.savedAlertEmailMode = this.alertEmailMode;
                this.showToast(this.labels.success, this.labels.alertPrefsSaved, 'success');
                this.updateChart();
            })
            .catch(error => {
                console.error('Error saving alert preferences:', error);
                this.showToast(this.labels.error, this.extractErrorMessage(error), 'error');
            });
    }

    handleAlertStatusToggleChange(event) {
        const turningOn = event.target.checked;
        if (!turningOn && this.hasAnyAlertConfigured) {
            // Mémorisé pour remettre l'interrupteur sur ON si l'admin annule :
            // aucune donnée ne change dans ce cas, donc LWC ne re-rendrait pas
            // l'input et il resterait affiché sur OFF à tort.
            this.alertStatusToggleElement = event.target;
            this.openDisableAllAlertsConfirm();
        }
        // Rien à faire pour "l'activer" directement via le toggle : il faut
        // configurer au moins un seuil ci-dessous pour que ça devienne actif.
        // Le toggle se resynchronisera de toute façon sur checked={hasAnyAlertConfigured}.
    }

    openDisableAllAlertsConfirm() {
        this.showDisableAllAlertsConfirm = true;
    }

    closeDisableAllAlertsConfirm() {
        if (this.alertStatusToggleElement) {
            this.alertStatusToggleElement.checked = true;
            this.alertStatusToggleElement = null;
        }
        this.showDisableAllAlertsConfirm = false;
    }

    confirmDisableAllAlerts() {
        this.alertStatusToggleElement = null;
        disableAllAlerts()
            .then(() => {
                this.alertThresholds = {};
                this.savedMetricThresholdsString = this.metricThresholdsString;
                this.showDisableAllAlertsConfirm = false;
                this.showToast(this.labels.success, this.labels.allAlertsDisabled, 'success');
                this.updateChart();
            })
            .catch(error => {
                console.error('Error disabling alerts:', error);
                this.showDisableAllAlertsConfirm = false;
                this.showToast(this.labels.error, this.extractErrorMessage(error), 'error');
            });
    }

    // ========== ADMIN ==========

    // Le libellé "Actif"/"Inactif" sous chaque toggle est calculé côté client
    // (pas un getter réactif par ligne possible dans un for:each) et doit
    // être recalculé à chaque chargement/rafraîchissement des lignes.
    decorateAdminRow(row) {
        return {
            ...row,
            userPsToggleText: row.hasUserPS ? this.labels.toggleActive : this.labels.toggleInactive,
            adminPsToggleText: row.hasAdminPS ? this.labels.toggleActive : this.labels.toggleInactive
        };
    }

    loadAdminUsers() {
        this.loadingAdminUsers = true;

        getUserAccessOverview()
            .then(result => {
                this.adminUserRows = (result || []).map(row => this.decorateAdminRow(row));
                this.loadingAdminUsers = false;
            })
            .catch(error => {
                console.error('Error loading admin user overview:', error);
                this.showToast(this.labels.error, this.labels.adminLoadError, 'error');
                this.loadingAdminUsers = false;
            });
    }

    get hasAdminUsers() {
        return this.adminUserRows && this.adminUserRows.length > 0;
    }

    handleAdminAlertSendTimeChange(event) {
        this.adminAlertSendTime = event.detail.value;
    }

    saveAlertSendTime() {
        this.savingAlertSendTime = true;

        setAlertScheduleTime({ timeValue: this.adminAlertSendTime })
            .then(() => {
                this.savedAlertSendTime = this.adminAlertSendTime;
                this.showToast(this.labels.success, this.labels.adminAlertSendTimeSaved, 'success');
                this.savingAlertSendTime = false;
            })
            .catch(error => {
                console.error('Error saving alert send time:', error);
                this.showToast(this.labels.error, this.extractErrorMessage(error), 'error');
                this.savingAlertSendTime = false;
            });
    }

    // Suggestions "au fil de la frappe" (dès 3 caractères, avec un léger
    // debounce pour ne pas lancer un appel Apex à chaque frappe) : distinctes
    // du bouton Rechercher, qui garde son comportement historique (ajout
    // direct de tous les résultats dans le tableau).
    handleAdminSearchInput(event) {
        this.adminSearchTerm = event.detail.value;
        const term = this.adminSearchTerm.trim();
        console.log('[OrgWatch][search] handleAdminSearchInput - raw value:', JSON.stringify(event.detail.value), '| trimmed term:', JSON.stringify(term), '| length:', term.length);

        if (this.adminSearchDebounceTimer) {
            clearTimeout(this.adminSearchDebounceTimer);
            this.adminSearchDebounceTimer = null;
        }

        if (term.length < 3) {
            console.log('[OrgWatch][search] term too short (<3), clearing suggestions and NOT calling Apex');
            this.adminSearchSuggestions = [];
            this.showAdminSearchDropdown = false;
            return;
        }

        console.log('[OrgWatch][search] scheduling performAdminAutoSearch in 300ms for term:', JSON.stringify(term));
        this.adminSearchDebounceTimer = setTimeout(() => {
            console.log('[OrgWatch][search] debounce elapsed, calling performAdminAutoSearch now for term:', JSON.stringify(term));
            this.performAdminAutoSearch(term);
        }, 300);
    }

    performAdminAutoSearch(term) {
        console.log('[OrgWatch][search] performAdminAutoSearch - calling Apex searchAdminUsers with term:', JSON.stringify(term));
        searchAdminUsers({ searchTerm: term })
            .then(result => {
                console.log('[OrgWatch][search] performAdminAutoSearch - Apex resolved. Raw result:', JSON.stringify(result));
                // Le champ a pu changer pendant l'aller-retour Apex : on ignore
                // une réponse qui ne correspond plus à la saisie actuelle.
                if (this.adminSearchTerm.trim() !== term) {
                    console.log('[OrgWatch][search] performAdminAutoSearch - STALE RESPONSE IGNORED. current field value:', JSON.stringify(this.adminSearchTerm.trim()), '!== requested term:', JSON.stringify(term));
                    return;
                }
                const existingIds = new Set(this.adminUserRows.map(r => r.userId));
                console.log('[OrgWatch][search] performAdminAutoSearch - existingIds already in table:', JSON.stringify(Array.from(existingIds)));
                this.adminSearchSuggestions = (result || [])
                    .filter(r => !existingIds.has(r.userId))
                    .map(row => this.decorateAdminRow(row));
                console.log('[OrgWatch][search] performAdminAutoSearch - final adminSearchSuggestions after filtering:', JSON.stringify(this.adminSearchSuggestions));
                this.showAdminSearchDropdown = true;
                console.log('[OrgWatch][search] performAdminAutoSearch - showAdminSearchDropdown set to true');
            })
            .catch(error => {
                console.error('[OrgWatch][search] performAdminAutoSearch - Apex CALL FAILED:', error, JSON.stringify(error));
            });
    }

    handleAdminSearchFocus() {
        if (this.adminSearchTerm.trim().length >= 3 && this.adminSearchSuggestions.length > 0) {
            this.showAdminSearchDropdown = true;
        }
    }

    handleAdminSearchBlur() {
        // Délai court pour laisser le clic sur une suggestion s'exécuter
        // avant que le blur ne referme la liste.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.adminSearchBlurTimer = setTimeout(() => {
            this.adminSearchBlurTimer = null;
            this.showAdminSearchDropdown = false;
        }, 200);
    }

    /**
     * Tabuler du champ vers une suggestion déclenche le blur du champ : sans
     * annuler la fermeture programmée, la liste se refermerait sous le focus
     * et rendrait la sélection au clavier impossible.
     */
    handleAdminSuggestionFocus() {
        if (this.adminSearchBlurTimer) {
            clearTimeout(this.adminSearchBlurTimer);
            this.adminSearchBlurTimer = null;
        }
    }

    selectAdminSearchSuggestion(event) {
        const userId = event.currentTarget.dataset.userId;
        console.log('[OrgWatch][search] selectAdminSearchSuggestion - clicked userId:', userId);
        const row = this.adminSearchSuggestions.find(r => r.userId === userId);
        if (!row) {
            console.log('[OrgWatch][search] selectAdminSearchSuggestion - no matching row found in adminSearchSuggestions, aborting');
            return;
        }

        const existingIds = new Set(this.adminUserRows.map(r => r.userId));
        if (!existingIds.has(row.userId)) {
            this.adminUserRows = [...this.adminUserRows, row].sort((a, b) => a.name.localeCompare(b.name));
        }

        this.adminSearchTerm = '';
        this.adminSearchSuggestions = [];
        this.showAdminSearchDropdown = false;
    }

    get hasAdminSearchSuggestions() {
        return this.adminSearchSuggestions && this.adminSearchSuggestions.length > 0;
    }

    handleAdminSearch() {
        const term = (this.adminSearchTerm || '').trim();
        console.log('[OrgWatch][search] handleAdminSearch (bouton) - term:', JSON.stringify(term), '| length:', term.length);
        if (term.length < 2) {
            console.log('[OrgWatch][search] handleAdminSearch - term too short (<2), NOT calling Apex');
            return;
        }

        this.showAdminSearchDropdown = false;
        this.searchingAdminUsers = true;
        console.log('[OrgWatch][search] handleAdminSearch - calling Apex searchAdminUsers with term:', JSON.stringify(term));

        searchAdminUsers({ searchTerm: term })
            .then(result => {
                console.log('[OrgWatch][search] handleAdminSearch - Apex resolved. Raw result:', JSON.stringify(result));
                const existingIds = new Set(this.adminUserRows.map(r => r.userId));
                console.log('[OrgWatch][search] handleAdminSearch - existingIds already in table:', JSON.stringify(Array.from(existingIds)));
                const newRows = (result || []).filter(r => !existingIds.has(r.userId)).map(row => this.decorateAdminRow(row));
                console.log('[OrgWatch][search] handleAdminSearch - newRows to merge (after filtering out existing):', JSON.stringify(newRows));
                this.adminUserRows = [...this.adminUserRows, ...newRows].sort((a, b) => a.name.localeCompare(b.name));

                if ((result || []).length === 0) {
                    console.log('[OrgWatch][search] handleAdminSearch - 0 results from Apex, showing "no results" toast');
                    this.showToast(this.labels.adminSearchButton, this.labels.adminNoSearchResults, 'info');
                }

                this.searchingAdminUsers = false;
            })
            .catch(error => {
                console.error('[OrgWatch][search] handleAdminSearch - Apex CALL FAILED:', error, JSON.stringify(error));
                this.showToast(this.labels.error, this.labels.adminSearchError, 'error');
                this.searchingAdminUsers = false;
            });
    }

    handleToggleUserPS(event) {
        this.handleTogglePS(event, 'OrgWatch_User');
    }

    handleToggleAdminPS(event) {
        this.handleTogglePS(event, 'OrgWatch_Admin');
    }

    handleTogglePS(event, permissionSetName) {
        const userId = event.target.dataset.userId;
        const row = this.adminUserRows.find(r => r.userId === userId);
        if (!row) return;

        const turningOn = event.target.checked;

        if (turningOn) {
            this.applyPermissionSetChange(row, permissionSetName, true);
            return;
        }

        // L'interrupteur est déjà visuellement sur OFF alors que la révocation
        // n'est pas confirmée : on garde une référence pour pouvoir le remettre
        // sur ON si l'admin annule (rien ne change côté données, donc LWC ne
        // re-rendrait pas l'input de lui-même).
        this.revokeToggleElement = event.target;
        this.revokeTargetRow = row;
        this.revokePermissionSetName = permissionSetName;
        this.revokeAlsoRemovesAdmin = permissionSetName === 'OrgWatch_User' && row.hasAdminPS;
        this.showRevokeConfirm = true;
    }

    get revokeConfirmMessage() {
        if (!this.revokeTargetRow) return '';
        const psLabel = this.revokePermissionSetName === 'OrgWatch_User' ? this.labels.adminColUserPS : this.labels.adminColAdminPS;
        let message = this.labels.revokeConfirmPrefix + psLabel + this.labels.revokeConfirmToUser + this.revokeTargetRow.name;
        message += this.revokeAlsoRemovesAdmin ? this.labels.revokeConfirmAlsoAdmin : this.labels.revokeConfirmSuffix;
        return message;
    }

    closeRevokeConfirm() {
        if (this.revokeToggleElement) {
            this.revokeToggleElement.checked = true;
            this.revokeToggleElement = null;
        }
        this.showRevokeConfirm = false;
        this.revokeTargetRow = null;
        this.revokePermissionSetName = null;
        this.revokeAlsoRemovesAdmin = false;
    }

    confirmRevokePS() {
        const row = this.revokeTargetRow;
        const psName = this.revokePermissionSetName;
        this.revokeToggleElement = null;
        this.showRevokeConfirm = false;
        this.applyPermissionSetChange(row, psName, false);
        this.revokeTargetRow = null;
        this.revokePermissionSetName = null;
        this.revokeAlsoRemovesAdmin = false;
    }

    applyPermissionSetChange(row, permissionSetName, assign) {
        // Un admin peut se retirer ses propres droits depuis ce tableau : on
        // repère le cas AVANT l'appel, car après coup la ligne peut avoir
        // disparu du tableau.
        const targetsCurrentUser = row.userId === CURRENT_USER_ID;

        setPermissionSetAssignment({ targetUserId: row.userId, permissionSetName: permissionSetName, assign: assign })
            .then(() => {
                this.showToast(this.labels.success, assign ? this.labels.adminPsGranted : this.labels.adminPsRevoked, 'success');

                if (targetsCurrentUser && !assign) {
                    this.refreshMyAccessAfterSelfRevoke();
                } else {
                    this.loadAdminUsers();
                }
            })
            .catch(error => {
                console.error('Error updating permission set assignment:', error);
                this.showToast(this.labels.error, error.body ? error.body.message : this.labels.adminPsUpdateError, 'error');
                this.loadAdminUsers();
            });
    }

    /**
     * Après un retrait de droits sur soi-même : sans ça, le rechargement du
     * tableau rappelait getUserAccessOverview(), désormais refusé côté
     * serveur, et l'utilisateur restait bloqué sur un onglet Admin ne
     * montrant plus qu'une erreur. getMyAccessState() n'est pas mis en cache,
     * contrairement à isAdminUser(), pour ne pas relire l'état d'avant.
     */
    refreshMyAccessAfterSelfRevoke() {
        getMyAccessState()
            .then(state => {
                this.isAdminUser = state.isAdmin === true;
                this.hasOrgWatchAccess = state.hasAccess === true;
                this.accessChecked = true;

                if (!this.hasOrgWatchAccess) {
                    // Plus aucun accès : le composant ne rend plus que le
                    // message de refus, il n'y a plus rien à recharger.
                    this.showToast(this.labels.selfAdminRevokedTitle, this.labels.selfAccessRevoked, 'warning');
                    return;
                }

                if (!this.isAdminUser) {
                    this.activeTab = 'monitoring';
                    this.resetAdminTabState();
                    this.showToast(this.labels.selfAdminRevokedTitle, this.labels.selfAdminRevoked, 'warning');
                    return;
                }

                this.loadAdminUsers();
            })
            .catch(error => {
                console.error('Error refreshing own access state:', error);
                // En cas de doute, on retombe sur l'état le plus restrictif
                // plutôt que de laisser une interface d'admin inutilisable.
                this.isAdminUser = false;
                this.activeTab = 'monitoring';
                this.resetAdminTabState();
            });
    }

    resetAdminTabState() {
        this.adminUserRows = [];
        this.adminSearchTerm = '';
        this.adminSearchSuggestions = [];
        this.showAdminSearchDropdown = false;
        this.setupStatus = null;
    }

    openDisableUserAlerts(event) {
        const userId = event.target.dataset.userId;
        const row = this.adminUserRows.find(r => r.userId === userId);
        if (!row) return;

        this.disableAlertsTargetRow = row;
        this.notifyUserOnDisable = true;
        this.showDisableUserAlertsConfirm = true;
    }

    get disableUserAlertsMessage() {
        if (!this.disableAlertsTargetRow) return '';
        return this.labels.disableUserAlertsTextPrefix + this.disableAlertsTargetRow.name + this.labels.disableUserAlertsTextSuffix;
    }

    get notifyUserCheckboxLabel() {
        if (!this.disableAlertsTargetRow) return '';
        return this.labels.notifyCheckboxPrefix + this.disableAlertsTargetRow.name + this.labels.notifyCheckboxSuffix;
    }

    closeDisableUserAlertsConfirm() {
        this.showDisableUserAlertsConfirm = false;
        this.disableAlertsTargetRow = null;
    }

    handleNotifyUserCheckbox(event) {
        this.notifyUserOnDisable = event.target.checked;
    }

    confirmDisableUserAlerts() {
        const row = this.disableAlertsTargetRow;
        if (!row) return;

        disableUserAlerts({ targetUserId: row.userId, notifyUser: this.notifyUserOnDisable })
            .then(() => {
                this.showDisableUserAlertsConfirm = false;
                this.disableAlertsTargetRow = null;
                this.showToast(this.labels.success, this.labels.adminUserAlertsDisabled, 'success');
                this.loadAdminUsers();
            })
            .catch(error => {
                console.error('Error disabling user alerts:', error);
                this.showDisableUserAlertsConfirm = false;
                this.disableAlertsTargetRow = null;
                this.showToast(this.labels.error, error.body ? error.body.message : this.labels.adminPsUpdateError, 'error');
            });
    }

    // ========== QUI PEUT MODIFIER L'HEURE D'ENVOI ? ==========

    openAdminDirectory() {
        this.showAdminDirectory = true;

        // Chargé à l'ouverture seulement : l'information n'est utile que dans
        // cette popup, et un utilisateur standard n'y va qu'exceptionnellement.
        if (this.adminDirectory) {
            return;
        }
        this.loadingAdminDirectory = true;
        getAdminDirectory()
            .then(result => {
                this.adminDirectory = result;
                this.loadingAdminDirectory = false;
            })
            .catch(error => {
                console.error('Error loading admin directory:', error);
                this.loadingAdminDirectory = false;
                this.showToast(this.labels.error, this.extractErrorMessage(error), 'error');
            });
    }

    closeAdminDirectory() {
        this.showAdminDirectory = false;
    }

    get hasOrgWatchAdmins() {
        return !!(this.adminDirectory && this.adminDirectory.admins && this.adminDirectory.admins.length);
    }

    /**
     * Libellé du Permission Set tel qu'il existe dans l'org (un client peut
     * l'avoir renommé). Le nom d'API ne sert que de repli, dans le cas où le
     * Permission Set serait absent de l'org et n'aurait donc pas de libellé.
     */
    get adminPermissionSetDisplay() {
        if (!this.adminDirectory) {
            return '';
        }
        return this.adminDirectory.permissionSetLabel || this.adminDirectory.permissionSetApiName;
    }

    // ========== INSTALLATION / MAINTENANCE ==========
    //
    // OrgWatch étant livré en unlocked package, Salesforce n'exécute aucun
    // script à l'installation ni à la désinstallation : cette section est le
    // seul endroit d'où un admin peut initialiser l'outil dans son org et le
    // préparer à une désinstallation propre.

    loadSetupStatus() {
        this.loadingSetupStatus = true;
        getSetupStatus()
            .then(result => {
                this.setupStatus = result;
                this.loadingSetupStatus = false;
            })
            .catch(error => {
                console.error('Error loading setup status:', error);
                this.showToast(this.labels.error, this.extractErrorMessage(error), 'error');
                this.loadingSetupStatus = false;
            });
    }

    get setupLibraryStatusLabel() {
        if (!this.setupStatus) return '';
        return this.setupStatus.libraryExists ? this.labels.maintenancePresent : this.labels.maintenanceMissing;
    }

    get setupChartStatusLabel() {
        if (!this.setupStatus) return '';
        return this.setupStatus.chartLibraryPresent ? this.labels.maintenancePresent : this.labels.maintenanceMissing;
    }

    get setupLibraryStatusClass() {
        return this.setupStatus && this.setupStatus.libraryExists
            ? 'ow-check-ok'
            : 'ow-check-missing';
    }

    get setupChartStatusClass() {
        return this.setupStatus && this.setupStatus.chartLibraryPresent
            ? 'ow-check-ok'
            : 'ow-check-missing';
    }

    get hasNoOrgWatchJobs() {
        return !this.setupStatus || this.setupStatus.scheduledJobCount === 0;
    }

    runSetup() {
        this.runningSetup = true;
        runOrgWatchSetup()
            .then(result => {
                if (!result.success) {
                    this.runningSetup = false;
                    // Le cas "bibliothèque déjà prise" décrit une marche à
                    // suivre : toast persistant, pour laisser le temps de la
                    // lire et de la refermer soi-même.
                    this.showToast(
                        this.labels.error,
                        result.errorMessage,
                        'error',
                        result.libraryNameTaken ? 'sticky' : 'dismissable'
                    );
                    return undefined;
                }
                let libraryMessage;
                if (result.libraryAdopted) {
                    libraryMessage = this.labels.maintenanceLibraryAdopted;
                } else if (result.libraryCreated) {
                    libraryMessage = this.labels.maintenanceSetupDone;
                } else {
                    libraryMessage = this.labels.maintenanceSetupAlready;
                }

                // Second appel serveur distinct, jamais fusionné avec
                // runOrgWatchSetup() : combiner l'insert ContentWorkspace et
                // System.schedule() dans une même transaction Apex lèverait
                // MIXED_DML_OPERATION.
                return ensureDefaultExportSchedule().then(scheduleResult => {
                    this.runningSetup = false;

                    let scheduleMessage;
                    if (scheduleResult.created) {
                        scheduleMessage = this.labels.maintenanceScheduleActivated;
                    } else if (scheduleResult.alreadyActive) {
                        scheduleMessage = this.labels.maintenanceScheduleAlready;
                    } else {
                        scheduleMessage = scheduleResult.errorMessage || this.labels.maintenanceScheduleError;
                    }

                    this.showToast(
                        this.labels.success,
                        libraryMessage + ' ' + scheduleMessage,
                        scheduleResult.success ? 'success' : 'warning'
                    );
                    this.loadSetupStatus();
                });
            })
            .catch(error => {
                console.error('Error running setup:', error);
                this.runningSetup = false;
                this.showToast(this.labels.error, this.extractErrorMessage(error), 'error');
            });
    }

    runPrepareUninstall() {
        this.runningUninstallPrep = true;
        prepareUninstall()
            .then(result => {
                this.runningUninstallPrep = false;
                const message = result.abortedCount > 0
                    ? this.labels.maintenanceUninstallDone + result.abortedJobNames.join(', ')
                    : this.labels.maintenanceUninstallNone;
                this.showToast(
                    result.success ? this.labels.success : this.labels.partialPurgeTitle,
                    result.success ? message : message + ' | ' + result.failedJobNames.join(', '),
                    result.success ? 'success' : 'warning'
                );
                this.loadSetupStatus();
                this.refreshSchedules();
            })
            .catch(error => {
                console.error('Error preparing uninstall:', error);
                this.runningUninstallPrep = false;
                this.showToast(this.labels.error, this.extractErrorMessage(error), 'error');
            });
    }

    openDeleteAllDataConfirm() {
        this.deleteAllDataConfirmed = false;
        this.deleteAllDataIncludeLibrary = false;
        this.showDeleteAllDataConfirm = true;
    }

    closeDeleteAllDataConfirm() {
        this.showDeleteAllDataConfirm = false;
        this.deleteAllDataConfirmed = false;
    }

    handleDeleteAllDataCheckbox(event) {
        this.deleteAllDataConfirmed = event.target.checked;
    }

    handleDeleteAllDataLibraryCheckbox(event) {
        this.deleteAllDataIncludeLibrary = event.target.checked;
    }

    get isDeleteAllDataDisabled() {
        return !this.deleteAllDataConfirmed || this.deletingAllData;
    }

    confirmDeleteAllData() {
        if (!this.deleteAllDataConfirmed) return;

        this.deletingAllData = true;
        deleteAllOrgWatchData({ deleteLibrary: this.deleteAllDataIncludeLibrary })
            .then(result => {
                this.deletingAllData = false;
                this.showDeleteAllDataConfirm = false;
                this.deleteAllDataConfirmed = false;
                this.showToast(
                    result.success ? this.labels.success : this.labels.partialPurgeTitle,
                    this.labels.maintenancePurgeAllDone + result.deletedFileCount
                        + (result.libraryDeletionQueued ? this.labels.maintenancePurgeAllLibraryQueued : '')
                        + (result.errors && result.errors.length ? ' | ' + result.errors.join(' | ') : ''),
                    result.success ? 'success' : 'warning'
                );
                this.loadSetupStatus();
                this.loadDataFilesInfo();
                if (this.wiredHistoryResult) {
                    refreshApex(this.wiredHistoryResult);
                }
            })
            .catch(error => {
                console.error('Error deleting all OrgWatch data:', error);
                this.deletingAllData = false;
                this.showDeleteAllDataConfirm = false;
                this.showToast(this.labels.error, this.extractErrorMessage(error), 'error');
            });
    }

    // ========== UTILITY ==========

    /**
     * Un rejet non-Apex (erreur réseau, TypeError côté client) n'a pas de
     * `body` : lire `error.body.message` directement lève alors une seconde
     * erreur dans le .catch et l'utilisateur ne voit aucun message.
     */
    extractErrorMessage(error) {
        if (!error) {
            return this.labels.error;
        }
        if (error.body && error.body.message) {
            return error.body.message;
        }
        if (Array.isArray(error.body) && error.body.length > 0 && error.body[0].message) {
            return error.body[0].message;
        }
        return error.message || this.labels.error;
    }

    /**
     * `mode` optionnel : 'sticky' pour un message que l'utilisateur doit
     * pouvoir lire et refermer lui-même (marche à suivre en plusieurs étapes),
     * les toasts se refermant sinon d'eux-mêmes au bout de quelques secondes.
     */
    showToast(title, message, variant, mode) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: mode || 'dismissable'
        });
        this.dispatchEvent(event);
    }
}