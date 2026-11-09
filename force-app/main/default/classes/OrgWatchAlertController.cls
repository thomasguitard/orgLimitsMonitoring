public with sharing class OrgWatchAlertController {

    private static final String ALERT_JOB_PREFIX = 'OrgWatchAlert_Daily_';
    private static final String DEFAULT_ALERT_TIME = '15:00';

    public class AlertPreferences {
        @AuraEnabled public String metricThresholds = '';
        @AuraEnabled public String emailMode = 'OnlyOnBreach';
        @AuraEnabled public Boolean hasActiveExportSchedule = false;
        @AuraEnabled public String alertSendTime = DEFAULT_ALERT_TIME;
    }

    /**
     * Lue depuis le Custom Setting Hierarchy (org-default) : la valeur configurée
     * doit survivre même quand le job quotidien est actuellement inactif (aucune
     * alerte configurée -> pas de CronTrigger actif dont on pourrait relire l'heure).
     */
    public static String getConfiguredAlertTime() {
        String configuredTime = OrgWatch_Settings__c.getOrgDefaults().Alert_Send_Time__c;
        return String.isNotBlank(configuredTime) ? configuredTime : DEFAULT_ALERT_TIME;
    }

    @AuraEnabled(cacheable=true)
    public static AlertPreferences getAlertPreferences() {
        OrgWatchController.assertOrgWatchAccess();
        AlertPreferences result = new AlertPreferences();

        OrgWatchController.UserPreferences prefs = OrgWatchController.readAllPreferences().get(UserInfo.getUserId());
        if (prefs != null) {
            result.metricThresholds = prefs.metricThresholds;
            result.emailMode = prefs.emailMode;
        }

        result.hasActiveExportSchedule = OrgWatchScheduleController.hasActiveExportSchedule();
        result.alertSendTime = getConfiguredAlertTime();

        return result;
    }

    @AuraEnabled
    public static String saveAlertPreferences(String metricThresholds, String emailMode) {
        OrgWatchController.assertOrgWatchAccess();
        String result = OrgWatchController.saveUserPreferencesFull(null, metricThresholds, emailMode);
        if (result == 'SUCCESS') {
            ensureAlertJobState();
        }
        return result;
    }

    @AuraEnabled
    public static String disableAllAlerts() {
        OrgWatchController.assertOrgWatchAccess();
        String result = OrgWatchController.saveUserPreferencesFull(null, '', null);
        if (result == 'SUCCESS') {
            ensureAlertJobState();
        }
        return result;
    }

    /**
     * Crée le job d'alerting quotidien s'il n'existe pas et qu'au moins un
     * utilisateur a désormais un seuil actif ; l'abort s'il existe alors que
     * plus personne n'a d'alerte configurée. Ne lève jamais d'exception vers
     * l'appelant : une erreur ici ne doit pas faire échouer la sauvegarde des
     * préférences qui vient de réussir. Public : OrgWatchAdminController
     * l'appelle aussi après avoir désactivé les alertes d'un autre utilisateur.
     */
    public static void ensureAlertJobState() {
        try {
            Boolean anyoneHasAlerts = false;
            for (OrgWatchController.UserPreferences p : OrgWatchController.readAllPreferences().values()) {
                if (String.isNotBlank(p.metricThresholds)) {
                    anyoneHasAlerts = true;
                    break;
                }
            }

            List<CronTrigger> jobs = [
                SELECT Id
                FROM CronTrigger
                WHERE CronJobDetail.Name LIKE :(ALERT_JOB_PREFIX + '%')
                AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING', 'PAUSED')
            ];
            Boolean jobActive = !jobs.isEmpty();

            if (anyoneHasAlerts && !jobActive) {
                scheduleAlertJob(getConfiguredAlertTime());
            } else if (!anyoneHasAlerts && jobActive) {
                System.abortJob(jobs[0].Id);
            }
        } catch (Exception e) {
            System.debug('Error ensuring alert job state: ' + e.getMessage());
        }
    }

    /**
     * Appelée par OrgWatchAdminController après un changement de l'heure
     * configurée : ensureAlertJobState() seule ne réagit qu'à un changement
     * d'état actif/inactif, pas à un changement d'heure sur un job déjà actif.
     * On abort donc systématiquement le job actif (s'il y en a un) avant de
     * laisser ensureAlertJobState() le recréer à la nouvelle heure si besoin.
     */
    public static void forceRescheduleAtConfiguredTime() {
        try {
            List<CronTrigger> jobs = [
                SELECT Id
                FROM CronTrigger
                WHERE CronJobDetail.Name LIKE :(ALERT_JOB_PREFIX + '%')
                AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING', 'PAUSED')
            ];
            for (CronTrigger job : jobs) {
                System.abortJob(job.Id);
            }
        } catch (Exception e) {
            System.debug('Error aborting alert job for reschedule: ' + e.getMessage());
        }
        ensureAlertJobState();
    }

    private static void scheduleAlertJob(String timeValue) {
        List<String> timeParts = timeValue.split(':');
        String hour = timeParts[0];
        String minute = timeParts.size() > 1 ? timeParts[1] : '0';
        String cronExpression = '0 ' + minute + ' ' + hour + ' * * ?';
        String jobName = ALERT_JOB_PREFIX + timeValue.replace(':', 'h');
        System.schedule(jobName, cronExpression, new OrgWatchAlertScheduler());
    }
}