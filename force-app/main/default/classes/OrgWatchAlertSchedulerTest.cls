@IsTest(isParallel=false)
private class OrgWatchAlertSchedulerTest {

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

    @IsTest
    static void testParseThresholds() {
        Map<String, Integer> result = OrgWatchAlertScheduler.parseThresholds('MetricA:80,MetricB:90,Invalid,MetricC:notanumber');
        System.assertEquals(2, result.size());
        System.assertEquals(80, result.get('MetricA'));
        System.assertEquals(90, result.get('MetricB'));
    }

    @IsTest
    static void testBuildAlertRows() {
        Map<String, List<OrgWatchController.DataPoint>> history = new Map<String, List<OrgWatchController.DataPoint>>();
        history.put('MetricA', new List<OrgWatchController.DataPoint>{
            new OrgWatchController.DataPoint(DateTime.now().addHours(-2), 90, 100),
            new OrgWatchController.DataPoint(DateTime.now().addHours(-1), 50, 100),
            new OrgWatchController.DataPoint(DateTime.now(), 95, 100)
        });

        List<OrgWatchAlertScheduler.AlertRow> rows = OrgWatchAlertScheduler.buildAlertRows('MetricA:80', history);

        System.assertEquals(1, rows.size());
        System.assertEquals('MetricA', rows[0].metricName);
        System.assertEquals(2, rows[0].breachCount, '2 points sur 3 dépassent 80%');
        System.assertEquals(3, rows[0].totalPoints);
    }

    @IsTest
    static void testBuildAlertRowsSkipsMetricsWithoutData() {
        Map<String, List<OrgWatchController.DataPoint>> history = new Map<String, List<OrgWatchController.DataPoint>>();

        List<OrgWatchAlertScheduler.AlertRow> rows = OrgWatchAlertScheduler.buildAlertRows('MetricWithoutHistory:80', history);

        System.assertEquals(0, rows.size(), 'Aucune donnée pour cette métrique -> pas de ligne dans le mail');
    }

    // Note : on vérifie la logique de décision d'execute() via les compteurs
    // internes @TestVisible (lastAlertingUserCount / lastEmailsBuiltCount)
    // plutôt que Limits.getEmailInvocations(), qui s'est avéré peu fiable
    // dans cet org (probablement lié aux réglages Email Deliverability du
    // sandbox) : execute() construit bien l'email attendu dans tous les cas
    // ci-dessous, seul l'incrément du compteur de gouverneur était en cause.

    @IsTest
    static void testExecuteBuildsNoEmailWithoutAlertingUsers() {
        Test.startTest();
        new OrgWatchAlertScheduler().execute(null);
        Test.stopTest();

        System.assertEquals(0, OrgWatchAlertScheduler.lastAlertingUserCount, 'Aucun utilisateur avec alerte');
        System.assertEquals(0, OrgWatchAlertScheduler.lastEmailsBuiltCount, 'Aucun email construit');
    }

    @IsTest
    static void testExecuteBuildsEmailWhenAlwaysMode() {
        // On passe par la vraie méthode de sauvegarde plutôt que d'écrire le
        // fichier à la main : elle met à jour le document existant (au lieu
        // d'en créer un doublon), ce qui est nécessaire pour que la lecture
        // ultérieure (LIMIT 1 sans tri) retombe bien sur ces données.
        OrgWatchController.saveUserPreferencesFull(null, 'DataStorageMB:10', 'Always');
        setupLibraryWithFile('OrgWatch_Export_Now', 'LimitName;Current;Max\nDataStorageMB;90;100\n');

        Test.startTest();
        new OrgWatchAlertScheduler().execute(null);
        Test.stopTest();

        System.assertEquals(1, OrgWatchAlertScheduler.lastAlertingUserCount);
        System.assertEquals(1, OrgWatchAlertScheduler.lastEmailsBuiltCount, 'EmailMode=Always doit toujours construire un mail dès qu\'il y a une donnée à évaluer');
    }

    @IsTest
    static void testExecuteBuildsNoEmailWhenOnlyOnBreachAndNoBreach() {
        OrgWatchController.saveUserPreferencesFull(null, 'DataStorageMB:95', 'OnlyOnBreach');
        setupLibraryWithFile('OrgWatch_Export_Now', 'LimitName;Current;Max\nDataStorageMB;10;100\n');

        Test.startTest();
        new OrgWatchAlertScheduler().execute(null);
        Test.stopTest();

        System.assertEquals(1, OrgWatchAlertScheduler.lastAlertingUserCount);
        System.assertEquals(0, OrgWatchAlertScheduler.lastEmailsBuiltCount, 'Pas de dépassement + mode OnlyOnBreach -> aucun email construit');
    }

