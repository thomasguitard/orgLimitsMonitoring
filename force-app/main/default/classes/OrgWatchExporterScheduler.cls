/**
 * Job planifié d'export des limites de l'org.
 *
 * Sans partage : job système qui écrit dans la bibliothèque OrgWatch pour le
 * compte de l'org entière, pas pour le compte d'un utilisateur.
 */
public without sharing class OrgWatchExporterScheduler implements Schedulable {

    public class OrgWatchExportException extends Exception {}

    public void execute(SchedulableContext sc) {
        // Volontairement NON silencieux : un export qui échoue en boucle sans
        // rien signaler (bibliothèque supprimée, stockage de fichiers plein)
        // laissait l'outil paraître fonctionnel avec des données figées. En
        // laissant remonter l'erreur, l'échec devient visible dans
        // Configuration > Tâches Apex et déclenche la notification d'erreur
        // Apex de l'org. Un échec ne déplanifie pas le job : la prochaine
        // exécution aura lieu normalement.
        if (!OrgWatchExporter.exportLimitsToLibrary()) {
            throw new OrgWatchExportException(
                'Export OrgWatch en échec : bibliothèque "' + OrgWatchController.getLibraryName()
                + '" introuvable ou écriture impossible. Lancer "Initialiser OrgWatch"'
                + ' depuis l\'onglet Admin, puis vérifier le stockage de fichiers de l\'org.'
            );
        }
    }
}