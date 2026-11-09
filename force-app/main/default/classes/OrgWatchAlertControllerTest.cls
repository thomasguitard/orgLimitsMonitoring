@IsTest(isParallel=false)
private class OrgWatchAlertControllerTest {

    private static final String ALERT_JOB_PREFIX = 'OrgWatchAlert_Daily_';

    private static void setupLibraryWithFile(String title, String csvBody) {
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
            VersionData = Blob.valueOf(csvBody),
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

    // Nettoyage défensif : CronTrigger n'est pas isolé entre les tests dans
    // cet org, un job "OrgWatchAlert_Daily_*" peut déjà exister (essai
    // manuel ou exécution de test précédente).
    private static void cleanupAlertJob() {
        for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE :(ALERT_JOB_PREFIX + '%')]) {
            System.abortJob(ct.Id);
        }
    }

    @IsTest
    static void testGetAlertPreferencesNoConfig() {
        OrgWatchAlertController.AlertPreferences prefs = OrgWatchAlertController.getAlertPreferences();
        System.assertEquals('', prefs.metricThresholds);
        System.assertEquals('OnlyOnBreach', prefs.emailMode);
        System.assertEquals('15:00', prefs.alertSendTime, 'Aucun Custom Setting configuré -> heure par défaut');
    }

    @IsTest
    static void testSaveAlertPreferencesCreatesJobAtConfiguredTime() {
        cleanupAlertJob();

        OrgWatch_Settings__c settings = OrgWatch_Settings__c.getOrgDefaults();
        settings.SetupOwnerId = UserInfo.getOrganizationId();
        settings.Alert_Send_Time__c = '09:30';
        upsert settings;

        Test.startTest();
        OrgWatchAlertController.saveAlertPreferences('DataStorageMB:80', 'Always');
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :(ALERT_JOB_PREFIX + '%')
        ];
        System.assertEquals(1, jobs.size());
        System.assertEquals('OrgWatchAlert_Daily_09h30', jobs[0].CronJobDetail.Name, 'Le job doit être créé à l\'heure configurée dans le Custom Setting');
    }

    @IsTest
    static void testSaveAlertPreferencesCreatesJob() {
        cleanupAlertJob();

        Test.startTest();
        String result = OrgWatchAlertController.saveAlertPreferences('DataStorageMB:80,ApiRequests:90', 'Always');
        Test.stopTest();

        System.assertEquals('SUCCESS', result);

        OrgWatchAlertController.AlertPreferences prefs = OrgWatchAlertController.getAlertPreferences();
        System.assertEquals('DataStorageMB:80,ApiRequests:90', prefs.metricThresholds);
        System.assertEquals('Always', prefs.emailMode);

        List<CronTrigger> jobs = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE :(ALERT_JOB_PREFIX + '%')];
        System.assertEquals(1, jobs.size(), 'Le job d\'alerting doit avoir été créé pour le 1er utilisateur avec une alerte');
    }

    @IsTest
    static void testDisableAllAlertsAbortsJobWhenNoOneElseHasAlerts() {
        cleanupAlertJob();

        Test.startTest();
        OrgWatchAlertController.saveAlertPreferences('DataStorageMB:80', null);
        String result = OrgWatchAlertController.disableAllAlerts();
        Test.stopTest();

        System.assertEquals('SUCCESS', result);

        OrgWatchAlertController.AlertPreferences prefs = OrgWatchAlertController.getAlertPreferences();
        System.assertEquals('', prefs.metricThresholds);

        List<CronTrigger> jobs = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE :(ALERT_JOB_PREFIX + '%')];
        System.assertEquals(0, jobs.size(), 'Plus personne n\'a d\'alerte, le job doit être aborté');
    }

    @IsTest
    static void testDisableAllAlertsKeepsJobWhenAnotherUserStillHasAlerts() {
        cleanupAlertJob();

        // Fichier avec un 2e utilisateur (fictif mais au bon format d'Id 18 caractères)
        // qui a une alerte active.
        String decoyUserId = '005000000000000AAA';
        String csv = 'UserId;HiddenMetrics;MetricThresholds;EmailMode;LastModified\n'
            + UserInfo.getUserId() + ';;DataStorageMB:80;OnlyOnBreach;2026-01-01T00:00:00Z\n'
            + decoyUserId + ';;ApiRequests:70;Always;2026-01-01T00:00:00Z\n';
        setupLibraryWithFile('OrgWatchUserPreferences.csv', csv);

        Test.startTest();
        String result = OrgWatchAlertController.disableAllAlerts();
        Test.stopTest();

        System.assertEquals('SUCCESS', result);

        List<CronTrigger> jobs = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE :(ALERT_JOB_PREFIX + '%')];
        System.assertEquals(1, jobs.size(), 'Le 2e utilisateur (fictif) a toujours une alerte active, le job doit rester actif');
    }
}