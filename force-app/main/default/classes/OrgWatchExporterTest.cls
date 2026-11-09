@IsTest(isParallel=false)
private class OrgWatchExporterTest {

    @TestSetup
    static void setup() {
        // Library creation guarded against DUPLICATE_VALUE
        ContentWorkspace ws;
        List<ContentWorkspace> existingWs = [
            SELECT Id FROM ContentWorkspace WHERE Name = 'OrgWatch Reporting TEST' LIMIT 1
        ];
        if (existingWs.isEmpty()) {
            ws = new ContentWorkspace(
                Name = 'OrgWatch Reporting TEST'
            );
            // ContentWorkspace est un "setup object" pour Apex : l'insérer puis
            // insérer un ContentVersion dans la même transaction lève MIXED_DML_OPERATION.
            System.runAs(new User(Id = UserInfo.getUserId())) {
                insert ws;
            }
        } else {
            ws = existingWs[0];
        }

        // Dummy CSV so the controller's parser has data to read
        ContentVersion cv = new ContentVersion(
            Title = 'OrgWatch_Export_Test',
            PathOnClient = 'Test.csv',
            VersionData = Blob.valueOf(
                'Catégorie;Nom de la Limite;Valeur Actuelle;Maximum;Consommation (%)\n' +
                'Organisation;Data Storage;10;100;10,00%'
            ),
            IsMajorVersion = true
        );
        insert cv;

        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

        try {
            insert new ContentDocumentLink(
                ContentDocumentId = docId,
                LinkedEntityId = ws.Id,
                ShareType = 'I',
                Visibility = 'AllUsers'
            );
        } catch (Exception e) {
            System.debug('Link might already exist: ' + e.getMessage());
        }
    }

    @IsTest
    static void testExportFunctionality() {
        Test.startTest();
        Boolean result = OrgWatchExporter.exportLimitsToLibrary();
        Test.stopTest();
        System.assertEquals(true, result, 'Exporter should execute successfully and return true');
    }

    @IsTest
    static void testGetLimitsHistory() {
        Test.startTest();
        Map<String, List<OrgWatchController.DataPoint>> history = OrgWatchController.getLimitsHistory();
        Test.stopTest();
        System.assertNotEquals(null, history, 'History map should be initialized');
        System.assert(history.containsKey('Data Storage'), 'La colonne Catégorie en tête de ligne doit être ignorée, pas confondue avec le nom de la métrique');
        System.assertEquals(1, history.get('Data Storage').size());
        System.assertEquals(10, history.get('Data Storage')[0].current);
        System.assertEquals(100, history.get('Data Storage')[0].max);
    }

    @IsTest
    static void testScheduler() {
        String cron = '0 0 2 * * ?'; // daily at 02:00
        Test.startTest();
        String jobId = System.schedule(
            'OrgWatch Daily Export Test',
            cron,
            new OrgWatchExporterScheduler()
        );
        Test.stopTest(); // execute() runs here

        System.assertNotEquals(null, jobId, 'Job should be scheduled');

        CronTrigger ct = [
            SELECT CronExpression, State FROM CronTrigger WHERE Id = :jobId
        ];
        System.assertEquals(cron, ct.CronExpression, 'Cron expression should match');
    }

    // --- NEW TESTS FOR UTILITY METHODS ---

    @IsTest
    static void testGetDecimalValue() {
        Test.startTest();
        Decimal nullVal = OrgWatchExporter.getDecimalValue(null);
        Decimal decVal  = OrgWatchExporter.getDecimalValue(12.345);
        Decimal longVal = OrgWatchExporter.getDecimalValue(100L);
        Decimal intVal  = OrgWatchExporter.getDecimalValue(50);
        Decimal strVal  = OrgWatchExporter.getDecimalValue('45.67');
        Test.stopTest();

        System.assertEquals(0, nullVal, 'Null input should return 0');
        System.assertEquals(12.345, decVal, 'Decimal input should return exact Decimal value');
        System.assertEquals(100.0, longVal, 'Long input should convert to Decimal');
        System.assertEquals(50.0, intVal, 'Integer input should convert to Decimal');
        System.assertEquals(45.67, strVal, 'String input should parse into Decimal');
    }

    @IsTest
    static void testGetLongValue() {
        Test.startTest();
        Long nullVal = OrgWatchExporter.getLongValue(null);
        Long longVal = OrgWatchExporter.getLongValue(1000L);
        Long intVal  = OrgWatchExporter.getLongValue(250);
        Long decVal  = OrgWatchExporter.getLongValue(78.9);
        Long strVal  = OrgWatchExporter.getLongValue('500');
        Test.stopTest();

        System.assertEquals(0L, nullVal, 'Null input should return 0');
        System.assertEquals(1000L, longVal, 'Long input should return exact Long value');
        System.assertEquals(250L, intVal, 'Integer input should convert to Long');
        System.assertEquals(78L, decVal, 'Decimal input should truncate to Long');
        System.assertEquals(500L, strVal, 'String input should parse into Long');
    }
}