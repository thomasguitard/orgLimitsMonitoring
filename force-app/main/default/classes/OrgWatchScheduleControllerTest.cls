@IsTest(isParallel=false)
private class OrgWatchScheduleControllerTest {

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

    // Nettoyage défensif : CronTrigger n'est pas isolé entre les tests dans
    // cet org, des jobs "OrgWatchExport_*" peuvent déjà exister (essai
    // manuel ou exécution de test précédente) et provoquer une collision
    // de nom lors de la création.
    private static void cleanupExistingJobs() {
        for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE 'OrgWatchExport%']) {
            System.abortJob(ct.Id);
        }
    }

    @IsTest
    static void testCreateDailySchedule() {
        grantOrgWatchAdminForTest();
        cleanupExistingJobs();

        Test.startTest();
        String jobId = OrgWatchScheduleController.createSchedule('daily', '14:30');
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Le job daily doit être créé');
    }

    @IsTest
    static void testCreateHourlySchedule() {
        grantOrgWatchAdminForTest();
        cleanupExistingJobs();

        Test.startTest();
        String jobId = OrgWatchScheduleController.createSchedule('hourly', null);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Le job hourly doit être créé');
    }

    // Note : Salesforce refuse les listes (virgules) dans les champs
    // secondes/minutes d'un cron pour System.schedule ("Seconds and minutes
    // must be specified as integers"), y compris en exécution réelle (pas
    // seulement en contexte de test). "Toutes les 15/30 minutes" doit donc
    // créer plusieurs jobs à minute fixe plutôt qu'un seul cron combiné.

    @IsTest
    static void testCreate15MinScheduleCreatesFourJobs() {
        grantOrgWatchAdminForTest();
        cleanupExistingJobs();

        Test.startTest();
        String jobId = OrgWatchScheduleController.createSchedule('15min', null);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Le premier job créé doit être retourné');

        List<CronTrigger> jobs = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE 'OrgWatchExport_15min_%'];
        System.assertEquals(4, jobs.size(), '4 jobs (0, 15, 30, 45) doivent être créés');
    }

    @IsTest
    static void testCreate30MinScheduleCreatesTwoJobs() {
        grantOrgWatchAdminForTest();
        cleanupExistingJobs();

        Test.startTest();
        String jobId = OrgWatchScheduleController.createSchedule('30min', null);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Le premier job créé doit être retourné');

        List<CronTrigger> jobs = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE 'OrgWatchExport_30min_%'];
        System.assertEquals(2, jobs.size(), '2 jobs (0, 30) doivent être créés');
    }

    @IsTest
    static void testGetActiveSchedulesAndDelete() {
        grantOrgWatchAdminForTest();
        cleanupExistingJobs();

        Test.startTest();
        String jobId = OrgWatchScheduleController.createSchedule('hourly', null);

        List<OrgWatchScheduleController.ScheduleInfo> schedules = OrgWatchScheduleController.getActiveSchedules();
        System.assertEquals(1, schedules.size(), 'Le job créé doit apparaître dans la liste');
        System.assertEquals((Id) jobId, (Id) schedules[0].jobId);

        OrgWatchScheduleController.deleteSchedule(jobId);
        Test.stopTest();

        List<OrgWatchScheduleController.ScheduleInfo> remaining = OrgWatchScheduleController.getActiveSchedules();
        System.assertEquals(0, remaining.size(), 'Le job supprimé ne doit plus apparaître');
    }

    @IsTest
    static void testErrorHandling() {
        grantOrgWatchAdminForTest();
        Test.startTest();
        try {
            // Id inexistant : le job n'existe pas, la suppression doit être refusée
            OrgWatchScheduleController.deleteSchedule('000000000000000AAA');
            System.assert(false, 'Une AuraHandledException aurait dû être levée');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception capturée avec succès');
        }
        Test.stopTest();
    }

    @IsTest
    static void testDeleteScheduleRejectsForeignJob() {
        grantOrgWatchAdminForTest();
        // Un job planifié qui n'appartient pas à cet outil (nom hors préfixe 'OrgWatchExport')
        String foreignJobId = System.schedule('SomeUnrelatedJob', '0 0 4 ? * SUN', new OrgWatchExporterScheduler());

        Boolean exceptionThrown = false;
        try {
            OrgWatchScheduleController.deleteSchedule(foreignJobId);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        System.assert(exceptionThrown, 'La suppression d\'un job qui n\'appartient pas à cet outil doit être refusée');
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
    static void testScheduleActionsRejectNonAdmin() {
        // Contrôle réel : pas de grantOrgWatchAdminForTest() ici.
        OrgWatchController.adminCheckOverrideForTests = null;
        User nonAdmin = createNonAdminUser('SchedNo');

        Integer rejected = 0;
        System.runAs(nonAdmin) {
            Test.startTest();
            try { OrgWatchScheduleController.createSchedule('hourly', null); }
            catch (AuraHandledException e) { rejected++; }
            try { OrgWatchScheduleController.deleteSchedule('08e000000000000AAA'); }
            catch (AuraHandledException e) { rejected++; }
            Test.stopTest();
        }

        System.assertEquals(2, rejected,
            'Créer ou arrêter un export planifié touche toute l\'org : un utilisateur sans OrgWatch_Admin_Access doit être refusé');
    }
}