public with sharing class OrgWatchScheduleController {

    @AuraEnabled
    public static List<ScheduleInfo> getActiveSchedules() {
        List<ScheduleInfo> schedules = new List<ScheduleInfo>();

        try {
            List<CronTrigger> cronJobs = [
                SELECT Id, CronJobDetail.Id, CronJobDetail.Name,
                       CronExpression, State, NextFireTime, PreviousFireTime
                FROM CronTrigger
                WHERE CronJobDetail.Name LIKE 'OrgWatchExport%'
                AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING', 'PAUSED')
                ORDER BY NextFireTime ASC
            ];

            for (CronTrigger ct : cronJobs) {
                ScheduleInfo info = new ScheduleInfo();
                info.jobId = ct.Id;
                info.jobName = ct.CronJobDetail.Name;
                info.cronExpression = ct.CronExpression;
                info.state = ct.State;
                info.nextRun = ct.NextFireTime;
                info.previousRun = ct.PreviousFireTime;
                info.frequency = parseCronToFrequency(ct.CronExpression);
                schedules.add(info);
            }
        } catch (Exception e) {
            System.debug('Error: ' + e.getMessage());
        }

        return schedules;
    }

    /**
     * Utilisé par l'onglet Alertes pour avertir l'utilisateur si aucun export
     * planifié n'est actif (les alertes ont besoin de données récentes).
     */
    public static Boolean hasActiveExportSchedule() {
        List<CronTrigger> jobs = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'OrgWatchExport%'
            AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING', 'PAUSED')
            LIMIT 1
        ];
        return !jobs.isEmpty();
    }

    @AuraEnabled
    public static String createSchedule(String frequency, String timeValue) {
        // Crée des jobs planifiés à l'échelle de l'org : admins uniquement
        // (la consultation du planning actif reste ouverte à tous).
        OrgWatchController.assertOrgWatchAdmin();

        try {
            // Salesforce n'accepte pas de liste (virgules) dans les champs
            // secondes/minutes d'un cron pour System.schedule (erreur
            // "Seconds and minutes must be specified as integers"). Pour
            // "toutes les 15/30 min", on doit donc créer plusieurs jobs à
            // minute fixe plutôt qu'un seul cron combiné.
            if (frequency == '15min') {
                return createMultipleSchedules(frequency, new List<Integer>{ 0, 15, 30, 45 });
            }
            if (frequency == '30min') {
                return createMultipleSchedules(frequency, new List<Integer>{ 0, 30 });
            }

            String cronExpression = buildCronExpression(frequency, timeValue);
            String jobName = 'OrgWatchExport_' + frequency;

            if (frequency == 'daily' && String.isNotBlank(timeValue)) {
                jobName += '_' + timeValue.replace(':', 'h');
            }

            return System.schedule(jobName, cronExpression, new OrgWatchExporterScheduler());
        } catch (Exception e) {
            throw new AuraHandledException('Erreur: ' + e.getMessage());
        }
    }

    private static String createMultipleSchedules(String frequency, List<Integer> minutes) {
        String firstJobId = '';
        for (Integer minute : minutes) {
            String jobName = 'OrgWatchExport_' + frequency + '_' + String.valueOf(minute).leftPad(2, '0');
            String cronExpression = '0 ' + minute + ' * * * ?';
            String jobId = System.schedule(jobName, cronExpression, new OrgWatchExporterScheduler());
            if (firstJobId == '') {
                firstJobId = jobId;
            }
        }
        return firstJobId;
    }

    @AuraEnabled
    public static void deleteSchedule(String jobId) {
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
        if (jobs.isEmpty() || !jobs[0].CronJobDetail.Name.startsWith('OrgWatchExport')) {
            throw new AuraHandledException('Ce job ne peut pas être supprimé depuis cet outil.');
        }
    }

    @TestVisible
    private static String buildCronExpression(String frequency, String timeValue) {
        String cronExp = '';

        if (frequency == 'hourly') {
            cronExp = '0 0 * * * ?';
        } else if (frequency == 'daily') {
            if (String.isBlank(timeValue)) {
                timeValue = '02:00';
            }
            List<String> timeParts = timeValue.split(':');
            String hour = timeParts[0];
            String minute = timeParts.size() > 1 ? timeParts[1] : '0';
            cronExp = '0 ' + minute + ' ' + hour + ' * * ?';
        }

        return cronExp;
    }

    private static String parseCronToFrequency(String cronExpression) {
        if (String.isBlank(cronExpression)) {
            return 'Non défini';
        }

        List<String> parts = cronExpression.split(' ');
        if (parts.size() < 6) {
            return 'Non défini';
        }

        String minutes = parts[1];
        String hours = parts[2];

        // Jobs créés par createMultipleSchedules (15min/30min) : chacun tourne
        // toutes les heures à une minute fixe, ensemble ils forment l'intervalle.
        if (hours == '*' && (minutes == '0' || minutes == '15' || minutes == '30' || minutes == '45')) {
            return 'Toutes les heures (minute ' + minutes + ')';
        }

        if (hours != '*' && minutes != '*') {
            return 'Quotidien à ' + hours + ':' + (minutes.length() == 1 ? '0' + minutes : minutes);
        }

        return 'Personnalisé';
    }

    public class ScheduleInfo {
        @AuraEnabled public String jobId;
        @AuraEnabled public String jobName;
        @AuraEnabled public String cronExpression;
        @AuraEnabled public String state;
        @AuraEnabled public DateTime nextRun;
        @AuraEnabled public DateTime previousRun;
        @AuraEnabled public String frequency;
    }
}