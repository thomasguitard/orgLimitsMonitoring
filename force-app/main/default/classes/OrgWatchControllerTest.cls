@isTest(isParallel=false)
private class OrgWatchControllerTest {

    private static Id setupLibraryWithFile(String title, String csvBody) {
        ContentWorkspace ws;
        List<ContentWorkspace> existing = [SELECT Id FROM ContentWorkspace WHERE Name = 'OrgWatch Reporting TEST' LIMIT 1];
        if (existing.isEmpty()) {
            ws = new ContentWorkspace(Name = 'OrgWatch Reporting TEST');
            // ContentWorkspace est un "setup object" pour Apex : l'insérer puis
            // insérer un ContentVersion dans la même transaction lève MIXED_DML_OPERATION.
            System.runAs(new User(Id = UserInfo.getUserId())) {
                insert ws;
            }
        } else {
            ws = existing[0];
        }

        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title + '.csv',
            VersionData = Blob.valueOf(csvBody),
            IsMajorVersion = true
        );
        insert cv;

        Id contentDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

        insert new ContentDocumentLink(
            ContentDocumentId = contentDocId,
            LinkedEntityId = ws.Id,
            ShareType = 'I',
            Visibility = 'AllUsers'
        );

        return ws.Id;
    }

    @isTest
    static void testGetLimitsHistoryAndSnapshot() {
        String csv = 'LimitName;Current;Max\nDataStorageMB;100;1000\nApiRequests;500;15000\n';
        setupLibraryWithFile('OrgWatch_Export_Test1', csv);

        Test.startTest();
        Map<String, List<OrgWatchController.DataPoint>> history = OrgWatchController.getLimitsHistory();
        List<OrgWatchController.MetricSnapshot> snapshot = OrgWatchController.getSnapshotAtTime(DateTime.now().addMinutes(1));
        Test.stopTest();

        System.assert(history.containsKey('DataStorageMB'));
        System.assert(history.containsKey('ApiRequests'));
        System.assertEquals(2, snapshot.size());
    }

    @isTest
    static void testGetUserPreferencesNoConfig() {
        // No config file exists yet
        String prefs = OrgWatchController.getUserPreferences();
        System.assertEquals('', prefs);
    }

    @isTest
    static void testSaveAndGetUserPreferences() {
        Test.startTest();
        String saveResult = OrgWatchController.saveUserPreferences('ApiRequests,DataStorageMB');
        String prefs = OrgWatchController.getUserPreferences();
        Test.stopTest();

        System.assertEquals('SUCCESS', saveResult);
        System.assertEquals('ApiRequests,DataStorageMB', prefs);
    }

    @isTest
    static void testSaveUserPreferencesOverwrite() {
        OrgWatchController.saveUserPreferences('MetricA');
        Test.startTest();
        String saveResult = OrgWatchController.saveUserPreferences('MetricB');
        String prefs = OrgWatchController.getUserPreferences();
        Test.stopTest();

        System.assertEquals('SUCCESS', saveResult);
        System.assertEquals('MetricB', prefs);
    }

    @isTest
    static void testSaveUserPreferencesFullDoesNotTouchOtherColumns() {
        Test.startTest();
        OrgWatchController.saveUserPreferencesFull('MetricA,MetricB', null, null);
        OrgWatchController.saveUserPreferencesFull(null, 'MetricC:80', 'Always');
        Test.stopTest();

        OrgWatchController.UserPreferences prefs = OrgWatchController.readAllPreferences().get(UserInfo.getUserId());
        System.assertNotEquals(null, prefs, 'Les préférences doivent être retrouvées');
        System.assertEquals('MetricA,MetricB', prefs.hiddenMetrics, 'HiddenMetrics ne doit pas avoir été touché par le 2e appel');
        System.assertEquals('MetricC:80', prefs.metricThresholds);
        System.assertEquals('Always', prefs.emailMode);
    }

    @isTest
    static void testReadAllPreferencesBackwardCompatibleWithOldThreeColumnFormat() {
        // Format d'avant l'ajout des colonnes d'alerting (MetricThresholds/EmailMode)
        String csv = 'UserId;HiddenMetrics;LastModified\n'
            + UserInfo.getUserId() + ';MetricA;2026-01-01T00:00:00Z\n';
        setupLibraryWithFile('OrgWatchUserPreferences.csv', csv);

        Map<String, OrgWatchController.UserPreferences> all = OrgWatchController.readAllPreferences();
        OrgWatchController.UserPreferences prefs = all.get(UserInfo.getUserId());

        System.assertNotEquals(null, prefs);
        System.assertEquals('MetricA', prefs.hiddenMetrics);
        System.assertEquals('', prefs.metricThresholds, 'Colonne absente sur une ancienne ligne -> valeur par défaut vide');
        System.assertEquals('OnlyOnBreach', prefs.emailMode, 'Colonne absente sur une ancienne ligne -> valeur par défaut');
    }

    @isTest
    static void testReadAllPreferencesBackwardCompatibleWithFiveColumnFormatDefaultsLanguageToFr() {
        // Format d'avant l'ajout de la colonne Language (5 colonnes) : c'est le
        // format des données réelles actuelles, la langue doit retomber sur 'fr'.
        String csv = 'UserId;HiddenMetrics;MetricThresholds;EmailMode;LastModified\n'
            + UserInfo.getUserId() + ';MetricA;MetricB:80;Always;2026-01-01T00:00:00Z\n';
        setupLibraryWithFile('OrgWatchUserPreferences.csv', csv);

        OrgWatchController.UserPreferences prefs = OrgWatchController.readAllPreferences().get(UserInfo.getUserId());

        System.assertNotEquals(null, prefs);
        System.assertEquals('MetricB:80', prefs.metricThresholds);
        System.assertEquals('fr', prefs.language, 'Colonne absente sur une ligne au format précédent -> fr par défaut');
    }

    @isTest
    static void testReadAllPreferencesReadsSixColumnFormatLanguage() {
        String csv = 'UserId;HiddenMetrics;MetricThresholds;EmailMode;Language;LastModified\n'
            + UserInfo.getUserId() + ';MetricA;MetricB:80;Always;en;2026-01-01T00:00:00Z\n';
        setupLibraryWithFile('OrgWatchUserPreferences.csv', csv);

        OrgWatchController.UserPreferences prefs = OrgWatchController.readAllPreferences().get(UserInfo.getUserId());

        System.assertNotEquals(null, prefs);
        System.assertEquals('en', prefs.language);
    }

    @isTest
    static void testSaveLanguagePreferenceDoesNotTouchOtherColumns() {
        Test.startTest();
        OrgWatchController.saveUserPreferencesFull('MetricA', 'MetricB:80', 'Always');
        String result = OrgWatchController.saveLanguagePreference('en');
        Test.stopTest();

        System.assertEquals('SUCCESS', result);

        OrgWatchController.UserPreferences prefs = OrgWatchController.readAllPreferences().get(UserInfo.getUserId());
        System.assertNotEquals(null, prefs);
        System.assertEquals('en', prefs.language);
        System.assertEquals('MetricA', prefs.hiddenMetrics, 'La langue ne doit pas écraser les autres colonnes');
        System.assertEquals('MetricB:80', prefs.metricThresholds);
        System.assertEquals('Always', prefs.emailMode);
    }

    @isTest
    static void testGetLimitsHistorySinceFiltersOldExports() {
        String csv = 'LimitName;Current;Max\nDataStorageMB;100;1000\n';
        setupLibraryWithFile('OrgWatch_Export_Test1', csv);

        Test.startTest();
        Map<String, List<OrgWatchController.DataPoint>> recentHistory =
            OrgWatchController.getLimitsHistorySince(DateTime.now().addDays(1));
        Test.stopTest();

        System.assertEquals(0, recentHistory.size(), 'Un cutoff dans le futur ne doit rien retenir');
    }

    @isTest
    static void testIsAdminUserDoesNotThrow() {
        Test.startTest();
        Boolean result = OrgWatchController.isAdminUser();
        Test.stopTest();

        System.assertNotEquals(null, result, 'isAdminUser doit toujours retourner true/false, jamais null');
    }

    /**
     * L'annuaire des admins est destiné aux utilisateurs NON-admins (savoir à
     * qui demander un changement de réglage global) : il doit donc rester
     * appelable sans la permission Admin, et nommer le Permission Set à
     * demander.
     */
    @isTest
    static void testAdminDirectoryListsAssigneesAndPermissionSet() {
        String uniqueSuffix = String.valueOf(Datetime.now().getTime());
        User futureAdmin = new User(
            FirstName = 'OrgWatch',
            LastName = 'DirAdmin',
            Email = 'orgwatch.dir@example.com.invalid',
            Username = 'orgwatch.dir' + uniqueSuffix + '@example.com.invalid',
            Alias = ('ow' + uniqueSuffix).right(8),
            TimeZoneSidKey = 'Europe/Paris',
            LocaleSidKey = 'fr_FR',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'fr',
            ProfileId = UserInfo.getProfileId(),
            IsActive = true
        );
        PermissionSet adminPs = [SELECT Id, Label FROM PermissionSet WHERE Name = 'OrgWatch_Admin' LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert futureAdmin;
            insert new PermissionSetAssignment(AssigneeId = futureAdmin.Id, PermissionSetId = adminPs.Id);
        }

        Test.startTest();
        OrgWatchController.AdminDirectory directory = OrgWatchController.getAdminDirectory();
        Test.stopTest();

        System.assertEquals('OrgWatch_Admin', directory.permissionSetApiName,
            'Le nom d\'API du Permission Set à demander doit être renvoyé pour être affiché à l\'utilisateur');
        System.assertEquals(adminPs.Label, directory.permissionSetLabel,
            'Le libellé doit être lu dans l\'org (un client peut avoir renommé le Permission Set)');

        Boolean found = false;
        for (OrgWatchController.AdminContact contact : directory.admins) {
            if (contact.userId == futureAdmin.Id) {
                found = true;
                System.assertNotEquals(null, contact.name, 'Le nom de l\'admin doit être renseigné');
            }
        }
        System.assert(found, 'Un utilisateur venant de recevoir OrgWatch_Admin doit apparaître dans l\'annuaire');
    }

    /**
     * Reproduit le bug constaté en préprod : un utilisateur authentifié sans
     * aucun des deux Permission Sets OrgWatch pouvait quand même appeler ces
     * méthodes @AuraEnabled directement (aucun contrôle d'accès de base
     * n'existait). `accessCheckOverrideForTests` simule ce cas sans dépendre
     * des Permission Sets réellement assignés dans l'org qui exécute le test
     * (cf. commentaire sur le champ lui-même).
     */
    @isTest
    static void testAssertOrgWatchAccessRejectsUserWithoutAnyPermissionSet() {
        OrgWatchController.accessCheckOverrideForTests = false;

        // AuraHandledException.getMessage() renvoie "Script-thrown exception"
        // (pas le message réel) tant que l'exception n'a pas franchi la
        // frontière client/serveur : comme le reste de cette suite de tests
        // (cf. testAssertAdminRejectsNonAdmin), on vérifie donc uniquement
        // qu'elle est bien levée, pas son contenu.
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            OrgWatchController.getLimitsHistory();
            System.assert(false, 'Une AuraHandledException aurait dû être levée');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        OrgWatchController.accessCheckOverrideForTests = null;

        System.assert(exceptionThrown, 'Un utilisateur sans OrgWatch_User ni OrgWatch_Admin doit être rejeté');
    }

    /**
     * Ce que le composant interroge pour décider d'afficher ses onglets ou
     * seulement le message d'accès refusé : contrairement aux autres méthodes,
     * elle ne doit jamais lever d'exception (c'est la question posée par un
     * utilisateur justement peut-être non habilité), mais bien répondre false.
     */
    @isTest
    static void testHasOrgWatchAccessForCurrentUserReflectsPermission() {
        OrgWatchController.accessCheckOverrideForTests = false;
        Boolean withoutPermissionSet = OrgWatchController.hasOrgWatchAccessForCurrentUser();

        OrgWatchController.accessCheckOverrideForTests = true;
        Boolean withPermissionSet = OrgWatchController.hasOrgWatchAccessForCurrentUser();

        OrgWatchController.accessCheckOverrideForTests = null;

        System.assertEquals(false, withoutPermissionSet,
            'Sans Permission Set, le composant ne doit afficher aucun onglet');
        System.assertEquals(true, withPermissionSet,
            'Avec un Permission Set OrgWatch, le composant doit s\'afficher normalement');
    }

    private static User createUserWithoutOrgWatchAccess(String lastName) {
        String uniqueSuffix = String.valueOf(Datetime.now().getTime()) + lastName;
        User u = new User(
            FirstName = 'OrgWatch',
            LastName = lastName,
            Email = 'orgwatch.access@example.com.invalid',
            Username = 'orgwatch.access.' + uniqueSuffix + '@example.com.invalid',
            Alias = ('ow' + uniqueSuffix).right(8),
            TimeZoneSidKey = 'Europe/Paris',
            LocaleSidKey = 'fr_FR',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'fr',
            ProfileId = UserInfo.getProfileId(),
            IsActive = true
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }

    /**
     * LE test qui manquait, et sans lequel le trou d'accès est passé deux
     * fois en préprod : il éprouve la VRAIE requête d'attribution de
     * Permission Set, sur de vraies PermissionSetAssignment, sans passer par
     * l'override de test. Un utilisateur sans aucun des deux Permission Sets
     * ne doit pas avoir accès, quel que soit son profil - c'est précisément
     * le cas constaté (accès via un profil, hors de tout Permission Set).
     */
    @isTest
    static void testRealPermissionSetCheckDeniesUserWithoutAnyOrgWatchPermissionSet() {
        User noAccess = createUserWithoutOrgWatchAccess('NoPS');
        User userPs = createUserWithoutOrgWatchAccess('UserPS');
        User adminPs = createUserWithoutOrgWatchAccess('AdminPS');

        PermissionSet psUser = [SELECT Id FROM PermissionSet WHERE Name = 'OrgWatch_User' LIMIT 1];
        PermissionSet psAdmin = [SELECT Id FROM PermissionSet WHERE Name = 'OrgWatch_Admin' LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<PermissionSetAssignment>{
                new PermissionSetAssignment(AssigneeId = userPs.Id, PermissionSetId = psUser.Id),
                new PermissionSetAssignment(AssigneeId = adminPs.Id, PermissionSetId = psAdmin.Id)
            };
        }

        Test.startTest();
        Boolean noAccessResult = OrgWatchController.hasOrgWatchAccessForUser(noAccess.Id);
        Boolean userPsResult = OrgWatchController.hasOrgWatchAccessForUser(userPs.Id);
        Boolean adminPsResult = OrgWatchController.hasOrgWatchAccessForUser(adminPs.Id);
        Test.stopTest();

        System.assertEquals(false, noAccessResult,
            'Un utilisateur sans aucun Permission Set OrgWatch ne doit JAMAIS avoir accès');
        System.assertEquals(true, userPsResult,
            'Le Permission Set OrgWatch_User doit donner accès');
        System.assertEquals(true, adminPsResult,
            'Le Permission Set OrgWatch_Admin doit suffire, sans exiger aussi OrgWatch_User');
    }
}