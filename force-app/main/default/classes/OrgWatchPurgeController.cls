public with sharing class OrgWatchPurgeController {

    private static final String LIBRARY_NAME = Test.isRunningTest() ? 'OrgWatch Reporting TEST' : 'OrgWatch Reporting';
    private static final String FILE_PREFIX = 'OrgWatch_Export_';
    private static final Integer DELETE_BATCH_SIZE = 200;
    private static final String PURGE_JOB_PREFIX = 'OrgWatchPurge';

    @AuraEnabled(cacheable=true)
    public static List<DataFileInfo> getDataFilesInfo() {
        List<DataFileInfo> result = new List<DataFileInfo>();

        List<ContentWorkspace> wsList = [
            SELECT Id FROM ContentWorkspace WHERE Name = :LIBRARY_NAME LIMIT 1
        ];
        if (wsList.isEmpty()) {
            return result;
        }

        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :wsList[0].Id
        ]) {
            docIds.add(cdl.ContentDocumentId);
        }

        if (docIds.isEmpty()) {
            return result;
        }

        String titleFilter = FILE_PREFIX + '%';

        // Uniquement les fichiers de "data" (exports CSV), jamais le fichier de préférences
        for (ContentVersion cv : [
            SELECT ContentDocumentId, CreatedDate, ContentSize
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds
            AND IsLatest = true
            AND FileExtension = 'csv'
            AND Title LIKE :titleFilter
            ORDER BY CreatedDate ASC
            LIMIT 5000
        ]) {
            result.add(new DataFileInfo(cv.ContentDocumentId, cv.CreatedDate, cv.ContentSize));
        }

        return result;
    }

    @AuraEnabled
    public static PurgeResult purgeFilesOlderThan(DateTime cutoffDate) {
        // Suppression définitive de l'historique de TOUTE l'org : réservé aux
        // admins OrgWatch (la lecture, elle, reste ouverte à tous).
        OrgWatchController.assertOrgWatchAdmin();

        PurgeResult res = new PurgeResult();

        if (cutoffDate == null) {
            res.errors.add('Aucune date de coupure fournie.');
            return res;
        }

        List<ContentWorkspace> wsList;
        try {
            wsList = [SELECT Id FROM ContentWorkspace WHERE Name = :LIBRARY_NAME LIMIT 1];
        } catch (Exception e) {
            res.errors.add('Bibliothèque introuvable : ' + e.getMessage());
            return res;
        }

        if (wsList.isEmpty()) {
            return res; // Pas encore de bibliothèque -> rien à purger, ce n'est pas un échec
        }

        Set<Id> docIds = new Set<Id>();
        try {
            for (ContentDocumentLink cdl : [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :wsList[0].Id
            ]) {
                docIds.add(cdl.ContentDocumentId);
            }
        } catch (Exception e) {
            res.errors.add('Erreur lors de la lecture des fichiers liés : ' + e.getMessage());
            return res;
        }

        if (docIds.isEmpty()) {
            return res; // rien à purger
        }

        // On re-détermine les fichiers cibles au moment de l'exécution (pas de dépendance
        // à une liste d'IDs venant du client, qui pourrait être obsolète)
        String titleFilter = FILE_PREFIX + '%';
        Map<Id, Long> idToBytes = new Map<Id, Long>();

        try {
            for (ContentVersion cv : [
                SELECT ContentDocumentId, ContentSize
                FROM ContentVersion
                WHERE ContentDocumentId IN :docIds
                AND IsLatest = true
                AND FileExtension = 'csv'
                AND Title LIKE :titleFilter
                AND CreatedDate < :cutoffDate
                LIMIT 5000
            ]) {
                idToBytes.put(cv.ContentDocumentId, cv.ContentSize != null ? (Long) cv.ContentSize : 0L);
            }
        } catch (Exception e) {
            res.errors.add('Erreur lors de l\'identification des fichiers à purger : ' + e.getMessage());
            return res;
        }

        if (idToBytes.isEmpty()) {
            return res; // aucun fichier ne correspond au critère
        }

        List<Id> toDeleteIds = new List<Id>(idToBytes.keySet());

        // Suppression par lots, tolérante aux suppressions concurrentes
        for (Integer i = 0; i < toDeleteIds.size(); i += DELETE_BATCH_SIZE) {
            Integer endIdx = Math.min(i + DELETE_BATCH_SIZE, toDeleteIds.size());
            List<ContentDocument> batch = new List<ContentDocument>();
            for (Integer j = i; j < endIdx; j++) {
                batch.add(new ContentDocument(Id = toDeleteIds[j]));
            }

            List<Database.DeleteResult> drList;
            try {
                drList = Database.delete(batch, false);
            } catch (Exception e) {
                res.errors.add('Erreur inattendue lors de la suppression d\'un lot : ' + e.getMessage());
                continue;
            }

            for (Integer k = 0; k < drList.size(); k++) {
                Database.DeleteResult dr = drList[k];
                Id currentId = batch[k].Id;
                Long bytes = idToBytes.get(currentId);

                if (dr.isSuccess()) {
                    res.deletedCount++;
                    res.freedBytes += bytes;
                } else {
                    Boolean alreadyGone = false;
                    for (Database.Error err : dr.getErrors()) {
                        if (err.getStatusCode() == StatusCode.ENTITY_IS_DELETED) {
                            alreadyGone = true;
                        }
                    }
                    if (alreadyGone) {
                        // Un autre utilisateur/process a déjà supprimé ce fichier entretemps :
                        // ce n'est pas une erreur, l'objectif (fichier absent) est atteint.
                        res.alreadyDeletedCount++;
                        res.freedBytes += bytes;
                    } else {
                        res.failedCount++;
                        for (Database.Error err : dr.getErrors()) {
                            res.errors.add(err.getMessage());
                        }
                    }
                }
            }
        }

        return res;
    }

    @AuraEnabled
    public static PurgeScheduleInfo getActivePurgeSchedule() {
        List<CronTrigger> jobs = [
            SELECT Id, CronJobDetail.Name, State, NextFireTime, PreviousFireTime
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :(PURGE_JOB_PREFIX + '%')
            AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING', 'PAUSED')
            ORDER BY NextFireTime ASC
            LIMIT 1
        ];

        if (jobs.isEmpty()) {
            return null;
        }

        CronTrigger ct = jobs[0];
        PurgeScheduleInfo info = new PurgeScheduleInfo();
        info.jobId = ct.Id;
        info.state = ct.State;
        info.nextRun = ct.NextFireTime;
        info.previousRun = ct.PreviousFireTime;

        // Le nom du job encode l'heure et le seuil choisis, ex: "OrgWatchPurge_Daily_03h00_90j"
        List<String> nameParts = ct.CronJobDetail.Name.split('_');
        if (nameParts.size() >= 4) {
            info.timeValue = nameParts[2].replace('h', ':');
            String daysPart = nameParts[3];
            info.ageDays = Integer.valueOf(daysPart.substring(0, daysPart.length() - 1));
        }

        List<AsyncApexJob> lastRuns = [
            SELECT Status, ExtendedStatus, CompletedDate
            FROM AsyncApexJob
            WHERE CronTriggerId = :ct.Id
            ORDER BY CompletedDate DESC NULLS LAST
            LIMIT 1
        ];
        if (!lastRuns.isEmpty()) {
            info.lastRunStatus = lastRuns[0].Status;
            info.lastRunError = lastRuns[0].ExtendedStatus;
            info.lastRunDate = lastRuns[0].CompletedDate;
        }

        return info;
    }

    @AuraEnabled
    public static String createPurgeSchedule(Integer ageDays, String timeValue) {
        // Crée un job planifié à l'échelle de l'org : admins uniquement.
        OrgWatchController.assertOrgWatchAdmin();

        Integer effectiveAgeDays = ageDays != null ? ageDays : 90;
        // ageDays <= 0 planifierait une purge de tout l'historique, chaque
        // jour, sans que l'écran ne le laisse deviner.
        if (effectiveAgeDays <= 0) {
            throw new AuraHandledException('La rétention doit être d\'au moins 1 jour.');
        }
        String purgeTime = String.isBlank(timeValue) ? '03:00' : timeValue;
        if (!Pattern.matches('^([01][0-9]|2[0-3]):[0-5][0-9]$', purgeTime)) {
            throw new AuraHandledException('Heure invalide, format attendu HH:MM.');
        }

        try {
            List<String> timeParts = purgeTime.split(':');
            String hour = timeParts[0];
            String minute = timeParts.size() > 1 ? timeParts[1] : '0';
            String cronExpression = '0 ' + minute + ' ' + hour + ' * * ?';

            String jobName = PURGE_JOB_PREFIX + '_Daily_' + purgeTime.replace(':', 'h') + '_' + effectiveAgeDays + 'j';

            return System.schedule(jobName, cronExpression, new OrgWatchPurgeScheduler(effectiveAgeDays));
        } catch (Exception e) {
            throw new AuraHandledException('Erreur: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void deletePurgeSchedule(String jobId) {
        // Arrête un job planifié à l'échelle de l'org : admins uniquement.
        OrgWatchController.assertOrgWatchAdmin();
        validateJobOwnership(jobId);
        try {
            System.abortJob(jobId);
        } catch (Exception e) {
            throw new AuraHandledException('Erreur: ' + e.getMessage());
        }
    }

    /**
     * Empêche la suppression d'un job planifié qui n'appartient pas à cet outil
     * (par ex. un CronTrigger d'un tout autre process de l'org).
     */
    private static void validateJobOwnership(String jobId) {
        List<CronTrigger> jobs = [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger
            WHERE Id = :jobId
        ];
        if (jobs.isEmpty() || !jobs[0].CronJobDetail.Name.startsWith(PURGE_JOB_PREFIX)) {
            throw new AuraHandledException('Ce job ne peut pas être supprimé depuis cet outil.');
        }
    }

    public class DataFileInfo {
        @AuraEnabled public Id docId;
        @AuraEnabled public DateTime createdDate;
        @AuraEnabled public Long sizeBytes;

        public DataFileInfo(Id docId, DateTime createdDate, Integer sizeBytes) {
            this.docId = docId;
            this.createdDate = createdDate;
            this.sizeBytes = sizeBytes != null ? sizeBytes : 0;
        }
    }

    public class PurgeScheduleInfo {
        @AuraEnabled public String jobId;
        @AuraEnabled public String state;
        @AuraEnabled public DateTime nextRun;
        @AuraEnabled public DateTime previousRun;
        @AuraEnabled public Integer ageDays;
        @AuraEnabled public String timeValue;
        @AuraEnabled public String lastRunStatus;
        @AuraEnabled public String lastRunError;
        @AuraEnabled public DateTime lastRunDate;
    }

    public class PurgeResult {
        @AuraEnabled public Integer deletedCount = 0;
        @AuraEnabled public Integer alreadyDeletedCount = 0;
        @AuraEnabled public Integer failedCount = 0;
        @AuraEnabled public Long freedBytes = 0;
        @AuraEnabled public List<String> errors = new List<String>();
    }
}