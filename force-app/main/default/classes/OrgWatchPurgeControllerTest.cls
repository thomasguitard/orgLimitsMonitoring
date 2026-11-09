@IsTest(isParallel=false)
private class OrgWatchPurgeControllerTest {

    /**
     * La purge et la planification sont désormais réservées aux admins
     * OrgWatch côté serveur. Ces tests valident la logique métier, pas
     * l'attribution des droits : on neutralise donc le contrôle de permission
     * pour ne pas dépendre des Permission Sets réellement assignés dans l'org
     * qui exécute la suite (sandbox, scratch org de packaging...). Le refus
     * d'un non-admin est vérifié séparément, via le contrôle réel.
     */
    private static void grantOrgWatchAdminForTest() {
        OrgWatchController.adminCheckOverrideForTests = true;
    }

    private static void setupLibraryWithFile(String title) {
        List<ContentWorkspace> existing = [SELECT Id FROM ContentWorkspace WHERE Name = 'OrgWatch Reporting TEST' LIMIT 1];
        ContentWorkspace ws;
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
            VersionData = Blob.valueOf('Nom;Val;Max\nTest;1;10\n'),
            IsMajorVersion = true
        );
        insert cv;

        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

        insert new ContentDocumentLink(
            ContentDocumentId = docId,
            LinkedEntityId = ws.Id,
            ShareType = 'I',
            Visibility = 'AllUsers'
        );
    }

    @IsTest
    static void testGetDataFilesInfoEmpty() {
        grantOrgWatchAdminForTest();
        List<OrgWatchPurgeController.DataFileInfo> result = OrgWatchPurgeController.getDataFilesInfo();
        System.assertEquals(0, result.size(), 'Aucune librairie, donc aucun fichier');
    }

    @IsTest
    static void testGetDataFilesInfoAndPurge() {
        grantOrgWatchAdminForTest();
        setupLibraryWithFile('OrgWatch_Export_Old');

        Test.startTest();
        List<OrgWatchPurgeController.DataFileInfo> files = OrgWatchPurgeController.getDataFilesInfo();
        System.assertEquals(1, files.size(), 'Le fichier d\'export doit être trouvé');

        OrgWatchPurgeController.PurgeResult res = OrgWatchPurgeController.purgeFilesOlderThan(DateTime.now().addDays(1));
        Test.stopTest();

        System.assertEquals(1, res.deletedCount, 'Le fichier doit être supprimé');
        System.assertEquals(0, res.failedCount, 'Aucun échec attendu');

        List<OrgWatchPurgeController.DataFileInfo> afterPurge = OrgWatchPurgeController.getDataFilesInfo();
        System.assertEquals(0, afterPurge.size(), 'Le fichier doit avoir été purgé');
    }

    @IsTest
    static void testPurgeDoesNotDeleteRecentFiles() {
        grantOrgWatchAdminForTest();
        setupLibraryWithFile('OrgWatch_Export_Recent');

        OrgWatchPurgeController.PurgeResult res = OrgWatchPurgeController.purgeFilesOlderThan(DateTime.now().addDays(-1));

        System.assertEquals(0, res.deletedCount, 'Un fichier récent ne doit pas être purgé');

        List<OrgWatchPurgeController.DataFileInfo> files = OrgWatchPurgeController.getDataFilesInfo();
        System.assertEquals(1, files.size(), 'Le fichier récent doit toujours être présent');
    }

    @IsTest
    static void testPurgeNoCutoffDate() {
        grantOrgWatchAdminForTest();
        OrgWatchPurgeController.PurgeResult res = OrgWatchPurgeController.purgeFilesOlderThan(null);
        System.assert(!res.errors.isEmpty(), 'Une erreur doit être remontée sans date de coupure');
    }

    // Note : pas de test "purge sans librairie" - ContentWorkspace n'est pas
    // isolé entre les exécutions de test dans cet org (une vraie librairie
    // "OrgWatch Reporting TEST" peut déjà exister suite à un test précédent),
    // donc ce cas ne peut pas être testé de façon déterministe.

    @IsTest
    static void testPurgeScheduleLifecycle() {
        grantOrgWatchAdminForTest();
        // Nettoyage défensif : CronTrigger n'est pas isolé entre les tests dans
        // cet org, un job "OrgWatchPurge_*" peut déjà exister (essai manuel
        // ou exécution de test précédente).
        for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE 'OrgWatchPurge%']) {
            System.abortJob(ct.Id);
        }

        Test.startTest();
        String jobId = OrgWatchPurgeController.createPurgeSchedule(60, '08:00');
        System.assertNotEquals(null, jobId, 'Le job de purge doit être créé');

        OrgWatchPurgeController.PurgeScheduleInfo info = OrgWatchPurgeController.getActivePurgeSchedule();
        System.assertNotEquals(null, info, 'Le planning actif doit être retrouvé');
        System.assertEquals((Id) jobId, (Id) info.jobId, 'Même job (formats 15/18 caractères comparés via Id)');
        System.assertEquals(60, info.ageDays, 'Le seuil choisi doit être retrouvable');
        System.assertEquals('08:00', info.timeValue, 'L\'heure choisie doit être retrouvable');

        OrgWatchPurgeController.deletePurgeSchedule(jobId);
        Test.stopTest();

        System.assertEquals(null, OrgWatchPurgeController.getActivePurgeSchedule(), 'Plus aucun planning actif après suppression');
    }

    @IsTest
    static void testCreatePurgeScheduleDefaults() {
        grantOrgWatchAdminForTest();
        for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE 'OrgWatchPurge%']) {
            System.abortJob(ct.Id);
        }

        Test.startTest();
        String jobId = OrgWatchPurgeController.createPurgeSchedule(null, null);
        Test.stopTest();

        OrgWatchPurgeController.PurgeScheduleInfo info = OrgWatchPurgeController.getActivePurgeSchedule();
        System.assertEquals(90, info.ageDays, 'Sans valeur fournie, le seuil doit retomber sur 90 jours');
        System.assertEquals('03:00', info.timeValue, 'Sans valeur fournie, l\'heure doit retomber sur 03:00');
    }

    @IsTest
    static void testDeletePurgeScheduleRejectsForeignJob() {
        grantOrgWatchAdminForTest();
        // Un job planifié qui n'appartient pas à cet outil (nom hors préfixe 'OrgWatchPurge')
        String foreignJobId = System.schedule('SomeUnrelatedJob', '0 0 4 ? * SUN', new OrgWatchExporterScheduler());

        Boolean exceptionThrown = false;
        try {
            OrgWatchPurgeController.deletePurgeSchedule(foreignJobId);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        System.assert(exceptionThrown, 'La suppression d\'un job qui n\'appartient pas à cet outil doit être refusée');
    }

    @IsTest
    static void testDeletePurgeScheduleRejectsUnknownJob() {
        grantOrgWatchAdminForTest();
        Boolean exceptionThrown = false;
        try {
            OrgWatchPurgeController.deletePurgeSchedule('000000000000000AAA');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        System.assert(exceptionThrown, 'Une AuraHandledException doit être levée pour un job inconnu');
    }

    @IsTest
    static void testPurgeSchedulerExecuteWithDefaultAge() {
        grantOrgWatchAdminForTest();
        setupLibraryWithFile('OrgWatch_Export_ForScheduler');

        Test.startTest();
        // ageDays = null -> doit retomber sur 90 jours par défaut, le fichier créé "maintenant" ne doit pas être purgé
        String jobId = System.schedule('TestOrgWatchPurgeRun', '0 0 4 ? * SUN', new OrgWatchPurgeScheduler(null));
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Le job planifié doit être créé');

        List<OrgWatchPurgeController.DataFileInfo> files = OrgWatchPurgeController.getDataFilesInfo();
        System.assertEquals(1, files.size(), 'Le fichier récent ne doit pas être purgé par le job (seuil 90 jours par défaut)');
    }

    /**
     * Utilisateur jetable SANS le Permission Set OrgWatch - Admin, pour
     * éprouver le contrôle de permission réel (attribution du Permission
     * Set), sans neutralisation.
     */
    private static User createNonAdminUser(String lastName) {
        String uniqueSuffix = String.valueOf(Datetime.now().getTime());
        User u = new User(
            FirstName = 'OrgWatch',
            LastName = lastName,
            Email = 'orgwatch.perm.' + lastName.toLowerCase() + '@example.com.invalid',
            Username = 'orgwatch.perm.' + lastName.toLowerCase() + uniqueSuffix + '@example.com.invalid',
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

    @IsTest
    static void testPurgeActionsRejectNonAdmin() {
        // Contrôle réel : pas de grantOrgWatchAdminForTest() ici.
        OrgWatchController.adminCheckOverrideForTests = null;
        User nonAdmin = createNonAdminUser('PurgeNo');

        Integer rejected = 0;
        System.runAs(nonAdmin) {
            Test.startTest();
            try { OrgWatchPurgeController.purgeFilesOlderThan(DateTime.now().addDays(-1)); }
            catch (AuraHandledException e) { rejected++; }
            try { OrgWatchPurgeController.createPurgeSchedule(30, '04:00'); }
            catch (AuraHandledException e) { rejected++; }
            try { OrgWatchPurgeController.deletePurgeSchedule('08e000000000000AAA'); }
            catch (AuraHandledException e) { rejected++; }
            Test.stopTest();
        }

        System.assertEquals(3, rejected,
            'Purger et planifier/arrêter une purge touchent toute l\'org : un utilisateur sans OrgWatch_Admin_Access doit être refusé');
    }
}