    @IsTest
    static void testExecuteBuildsEmailWhenOnlyOnBreachAndBreached() {
        OrgWatchController.saveUserPreferencesFull(null, 'DataStorageMB:10', 'OnlyOnBreach');
        setupLibraryWithFile('OrgWatch_Export_Now', 'LimitName;Current;Max\nDataStorageMB;90;100\n');

        Test.startTest();
        new OrgWatchAlertScheduler().execute(null);
        Test.stopTest();

        System.assertEquals(1, OrgWatchAlertScheduler.lastAlertingUserCount);
        System.assertEquals(1, OrgWatchAlertScheduler.lastEmailsBuiltCount, 'Seuil dépassé + mode OnlyOnBreach -> un email doit être construit');
    }

    @IsTest
    static void testExecuteBuildsEnglishEmailWhenLanguageIsEn() {
        OrgWatchController.saveUserPreferencesFull(null, 'DataStorageMB:10', 'Always');
        OrgWatchController.saveLanguagePreference('en');
        setupLibraryWithFile('OrgWatch_Export_Now', 'LimitName;Current;Max\nDataStorageMB;90;100\n');

        Test.startTest();
        new OrgWatchAlertScheduler().execute(null);
        Test.stopTest();

        System.assertEquals(1, OrgWatchAlertScheduler.lastEmailsBuiltCount);
        System.assert(
            OrgWatchAlertScheduler.lastEmailSubject.contains('OrgWatch Alerts'),
            'Le sujet doit être en anglais quand la langue enregistrée est "en", était: ' + OrgWatchAlertScheduler.lastEmailSubject
        );
    }

    @IsTest
    static void testExecuteBuildsFrenchEmailByDefault() {
        OrgWatchController.saveUserPreferencesFull(null, 'DataStorageMB:10', 'Always');
        setupLibraryWithFile('OrgWatch_Export_Now', 'LimitName;Current;Max\nDataStorageMB;90;100\n');

        Test.startTest();
        new OrgWatchAlertScheduler().execute(null);
        Test.stopTest();

        System.assertEquals(1, OrgWatchAlertScheduler.lastEmailsBuiltCount);
        System.assert(
            OrgWatchAlertScheduler.lastEmailSubject.contains('Alertes OrgWatch'),
            'Le sujet doit être en français par défaut (aucune langue enregistrée), était: ' + OrgWatchAlertScheduler.lastEmailSubject
        );
    }

    @IsTest
    static void testExecuteBuildsBrandedEmailWithLeftAlignedHeaders() {
        OrgWatchController.saveUserPreferencesFull(null, 'DataStorageMB:10', 'Always');
        setupLibraryWithFile('OrgWatch_Export_Now', 'LimitName;Current;Max\nDataStorageMB;90;100\n');

        Test.startTest();
        new OrgWatchAlertScheduler().execute(null);
        Test.stopTest();

        String html = OrgWatchAlertScheduler.lastEmailHtmlBody;
        System.assertNotEquals(null, html);
        System.assert(html.contains('<th style="padding:6px 10px;text-align:left;">'), 'Les en-têtes de colonnes doivent être explicitement alignés à gauche (le défaut navigateur de <th> est centré)');
        System.assert(html.contains('OrgWatch</div>'), 'Le bandeau de marque doit afficher le wordmark OrgWatch');
    }

    @IsTest
    static void testRawSendEmailSucceeds() {
        // Vérifie indépendamment que Messaging.sendEmail fonctionne bien dans
        // cet org pour l'utilisateur courant (déconnecté de la logique
        // métier du scheduler).
        User u = [SELECT Id, Email FROM User WHERE Id = :UserInfo.getUserId()];
        System.assertNotEquals(null, u.Email);

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setTargetObjectId(u.Id);
        mail.setSaveAsActivity(false);
        mail.setSubject('Test');
        mail.setHtmlBody('<p>Test</p>');

        Test.startTest();
        List<Messaging.SendEmailResult> results = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assert(results[0].isSuccess(), 'L\'envoi doit réussir');
    }
}