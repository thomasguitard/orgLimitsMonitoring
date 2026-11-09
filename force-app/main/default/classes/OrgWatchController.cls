public with sharing class OrgWatchController {

    private static final String CONFIG_FILENAME = 'OrgWatchUserPreferences.csv';
    private static final String LIBRARY_NAME = Test.isRunningTest() ? 'OrgWatch Reporting TEST' : 'OrgWatch Reporting';
    private static final String DEFAULT_EMAIL_MODE = 'OnlyOnBreach';
    private static final String DEFAULT_LANGUAGE = 'fr';
    private static final String ADMIN_PERMISSION_SET = 'OrgWatch_Admin';
    private static final String USER_PERMISSION_SET = 'OrgWatch_User';
    @TestVisible
    private static final String ADMIN_REQUIRED_MESSAGE =
        'Action réservée aux administrateurs OrgWatch (permission "OrgWatch - Accès Admin").'
        + ' / Reserved for OrgWatch administrators ("OrgWatch - Admin Access" permission).';
    @TestVisible
    private static final String ACCESS_REQUIRED_MESSAGE =
        'Accès réservé aux utilisateurs OrgWatch (permission "OrgWatch - Accès Utilisateur" ou "OrgWatch - Accès Admin").'
        + ' Un administrateur doit d\'abord vous donner accès depuis l\'onglet Admin.'
        + ' / Reserved for OrgWatch users ("OrgWatch - User Access" or "OrgWatch - Admin Access" permission).'
        + ' An administrator must first grant you access from the Admin tab.';
    // Nombre d'exports lus pour construire l'historique. Chaque CSV est chargé
    // en mémoire (VersionData) : monter ce chiffre rapproche du plafond de heap
    // synchrone (6 Mo). Les fichiers lus sont les plus récents (tri DESC).
    private static final Integer HISTORY_FILE_LIMIT = 1000;

    @AuraEnabled(cacheable=true)
    public static Map<String, List<DataPoint>> getLimitsHistory() {
        assertOrgWatchAccess();
        return getLimitsHistoryInternal(null);
    }

    /**
     * Même historique, mais restreint aux exports créés depuis `cutoff`.
     * Utilisé par le batch d'alerting (fenêtre glissante des dernières 24h).
     */
    public static Map<String, List<DataPoint>> getLimitsHistorySince(DateTime cutoff) {
        return getLimitsHistoryInternal(cutoff);
    }

    /**
     * Expose côté client si l'utilisateur courant a le Permission Set
     * "OrgWatch - Admin", pour n'afficher l'onglet Admin qu'aux personnes
     * habilitées.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean isAdminUser() {
        return hasOrgWatchAdminPermission();
    }

    /**
     * Expose côté client si l'utilisateur courant a accès à OrgWatch tout
     * court (Permission Set "OrgWatch - Utilisateur" ou "OrgWatch - Admin"),
     * pour que le composant n'affiche AUCUN onglet à quelqu'un qui n'y a pas
     * droit. Volontairement la seule méthode non protégée par
     * assertOrgWatchAccess() : c'est précisément la question que pose un
     * utilisateur potentiellement non habilité. Sans elle, le composant
     * affichait ses onglets Monitoring/Alertes à tout le monde, les appels
     * de données échouant seulement une fois à l'intérieur.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean hasOrgWatchAccessForCurrentUser() {
        return hasOrgWatchAccess();
    }

    /**
     * Ré-évaluation des droits de l'appelant, volontairement NON mise en
     * cache : à utiliser juste après qu'il a modifié ses propres Permission
     * Sets depuis l'onglet Admin (il peut retirer le sien). isAdminUser() et
     * hasOrgWatchAccessForCurrentUser() sont cacheable=true, un appel
     * impératif juste après le changement renverrait l'état d'avant, et
     * l'interface resterait sur un onglet Admin devenu inaccessible.
     */
    @AuraEnabled
    public static AccessState getMyAccessState() {
        AccessState state = new AccessState();
        state.hasAccess = hasOrgWatchAccess();
        state.isAdmin = hasOrgWatchAdminPermission();
        return state;
    }

    public class AccessState {
        @AuraEnabled public Boolean hasAccess = false;
        @AuraEnabled public Boolean isAdmin = false;
    }

    /**
     * Qui sont les administrateurs OrgWatch de cette org, et par quel
     * Permission Set on le devient.
     *
     * Volontairement dans cette classe et non dans OrgWatchAdminController :
     * la cible est justement l'utilisateur NON-admin, qui doit pouvoir savoir
     * à qui s'adresser pour faire changer un réglage global (l'heure d'envoi
     * du récapitulatif, par exemple). Il n'a pas accès à
     * OrgWatchAdminController, réservé au Permission Set "OrgWatch - Admin".
     *
     * Le libellé du Permission Set est lu dans l'org plutôt que codé en dur :
     * un client peut l'avoir renommé.
     */
    @AuraEnabled(cacheable=true)
    public static AdminDirectory getAdminDirectory() {
        assertOrgWatchAccess();
        AdminDirectory directory = new AdminDirectory();
        directory.permissionSetApiName = ADMIN_PERMISSION_SET;

        List<PermissionSet> permissionSets = [
            SELECT Id, Label FROM PermissionSet WHERE Name = :ADMIN_PERMISSION_SET LIMIT 1
        ];
        if (permissionSets.isEmpty()) {
            return directory;
        }
        directory.permissionSetLabel = permissionSets[0].Label;

        Set<Id> assigneeIds = new Set<Id>();
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId
            FROM PermissionSetAssignment
            WHERE PermissionSetId = :permissionSets[0].Id
        ]) {
            assigneeIds.add(psa.AssigneeId);
        }
        if (assigneeIds.isEmpty()) {
            return directory;
        }

        for (User u : [
            SELECT Id, Name, Email
            FROM User
            WHERE Id IN :assigneeIds
            AND IsActive = true
            ORDER BY Name
            LIMIT 200
        ]) {
            AdminContact contact = new AdminContact();
            contact.userId = u.Id;
            contact.name = u.Name;
            contact.email = u.Email;
            directory.admins.add(contact);
        }

        return directory;
    }

    public class AdminDirectory {
        @AuraEnabled public List<AdminContact> admins = new List<AdminContact>();
        @AuraEnabled public String permissionSetLabel;
        @AuraEnabled public String permissionSetApiName;
    }

    public class AdminContact {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
    }

    /**
     * Nom de la bibliothèque de fichiers utilisée par OrgWatch. Source unique
     * de vérité : les autres classes de l'outil doivent l'obtenir ici plutôt
     * que de redéclarer la constante (elle l'est encore dans OrgWatchExporter,
     * OrgWatchPurgeController et OrgWatchAdminController - à consolider).
     */
    public static String getLibraryName() {
        return LIBRARY_NAME;
    }

    /**
     * Garde-fou serveur partagé par toutes les actions qui touchent l'org
     * entière (purge de l'historique, création/suppression de jobs planifiés)
     * et non les seules préférences de l'appelant. Masquer le bouton côté
     * client ne suffit pas : une méthode @AuraEnabled reste appelable
     * directement par n'importe quel utilisateur ayant accès à la classe.
     */
    public static void assertOrgWatchAdmin() {
        if (!hasOrgWatchAdminPermission()) {
            throw new AuraHandledException(ADMIN_REQUIRED_MESSAGE);
        }
    }

    /**
     * Garde-fou serveur pour les actions accessibles à TOUT utilisateur
     * OrgWatch (consultation du monitoring, gestion de ses propres alertes) -
     * distinct de assertOrgWatchAdmin() qui protège les actions réservées aux
     * administrateurs. Sans ce contrôle, un utilisateur authentifié sans
     * aucun des deux Permission Sets pouvait quand même appeler ces méthodes
     * @AuraEnabled directement (accès à l'app constaté sans PS assignée).
     */
    public static void assertOrgWatchAccess() {
        if (!hasOrgWatchAccess()) {
            throw new AuraHandledException(ACCESS_REQUIRED_MESSAGE);
        }
    }

    /**
     * Le point d'injection `adminCheckOverrideForTests` évite de faire
     * dépendre la suite de tests des Permission Sets réellement assignés dans
     * l'org qui l'exécute : les tests de la purge et de la planification
     * doivent valider leur propre logique, pas l'attribution des droits, et
     * doivent passer aussi bien dans une scratch org de packaging que dans un
     * sandbox. Le contrôle réel reste seul actif en production : un membre
     * @TestVisible n'est accessible qu'en contexte de test.
     */
    @TestVisible
    private static Boolean adminCheckOverrideForTests = null;

    /**
     * Même principe que `adminCheckOverrideForTests`, pour le contrôle
     * d'accès de base. Contrairement à celui-ci, quand aucun override n'est
     * positionné en contexte de test, on autorise par défaut : la grande
     * majorité des tests existants valident la logique métier de ces méthodes
     * (historique, préférences...) et n'ont pas vocation à revalider
     * l'attribution des Permission Sets - seul un test dédié positionne
     * explicitement `false` pour éprouver le rejet. En production,
     * Test.isRunningTest() est toujours faux : seul le contrôle réel
     * (attribution effective du Permission Set) s'applique.
     */
    @TestVisible
    private static Boolean accessCheckOverrideForTests = null;

    private static Boolean hasOrgWatchAccess() {
        if (Test.isRunningTest()) {
            return accessCheckOverrideForTests != null ? accessCheckOverrideForTests : true;
        }
        return hasOrgWatchAccessForUser(UserInfo.getUserId());
    }

    /**
     * Le contrôle réel, isolé sur un utilisateur explicite pour qu'un test
     * puisse l'éprouver sur de vraies attributions de Permission Set : le
     * court-circuit ci-dessus empêche sinon d'exercer cette requête en
     * contexte de test, et c'est exactement ce qui a laissé passer l'absence
     * de contrôle d'accès. L'un OU l'autre des deux Permission Sets suffit :
     * un administrateur OrgWatch a nécessairement accès aux fonctionnalités
     * standard sans qu'on ait à lui attribuer les deux.
     */
    @TestVisible
    private static Boolean hasOrgWatchAccessForUser(Id userId) {
        return !([
            SELECT Id
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId
            AND PermissionSet.Name IN (:USER_PERMISSION_SET, :ADMIN_PERMISSION_SET)
            LIMIT 1
        ]).isEmpty();
    }

    /**
     * Vérifie directement l'attribution du Permission Set "OrgWatch - Admin",
     * plutôt que FeatureManagement.checkPermission() sur la Custom Permission
     * associée : cette dernière reflète TOUTE source d'octroi, y compris un
     * profil sur lequel elle aurait été cochée manuellement dans Configuration
     * (hors du contrôle du package). C'est exactement ce qui a donné accès
     * admin à l'ensemble des utilisateurs d'une org sans qu'aucun n'ait la PS,
     * ce contrôle est donc la seule source de vérité désormais.
     */
    private static Boolean hasOrgWatchAdminPermission() {
        if (Test.isRunningTest() && adminCheckOverrideForTests != null) {
            return adminCheckOverrideForTests;
        }
        return !([
            SELECT Id
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
            AND PermissionSet.Name = :ADMIN_PERMISSION_SET
            LIMIT 1
        ]).isEmpty();
    }

    private static Map<String, List<DataPoint>> getLimitsHistoryInternal(DateTime cutoff) {
        Map<String, List<DataPoint>> historyMap = new Map<String, List<DataPoint>>();

        // 1. Récupérer l'ID de la bibliothèque "OrgWatch Reporting"
        List<ContentWorkspace> wsList = [SELECT Id FROM ContentWorkspace WHERE Name = :LIBRARY_NAME LIMIT 1];
        if (wsList.isEmpty()) {
            return historyMap;
        }

        // 2. Récupérer les IDs des documents présents dans cette bibliothèque
        List<ContentDocumentLink> links = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :wsList[0].Id];

        Set<Id> docIds = new Set<Id>();
        for(ContentDocumentLink cdl : links) {
            docIds.add(cdl.ContentDocumentId);
        }

        // 3. Récupérer les versions de fichiers (CSV) correspondantes.
        // Tri DESC : au-delà de HISTORY_FILE_LIMIT exports, ce sont les plus
        // RÉCENTS qu'il faut garder (un tri ASC renverrait les plus anciens et
        // le graphe se figerait sur les premiers jours suivant l'installation).
        List<ContentVersion> cvList;
        if (cutoff != null) {
            cvList = [
                SELECT VersionData, CreatedDate, Title
                FROM ContentVersion
                WHERE ContentDocumentId IN :docIds
                AND IsLatest = true
                AND FileExtension = 'csv'
                AND Title LIKE 'OrgWatch_Export_%'
                AND CreatedDate >= :cutoff
                ORDER BY CreatedDate DESC
                LIMIT :HISTORY_FILE_LIMIT
            ];
        } else {
            cvList = [
                SELECT VersionData, CreatedDate, Title
                FROM ContentVersion
                WHERE ContentDocumentId IN :docIds
                AND IsLatest = true
                AND FileExtension = 'csv'
                AND Title LIKE 'OrgWatch_Export_%'
                ORDER BY CreatedDate DESC
                LIMIT :HISTORY_FILE_LIMIT
            ];
        }

        // Reparcouru à l'envers pour rendre les points de mesure dans l'ordre
        // chronologique attendu par les graphes.
        for (Integer fileIndex = cvList.size() - 1; fileIndex >= 0; fileIndex--) {
            ContentVersion cv = cvList[fileIndex];
            try {
                String csvText = cv.VersionData.toString();
                DateTime fileDate = cv.CreatedDate;

                List<String> lines = csvText.split('\n');
                for (Integer i = 1; i < lines.size(); i++) {
                    String line = lines[i].trim();
                    if(String.isBlank(line)) continue;

                    List<String> columns = line.split(';');
                    String limitName;
                    Long currentVal;
                    Long maxVal;
                    if (columns.size() >= 5) {
                        // Format actuel de l'exporteur : Catégorie;Nom de la Limite;Valeur Actuelle;Maximum;Consommation (%)
                        limitName = columns[1].trim();
                        currentVal = Long.valueOf(columns[2].trim());
                        maxVal = Long.valueOf(columns[3].trim());
                    } else if (columns.size() >= 3) {
                        // Format historique/tests, sans colonne Catégorie : Nom;Valeur;Maximum
                        limitName = columns[0].trim();
                        currentVal = Long.valueOf(columns[1].trim());
                        maxVal = Long.valueOf(columns[2].trim());
                    } else {
                        continue;
                    }

                    if (!historyMap.containsKey(limitName)) {
                        historyMap.put(limitName, new List<DataPoint>());
                    }
                    historyMap.get(limitName).add(new DataPoint(fileDate, currentVal, maxVal));
                }
            } catch(Exception e) {
                System.debug('Erreur lors du parsing d\'un fichier : ' + e.getMessage());
            }
        }
        return historyMap;
    }

    @AuraEnabled
    public static List<MetricSnapshot> getSnapshotAtTime(DateTime targetTimestamp) {
        assertOrgWatchAccess();
        List<MetricSnapshot> snapshotList = new List<MetricSnapshot>();

        List<ContentWorkspace> wsList = [SELECT Id FROM ContentWorkspace WHERE Name = :LIBRARY_NAME LIMIT 1];
        if (wsList.isEmpty()) {
            return snapshotList;
        }

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :wsList[0].Id
        ];

        Set<Id> docIds = new Set<Id>();
        for(ContentDocumentLink cdl : links) {
            docIds.add(cdl.ContentDocumentId);
        }

        List<ContentVersion> cvList = [
            SELECT VersionData, CreatedDate, Title
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds
            AND IsLatest = true
            AND FileExtension = 'csv'
            AND Title LIKE 'OrgWatch_Export_%'
            AND CreatedDate <= :targetTimestamp
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (cvList.isEmpty()) {
            return snapshotList;
        }

        ContentVersion cv = cvList[0];
        try {
            String csvText = cv.VersionData.toString();

            List<String> lines = csvText.split('\n');
            for (Integer i = 1; i < lines.size(); i++) {
                String line = lines[i].trim();
                if(String.isBlank(line)) continue;

                List<String> columns = line.split(';');
                String limitName;
                Long currentVal;
                Long maxVal;
                if (columns.size() >= 5) {
                    // Format actuel de l'exporteur : Catégorie;Nom de la Limite;Valeur Actuelle;Maximum;Consommation (%)
                    limitName = columns[1].trim();
                    currentVal = Long.valueOf(columns[2].trim());
                    maxVal = Long.valueOf(columns[3].trim());
                } else if (columns.size() >= 3) {
                    // Format historique/tests, sans colonne Catégorie : Nom;Valeur;Maximum
                    limitName = columns[0].trim();
                    currentVal = Long.valueOf(columns[1].trim());
                    maxVal = Long.valueOf(columns[2].trim());
                } else {
                    continue;
                }

                snapshotList.add(new MetricSnapshot(limitName, currentVal, maxVal));
            }
        } catch(Exception e) {
            System.debug('Erreur lors du parsing du snapshot : ' + e.getMessage());
        }

        snapshotList.sort();

        return snapshotList;
    }

    @AuraEnabled(cacheable=true)
    public static String getUserPreferences() {
        assertOrgWatchAccess();
        UserPreferences prefs = readAllPreferences().get(UserInfo.getUserId());
        return prefs != null ? prefs.hiddenMetrics : '';
    }

    @AuraEnabled
    public static String saveUserPreferences(String hiddenMetricsList) {
        assertOrgWatchAccess();
        return saveUserPreferencesFull(hiddenMetricsList, null, null);
    }

    /**
     * Écrivain central du fichier de préférences : `null` sur un paramètre
     * signifie "ne pas modifier cette colonne pour l'utilisateur courant"
     * (permet à OrgWatchAlertController de ne toucher que les colonnes
     * d'alerting sans écraser les métriques masquées, et inversement).
     */
    public static String saveUserPreferencesFull(String hiddenMetrics, String metricThresholds, String emailMode) {
        return writePreferencesForUser(UserInfo.getUserId(), hiddenMetrics, metricThresholds, emailMode, null);
    }

    /**
     * Enregistre uniquement la langue préférée de l'utilisateur courant (choix
     * fait côté client dans le sélecteur FR/EN). Persisté côté serveur - en plus
     * du localStorage qui pilote l'UI - car le batch d'alerting quotidien tourne
     * sans contexte navigateur et ne peut lire que ce qui est dans ce fichier.
     */
    @AuraEnabled
    public static String saveLanguagePreference(String language) {
        assertOrgWatchAccess();
        return writePreferencesForUser(UserInfo.getUserId(), null, null, null, language);
    }

    /**
     * Même écrivain, mais pour un utilisateur cible explicite plutôt que
     * l'utilisateur courant : utilisé par OrgWatchAdminController pour
     * qu'un admin puisse désactiver les alertes d'un autre utilisateur.
     */
    public static String writePreferencesForUser(Id targetUserId, String hiddenMetrics, String metricThresholds, String emailMode, String language) {
        try {
            String currentUserId = targetUserId;
            DateTime now = DateTime.now();

            if (hiddenMetrics != null) {
                hiddenMetrics = hiddenMetrics.replace(';', ',').replace('\n', '').replace('\r', '');
            }
            if (metricThresholds != null) {
                metricThresholds = metricThresholds.replace(';', ',').replace('\n', '').replace('\r', '');
            }
            if (emailMode != null) {
                emailMode = emailMode.replace(';', '').replace(',', '').replace('\n', '').replace('\r', '');
            }
            if (language != null) {
                language = language.replace(';', '').replace(',', '').replace('\n', '').replace('\r', '');
            }

            ContentWorkspace ws = getOrCreateLibrary();

            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :ws.Id
            ];

            Set<Id> docIds = new Set<Id>();
            for(ContentDocumentLink cdl : links) {
                docIds.add(cdl.ContentDocumentId);
            }

            List<ContentVersion> existingConfigs = [
                SELECT ContentDocumentId, VersionData
                FROM ContentVersion
                WHERE ContentDocumentId IN :docIds
                AND Title = :CONFIG_FILENAME
                AND IsLatest = true
                LIMIT 1
            ];

            Id existingDocId = null;
            Map<String, UserPreferences> allPrefs = new Map<String, UserPreferences>();

            if (!existingConfigs.isEmpty()) {
                existingDocId = existingConfigs[0].ContentDocumentId;
                try {
                    allPrefs = parsePreferencesCsv(existingConfigs[0].VersionData.toString());
                } catch (Exception parseEx) {
                    System.debug('Error parsing existing config, will recreate: ' + parseEx.getMessage());
                    allPrefs = new Map<String, UserPreferences>();
                }
            }

            UserPreferences current = allPrefs.get(currentUserId);
            if (current == null) {
                current = new UserPreferences();
                current.userId = currentUserId;
            }
            if (hiddenMetrics != null) current.hiddenMetrics = hiddenMetrics;
            if (metricThresholds != null) current.metricThresholds = metricThresholds;
            if (emailMode != null) current.emailMode = emailMode;
            if (language != null) current.language = language;
            allPrefs.put(currentUserId, current);

            String csvContent = 'UserId;HiddenMetrics;MetricThresholds;EmailMode;Language;LastModified\n';
            for (String userId : allPrefs.keySet()) {
                UserPreferences p = allPrefs.get(userId);
                csvContent += userId + ';' + p.hiddenMetrics + ';' + p.metricThresholds + ';' + p.emailMode + ';' + p.language
                    + ';' + now.formatGMT('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') + '\n';
            }

            ContentVersion cv = new ContentVersion();
            cv.Title = CONFIG_FILENAME;
            cv.PathOnClient = CONFIG_FILENAME;
            cv.VersionData = Blob.valueOf(csvContent);
            cv.IsMajorVersion = true;

            if (existingDocId != null) {
                cv.ContentDocumentId = existingDocId;
            }

            insert cv;

            if (existingDocId == null) {
                ContentVersion insertedVersion = [
                    SELECT ContentDocumentId
                    FROM ContentVersion
                    WHERE Id = :cv.Id
                    LIMIT 1
                ];

                ContentDocumentLink cdl = new ContentDocumentLink();
                cdl.ContentDocumentId = insertedVersion.ContentDocumentId;
                cdl.LinkedEntityId = ws.Id;
                cdl.ShareType = 'I';
                cdl.Visibility = 'AllUsers';
                insert cdl;
            }

            return 'SUCCESS';

        } catch(Exception e) {
            System.debug('Error saving user preferences: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            return 'ERROR: ' + e.getMessage();
        }
    }

    /**
     * Supprime entièrement la ligne de préférences d'un utilisateur (pas
     * seulement ses seuils, comme writePreferencesForUser(...,'',...)) :
     * appelé quand un admin retire tout accès OrgWatch (plus aucune PS), un
     * utilisateur sans PS n'est plus un utilisateur de l'app, ses données
     * (métriques masquées, seuils, langue) n'ont plus lieu d'exister.
     */
    public static String removePreferencesForUser(Id targetUserId) {
        try {
            ContentWorkspace ws = getOrCreateLibrary();

            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :ws.Id
            ];

            Set<Id> docIds = new Set<Id>();
            for (ContentDocumentLink cdl : links) {
                docIds.add(cdl.ContentDocumentId);
            }

            List<ContentVersion> existingConfigs = [
                SELECT ContentDocumentId, VersionData
                FROM ContentVersion
                WHERE ContentDocumentId IN :docIds
                AND Title = :CONFIG_FILENAME
                AND IsLatest = true
                LIMIT 1
            ];

            if (existingConfigs.isEmpty()) {
                return 'SUCCESS';
            }

            Id existingDocId = existingConfigs[0].ContentDocumentId;
            Map<String, UserPreferences> allPrefs;
            try {
                allPrefs = parsePreferencesCsv(existingConfigs[0].VersionData.toString());
            } catch (Exception parseEx) {
                System.debug('Error parsing existing config: ' + parseEx.getMessage());
                return 'SUCCESS';
            }

            if (!allPrefs.containsKey(targetUserId)) {
                return 'SUCCESS';
            }
            allPrefs.remove(targetUserId);

            DateTime now = DateTime.now();
            String csvContent = 'UserId;HiddenMetrics;MetricThresholds;EmailMode;Language;LastModified\n';
            for (String userId : allPrefs.keySet()) {
                UserPreferences p = allPrefs.get(userId);
                csvContent += userId + ';' + p.hiddenMetrics + ';' + p.metricThresholds + ';' + p.emailMode + ';' + p.language
                    + ';' + now.formatGMT('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') + '\n';
            }

            ContentVersion cv = new ContentVersion();
            cv.Title = CONFIG_FILENAME;
            cv.PathOnClient = CONFIG_FILENAME;
            cv.VersionData = Blob.valueOf(csvContent);
            cv.IsMajorVersion = true;
            cv.ContentDocumentId = existingDocId;

            insert cv;

            return 'SUCCESS';
        } catch (Exception e) {
            System.debug('Error removing user preferences: ' + e.getMessage());
            return 'ERROR: ' + e.getMessage();
        }
    }

    private static ContentWorkspace getOrCreateLibrary() {
        List<ContentWorkspace> existing = [SELECT Id FROM ContentWorkspace WHERE Name = :LIBRARY_NAME LIMIT 1];
        if (!existing.isEmpty()) {
            return existing[0];
        }
        ContentWorkspace ws = new ContentWorkspace(Name = LIBRARY_NAME);
        // ContentWorkspace est un "setup object" pour Apex : l'insérer puis
        // insérer un ContentVersion dans la même transaction lève
        // MIXED_DML_OPERATION. runAs isole la création dans son propre
        // contexte DML (uniquement utilisable en contexte de test).
        if (Test.isRunningTest()) {
            System.runAs(new User(Id = UserInfo.getUserId())) {
                insert ws;
            }
        } else {
            insert ws;
        }
        return ws;
    }

    /**
     * Lit le fichier de préférences pour tous les utilisateurs. Utilisé par
     * l'onglet Alertes/le batch d'alerting pour savoir qui a des seuils actifs.
     * Ne lève jamais d'exception : fichier absent/corrompu -> map vide.
     */
    public static Map<String, UserPreferences> readAllPreferences() {
        Map<String, UserPreferences> result = new Map<String, UserPreferences>();
        try {
            ContentWorkspace ws = [SELECT Id FROM ContentWorkspace WHERE Name = :LIBRARY_NAME LIMIT 1];

            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :ws.Id
            ];

            Set<Id> docIds = new Set<Id>();
            for(ContentDocumentLink cdl : links) {
                docIds.add(cdl.ContentDocumentId);
            }

            List<ContentVersion> configFiles = [
                SELECT VersionData
                FROM ContentVersion
                WHERE ContentDocumentId IN :docIds
                AND Title = :CONFIG_FILENAME
                AND IsLatest = true
                LIMIT 1
            ];

            if (configFiles.isEmpty()) {
                return result;
            }

            result = parsePreferencesCsv(configFiles[0].VersionData.toString());
        } catch (Exception e) {
            System.debug('Error reading preferences: ' + e.getMessage());
        }
        return result;
    }

    private static Map<String, UserPreferences> parsePreferencesCsv(String csvContent) {
        Map<String, UserPreferences> result = new Map<String, UserPreferences>();
        if (String.isBlank(csvContent)) {
            return result;
        }

        List<String> lines = csvContent.split('\n');

        for (Integer i = 1; i < lines.size(); i++) {
            try {
                String line = lines[i].trim();
                if (String.isBlank(line)) continue;

                List<String> columns = line.split(';');
                if (columns.size() < 2) continue;

                String lineUserId = columns[0].trim();
                if (lineUserId.length() != 15 && lineUserId.length() != 18) continue;

                UserPreferences p = new UserPreferences();
                p.userId = lineUserId;
                p.hiddenMetrics = columns[1].trim();
                // Format actuel : UserId;HiddenMetrics;MetricThresholds;EmailMode;Language;LastModified
                // (6 colonnes). Une ligne écrite avant l'ajout de la langue n'en a que
                // 5 (UserId;HiddenMetrics;MetricThresholds;EmailMode;LastModified) : pas
                // de langue enregistrée -> 'fr' par défaut. Une ligne encore plus ancienne
                // n'a que 3 colonnes (UserId;HiddenMetrics;LastModified) : sa 3e colonne
                // est LastModified, pas MetricThresholds - il ne faut pas la lire comme telle.
                if (columns.size() >= 6) {
                    p.metricThresholds = columns[2].trim();
                    p.emailMode = String.isNotBlank(columns[3].trim()) ? columns[3].trim() : DEFAULT_EMAIL_MODE;
                    p.language = String.isNotBlank(columns[4].trim()) ? columns[4].trim() : DEFAULT_LANGUAGE;
                } else if (columns.size() >= 5) {
                    p.metricThresholds = columns[2].trim();
                    p.emailMode = String.isNotBlank(columns[3].trim()) ? columns[3].trim() : DEFAULT_EMAIL_MODE;
                    p.language = DEFAULT_LANGUAGE;
                } else {
                    p.metricThresholds = '';
                    p.emailMode = DEFAULT_EMAIL_MODE;
                    p.language = DEFAULT_LANGUAGE;
                }

                result.put(lineUserId, p);
            } catch (Exception lineEx) {
                System.debug('Skipping corrupted preferences line: ' + lineEx.getMessage());
                continue;
            }
        }

        return result;
    }

    public class UserPreferences {
        @AuraEnabled public String userId;
        @AuraEnabled public String hiddenMetrics = '';
        @AuraEnabled public String metricThresholds = '';
        @AuraEnabled public String emailMode = DEFAULT_EMAIL_MODE;
        @AuraEnabled public String language = DEFAULT_LANGUAGE;
    }

    public class DataPoint {
        @AuraEnabled public DateTime timestamp;
        @AuraEnabled public Long current;
        @AuraEnabled public Long max;

        public DataPoint(DateTime ts, Long c, Long m) {
            this.timestamp = ts;
            this.current = c;
            this.max = m;
        }
    }

    public class MetricSnapshot implements Comparable {
        @AuraEnabled public String name;
        @AuraEnabled public Long current;
        @AuraEnabled public Long max;
        @AuraEnabled public Decimal percentage;

        public MetricSnapshot(String n, Long c, Long m) {
            this.name = n;
            this.current = c;
            this.max = m;
            this.percentage = m > 0 ? (Decimal.valueOf(c) / Decimal.valueOf(m) * 100).setScale(2) : 0;
        }

        public Integer compareTo(Object compareTo) {
            MetricSnapshot other = (MetricSnapshot) compareTo;
            if (this.percentage > other.percentage) return -1;
            if (this.percentage < other.percentage) return 1;
            return 0;
        }
    }
}