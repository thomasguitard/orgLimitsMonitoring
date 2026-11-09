@IsTest(isParallel=false)
private class OrgWatchExporterSchedulerTest {

    @IsTest
    static void testScheduledExecution() {
        Test.startTest();
        String jobId = System.schedule('TestOrgWatchExportRun', '0 0 3 ? * SUN', new OrgWatchExporterScheduler());
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Le job planifié doit être créé');

        List<ContentWorkspace> libs = [SELECT Id FROM ContentWorkspace WHERE Name = 'OrgWatch Reporting TEST'];
        System.assert(!libs.isEmpty(), 'La librairie doit être créée par l\'exécution du job');

        List<ContentVersion> exports = [
            SELECT Id FROM ContentVersion WHERE Title LIKE 'OrgWatch_Export_%'
        ];
        System.assert(!exports.isEmpty(), 'Un export CSV doit avoir été créé par le job planifié');
    }

    @IsTest
    static void testFailedExportSurfacesInsteadOfBeingSilent() {
        // Un export en échec doit faire échouer l'exécution planifiée, pour
        // apparaître dans Configuration > Tâches Apex : un échec silencieux
        // laissait l'outil paraître opérationnel avec des données figées.
        OrgWatchExporter.forceFailureForTests = true;

        Boolean thrown = false;
        Test.startTest();
        try {
            new OrgWatchExporterScheduler().execute(null);
        } catch (OrgWatchExporterScheduler.OrgWatchExportException e) {
            thrown = true;
            System.assert(
                e.getMessage().contains('Initialiser OrgWatch'),
                'Le message doit indiquer l\'action corrective, était: ' + e.getMessage()
            );
        }
        Test.stopTest();

        System.assert(thrown, 'Un export en échec doit lever une exception et non être ignoré');
    }
}