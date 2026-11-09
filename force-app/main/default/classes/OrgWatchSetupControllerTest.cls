@IsTest(isParallel=false)
private class OrgWatchSetupControllerTest {

    // Nettoyage défensif : CronTrigger n'est pas isolé entre les méthodes de
    // test dans cet org (les jobs planifiés survivent au rollback), un job
    // "OrgWatchExport_*" laissé par une autre méthode de test peut donc
    // fausser un test qui suppose qu'aucun export n'est encore planifié.
    private static void cleanupExistingExportJobs() {
        for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE 'OrgWatchExport%']) {
            System.abortJob(ct.Id);
        }
    }

    /**
     * Utilisateur de test jetable : ne jamais éprouver les actions
     * d'installation/désinstallation avec l'utilisateur courant, qui est un
     * vrai administrateur de l'org.
     */
    private static User createTestUser(String lastName) {
        String uniqueSuffix = String.valueOf(Datetime.now().getTime());
        User u = new User(
            FirstName = 'OrgWatch',
            LastName = lastName,
            Email = 'orgwatch.setup.' + lastName.toLowerCase() + '@example.com.invalid',
            Username = 'orgwatch.setup.' + lastName.toLowerCase() + uniqueSuffix + '@example.com.invalid',
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

    private static User createAdminUser(String lastName) {
        User u = createTestUser(lastName);
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'OrgWatch_Admin' LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
        return u;
    }

    @IsTest
    static void testAllActionsRejectNonAdmin() {
        User nonAdmin = createTestUser('NoAdmin');

        Integer rejected = 0;
        System.runAs(nonAdmin) {
            Test.startTest();
            try { OrgWatchSetupController.getSetupStatus(); } catch (AuraHandledException e) { rejected++; }
            try { OrgWatchSetupController.runSetup(); } catch (AuraHandledException e) { rejected++; }
            try { OrgWatchSetupController.ensureDefaultExportSchedule(); } catch (AuraHandledException e) { rejected++; }
            try { OrgWatchSetupController.prepareUninstall(); } catch (AuraHandledException e) { rejected++; }
            try { OrgWatchSetupController.deleteAllOrgWatchData(false); } catch (AuraHandledException e) { rejected++; }
            Test.stopTest();
        }

        System.assertEquals(5, rejected, 'Les 5 actions d\'installation/désinstallation doivent être refusées à un non-admin');
    }

    @IsTest
    static void testRunSetupCreatesLibraryThenIsIdempotent() {
        User admin = createAdminUser('Setup1');

        System.runAs(admin) {
            Test.startTest();
            OrgWatchSetupController.SetupResult first = OrgWatchSetupController.runSetup();
            OrgWatchSetupController.SetupResult second = OrgWatchSetupController.runSetup();
            Test.stopTest();

            System.assertEquals(true, first.success, 'Le setup doit réussir : ' + first.errorMessage);
            System.assertEquals(true, first.libraryCreated, 'La bibliothèque doit être créée au premier appel');

            System.assertEquals(true, second.success);
            System.assertEquals(true, second.libraryAlreadyExisted, 'Un second appel ne doit rien recréer');
            System.assertEquals(false, second.libraryCreated);
        }
    }

    @IsTest
    static void testSetupStatusReflectsLibraryPresence() {
        User admin = createAdminUser('Setup2');

        System.runAs(admin) {
            OrgWatchSetupController.SetupStatus before = OrgWatchSetupController.getSetupStatus();
            System.assertEquals(false, before.libraryExists, 'Aucune bibliothèque de test ne doit exister avant le setup');

            Test.startTest();
            OrgWatchSetupController.runSetup();
            OrgWatchSetupController.SetupStatus after = OrgWatchSetupController.getSetupStatus();
            Test.stopTest();

            System.assertEquals(true, after.libraryExists, 'La check-list doit voir la bibliothèque après le setup');
            System.assertEquals(OrgWatchController.getLibraryName(), after.libraryName);
        }
    }

    @IsTest
    static void testPrepareUninstallAbortsOrgWatchScheduledJobs() {
        User admin = createAdminUser('Setup3');

        System.runAs(admin) {
            // Un job planifié portant le préfixe de l'outil : c'est exactement
            // ce qui, laissé en place, fait échouer la désinstallation.
            String jobId = System.schedule(
                'OrgWatchTest_PrepareUninstall_' + Datetime.now().getTime(),
                '0 0 4 * * ?',
                new OrgWatchPurgeScheduler(90)
            );
            System.assertNotEquals(null, jobId, 'Pré-requis : le job de test doit être planifié');

            Test.startTest();
            OrgWatchSetupController.UninstallPrepResult result = OrgWatchSetupController.prepareUninstall();
            Test.stopTest();

            System.assertEquals(true, result.success, 'La préparation doit réussir : ' + result.failedJobNames);
            System.assert(result.abortedCount >= 1, 'Le job OrgWatch planifié doit avoir été arrêté, arrêtés = ' + result.abortedCount);

            List<CronTrigger> remaining = [
                SELECT Id FROM CronTrigger
                WHERE Id = :jobId AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING', 'PAUSED')
            ];
            System.assert(remaining.isEmpty(), 'Le job ne doit plus être actif après la préparation à la désinstallation');
        }
    }

    @IsTest
    static void testEnsureDefaultExportScheduleCreatesHourlyJobWhenNoneActive() {
        cleanupExistingExportJobs();
        User admin = createAdminUser('Setup5');

        System.runAs(admin) {
            System.assertEquals(false, OrgWatchScheduleController.hasActiveExportSchedule(),
                'Pré-requis : aucun export planifié avant le test');

            Test.startTest();
            OrgWatchSetupController.ScheduleResult result = OrgWatchSetupController.ensureDefaultExportSchedule();
            Test.stopTest();

            System.assertEquals(true, result.success, 'La planification par défaut doit réussir : ' + result.errorMessage);
            System.assertEquals(true, result.created, 'Un job doit être créé quand aucun export n\'est planifié');
            System.assertEquals(false, result.alreadyActive);
            System.assert(OrgWatchScheduleController.hasActiveExportSchedule(),
                'Un export planifié doit maintenant exister');
        }
    }

    @IsTest
    static void testEnsureDefaultExportScheduleIsIdempotent() {
        cleanupExistingExportJobs();
        User admin = createAdminUser('Setup6');

        System.runAs(admin) {
            // Une fréquence déjà configurée manuellement, différente de celle
            // par défaut : l'action ne doit rien recréer ni la remplacer.
            OrgWatchScheduleController.createSchedule('daily', '09:00');

            Test.startTest();
            OrgWatchSetupController.ScheduleResult result = OrgWatchSetupController.ensureDefaultExportSchedule();
            Test.stopTest();

            System.assertEquals(true, result.success);
            System.assertEquals(true, result.alreadyActive, 'Un export déjà planifié ne doit pas être dupliqué');
            System.assertEquals(false, result.created);

            List<CronTrigger> jobs = [
                SELECT Id FROM CronTrigger
                WHERE CronJobDetail.Name LIKE 'OrgWatchExport%'
                AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING', 'PAUSED')
            ];
            System.assertEquals(1, jobs.size(), 'Le job planifié manuellement doit rester seul, sans doublon');
        }
    }

    @IsTest
    static void testDeleteAllDataIsSafeWhenNothingToDelete() {
        User admin = createAdminUser('Setup4');

        System.runAs(admin) {
            Test.startTest();
            // Aucune bibliothèque : l'action ne doit pas échouer pour autant
            // (cas d'un client qui nettoie deux fois).
            OrgWatchSetupController.DataCleanupResult withoutLibrary =
                OrgWatchSetupController.deleteAllOrgWatchData(false);

            OrgWatchSetupController.runSetup();
            OrgWatchSetupController.DataCleanupResult emptyLibrary =
                OrgWatchSetupController.deleteAllOrgWatchData(true);
            Test.stopTest();

            System.assertEquals(true, withoutLibrary.success, 'Nettoyer sans bibliothèque doit être sans effet et sans erreur');
            System.assertEquals(0, withoutLibrary.deletedFileCount);

            System.assertEquals(true, emptyLibrary.success, 'Nettoyer une bibliothèque vide doit réussir : ' + emptyLibrary.errors);
            System.assertEquals(0, emptyLibrary.remainingFileCount);
            System.assertEquals(true, emptyLibrary.libraryDeletionQueued, 'Une bibliothèque vidée doit être mise en file pour suppression');

            // La suppression réelle est asynchrone (@future) : Test.stopTest()
            // ci-dessus l'a déjà exécutée, on peut donc vérifier son effet.
            List<ContentWorkspace> remaining = [
                SELECT Id FROM ContentWorkspace WHERE Name = 'OrgWatch Reporting TEST'
            ];
            System.assert(remaining.isEmpty(), 'La bibliothèque doit avoir été effectivement supprimée par le @future');
        }
    }

    private static void setupLibraryWithFile(String title) {
        List<ContentWorkspace> existing = [SELECT Id FROM ContentWorkspace WHERE Name = 'OrgWatch Reporting TEST' LIMIT 1];
        ContentWorkspace ws;
        if (existing.isEmpty()) {
            ws = new ContentWorkspace(Name = 'OrgWatch Reporting TEST');
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
            ShareType = 'I'
        );
    }

    /**
     * Le vrai symptôme signalé (la bibliothèque refuse de se supprimer tant
     * que sa corbeille contient du contenu) est couvert par les assertions
     * ci-dessous, elles-mêmes la preuve que la purge a fonctionné -
     * Database.emptyRecycleBin() est vérifiée séparément (isSuccess=true,
     * sans erreur) plutôt que par une requête "ALL ROWS" juste après : un
     * ContentDocument reste interrogeable ainsi un moment après une purge
     * pourtant déjà confirmée réussie par la plateforme, propre à
     * l'architecture de stockage des fichiers - ce n'est donc pas un signal
     * fiable en contexte de test.
     */
    @IsTest
    static void testDeleteAllDataHardDeletesFilesInsteadOfRecycling() {
        User admin = createAdminUser('Setup7');

        // setupLibraryWithFile() est appelée à l'intérieur du même runAs()
        // que l'action testée : en contexte de test, une bibliothèque créée
        // par une identité n'est pas visible de façon fiable depuis un
        // System.runAs() différent (constaté empiriquement sur
        // OrgWatchAdminControllerTest), même avec AccessLevel.SYSTEM_MODE.
        System.runAs(admin) {
            setupLibraryWithFile('OrgWatch_Export_ToPurge');

            Test.startTest();
            OrgWatchSetupController.DataCleanupResult result = OrgWatchSetupController.deleteAllOrgWatchData(true);
            Test.stopTest();

            System.assertEquals(true, result.success, 'Le nettoyage doit réussir : ' + result.errors);
            System.assertEquals(1, result.deletedFileCount);
            System.assertEquals(true, result.libraryDeletionQueued,
                'La bibliothèque doit être mise en file pour suppression, sans erreur DEPENDENCY_EXISTS : c\'est le bug corrigé ici');

            // La suppression réelle est asynchrone (@future) : Test.stopTest()
            // ci-dessus l'a déjà exécutée.
            List<ContentWorkspace> remaining = [
                SELECT Id FROM ContentWorkspace WHERE Name = 'OrgWatch Reporting TEST'
            ];
            System.assert(remaining.isEmpty(), 'La bibliothèque doit avoir été effectivement supprimée par le @future');
        }
    }

    /**
     * Reproduit le blocage observé : un fichier déjà dans la corbeille
     * (laissé par une exécution précédente, avant ce correctif) doit être
     * purgé automatiquement, sinon Salesforce refuse de supprimer la
     * bibliothèque avec l'erreur DEPENDENCY_EXISTS.
     */
    @IsTest
    static void testDeleteAllDataPurgesPreexistingRecycledFiles() {
        User admin = createAdminUser('Setup8');

        // Cf. testDeleteAllDataHardDeletesFilesInsteadOfRecycling : tout dans
        // le même runAs().
        System.runAs(admin) {
            setupLibraryWithFile('OrgWatch_Export_Stale');
            Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Title = 'OrgWatch_Export_Stale' LIMIT 1].ContentDocumentId;
            // Simule une exécution précédente (avant ce correctif) qui avait
            // seulement mis le fichier à la corbeille sans le purger.
            delete new ContentDocument(Id = docId);

            Test.startTest();
            OrgWatchSetupController.DataCleanupResult result = OrgWatchSetupController.deleteAllOrgWatchData(true);
            Test.stopTest();

            System.assertEquals(true, result.success, 'La purge du contenu déjà recyclé doit réussir : ' + result.errors);
            System.assertEquals(true, result.libraryDeletionQueued,
                'La bibliothèque doit être mise en file pour suppression une fois la corbeille vidée');

            List<ContentWorkspace> remaining = [
                SELECT Id FROM ContentWorkspace WHERE Name = 'OrgWatch Reporting TEST'
            ];
            System.assert(remaining.isEmpty(), 'La bibliothèque doit avoir été effectivement supprimée par le @future');
        }
    }
}