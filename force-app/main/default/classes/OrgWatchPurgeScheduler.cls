/**
 * Job planifie de purge des exports OrgWatch trop anciens.
 *
 * Sans partage, explicitement : job systeme agissant sur les fichiers de
 * l'org, pas sur ceux d'un utilisateur.
 */
public without sharing class OrgWatchPurgeScheduler implements Schedulable {

    private static final Integer DEFAULT_AGE_DAYS = 90;

    private Integer ageDays;

    public OrgWatchPurgeScheduler(Integer ageDays) {
        this.ageDays = ageDays != null ? ageDays : DEFAULT_AGE_DAYS;
    }

    /**
     * Volontairement pas de try/catch autour de la purge : si elle échoue
     * (bibliothèque introuvable, suppressions en échec, ...), l'exception
     * remonte pour que ce passage soit marqué "Failed" (visible dans le
     * panneau "Purge automatique" via AsyncApexJob) et que Salesforce envoie
     * l'email d'échec automatique au propriétaire du job planifié.
     */
    public void execute(SchedulableContext sc) {
        DateTime cutoffDate = DateTime.now().addDays(-this.ageDays);
        OrgWatchPurgeController.PurgeResult result = OrgWatchPurgeController.purgeFilesOlderThan(cutoffDate);

        if (!result.errors.isEmpty() || result.failedCount > 0) {
            throw new OrgWatchPurgeException(
                'Purge automatique en échec (' + result.failedCount + ' échec(s)) : ' + String.join(result.errors, ' | ')
            );
        }
    }

    public class OrgWatchPurgeException extends Exception {}
}