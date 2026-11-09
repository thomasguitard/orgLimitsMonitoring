/**
 * Installation, contrôle de santé et préparation à la désinstallation de
 * OrgWatch.
 *
 * OrgWatch est distribué en unlocked package : Salesforce n'exécute donc
 * AUCUN script à l'installation ni à la désinstallation (les interfaces
 * InstallHandler / UninstallHandler ne sont disponibles que pour les managed
 * packages). Tout ce qui doit être créé après une installation, ou nettoyé
 * avant une désinstallation, passe donc par cette classe, appelée depuis
 * l'onglet Admin.
 *
 * Deux raisons rendent ces actions indispensables plutôt que confortables :
 *
 * 1. La bibliothèque de fichiers ne peut pas être livrée dans un package
 *    (ContentWorkspace n'est pas une métadonnée). Elle ne peut pas non plus
 *    être créée à la volée par l'export : ContentWorkspace est un "setup
 *    object", donc l'insérer puis insérer un ContentVersion dans la même
 *    transaction lève MIXED_DML_OPERATION. Elle doit être créée seule, dans
 *    sa propre transaction : c'est ce que fait runSetup().
 *
 * 2. Les jobs planifiés (export, purge, alertes) référencent des classes Apex
 *    du package. Tant qu'ils existent, la suppression de ces classes est
 *    refusée par la plateforme, ce qui fait échouer la désinstallation. Ils
 *    doivent être arrêtés AVANT : c'est ce que fait prepareUninstall().
 */
public with sharing class OrgWatchSetupController {

    // Tous les jobs planifiés par l'outil sont préfixés ainsi. Les noms de
    // CronTrigger ne sont pas préfixés par un namespace, même dans un package :
    // ce préfixe est donc le seul moyen de les retrouver de façon fiable, dans
    // l'org d'un client comme dans Setup > Jobs planifiés.
    @TestVisible
    private static final String JOB_NAME_PREFIX = 'OrgWatch';
    private static final Integer DELETE_BATCH_SIZE = 200;

    /**
     * État de l'installation, à afficher comme une check-list après un
     * déploiement chez un client. Purement en lecture.
     */
    @AuraEnabled
    public static SetupStatus getSetupStatus() {
        OrgWatchController.assertOrgWatchAdmin();

        SetupStatus status = new SetupStatus();
        status.libraryName = OrgWatchController.getLibraryName();
        status.libraryExists = findLibraryId() != null;
        status.chartLibraryPresent = ![SELECT Id FROM StaticResource WHERE Name = 'chartjs' LIMIT 1].isEmpty();

        for (CronTrigger job : queryOrgWatchJobs()) {
            status.scheduledJobNames.add(job.CronJobDetail.Name);
        }
        status.scheduledJobCount = status.scheduledJobNames.size();
        status.exportFileCount = countExportFiles();

        return status;
    }

    /**
     * Idempotent : crée ce qui manque, ne touche pas à ce qui existe. Peut
     * être relancé sans risque après une mise à jour du package.
     *
     * N'effectue volontairement qu'un seul type de DML (ContentWorkspace) :
     * y ajouter l'écriture d'un autre objet lèverait MIXED_DML_OPERATION.
     * L'enregistrement OrgWatch_Settings__c n'a pas besoin d'être créé ici,
     * getOrgDefaults() renvoie déjà les valeurs par défaut du champ.
     */
    @AuraEnabled
    public static SetupResult runSetup() {
        OrgWatchController.assertOrgWatchAdmin();

        SetupResult result = new SetupResult();
        result.libraryName = OrgWatchController.getLibraryName();

        try {
            if (findLibraryId() != null) {
                result.libraryAlreadyExisted = true;
            } else {
                insert new ContentWorkspace(
                    Name = OrgWatchController.getLibraryName(),
                    Description = 'Bibliothèque des exports OrgWatch (limites de l\'org).',
                    // INDISPENSABLE : la visibilité d'une bibliothèque en SOQL
                    // dépend uniquement de l'appartenance - ni les permissions
                    // de gestion de contenu, ni "without sharing", ni
                    // AccessLevel.SYSTEM_MODE ne la contournent. Sans ce
                    // drapeau, le créateur n'est pas membre : la bibliothèque
                    // est créée mais invisible dès sa création, la check-list
                    // l'annonce "Absente", et tout nouvel essai d'initialisation
                    // échoue en DUPLICATE_VALUE puisque le nom est bien pris.
                    ShouldAddCreatorMembership = true
                );
                result.libraryCreated = true;
            }
            result.success = true;
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage();

            // Cas piégeux : le nom est déjà pris à l'échelle de l'org par une
            // bibliothèque que l'outil ne peut pas voir (supprimée mais encore
            // en corbeille, ou dont l'appelant n'est pas membre - la visibilité
            // des bibliothèques échappe au partage Apex). La check-list affiche
            // alors "Absente" et ce bouton échoue en boucle : sans explication,
            // l'admin n'a aucun moyen de deviner quoi faire.
            if (!String.isBlank(result.errorMessage)
                && result.errorMessage.containsIgnoreCase('DUPLICATE_VALUE')) {

                // Le nom est pris par une bibliothèque que personne ne voit :
                // on tente de la récupérer plutôt que d'en créer une seconde
                // sous un autre nom, ce qui disperserait les exports.
                Id adopted = adoptOrphanLibrary(result.libraryName);
                if (adopted != null) {
                    result.success = true;
                    result.libraryAlreadyExisted = true;
                    result.libraryAdopted = true;
                    result.errorMessage = null;
                    return result;
                }

                result.libraryNameTaken = true;
                result.errorMessage =
                    'La bibliothèque "' + result.libraryName + '" existe déjà dans cette org, mais vous n\'en'
                    + ' êtes pas membre : OrgWatch ne peut donc pas la voir (la visibilité d\'une bibliothèque'
                    + ' dépend de l\'appartenance, pas des permissions). Ouvrez Fichiers > Bibliothèques >'
                    + ' "' + result.libraryName + '" > Gérer les membres, ajoutez-vous, puis relancez.'
                    + ' / Library "' + result.libraryName + '" already exists in this org, but you are not a'
                    + ' member, so OrgWatch cannot see it. Open Files > Libraries > "' + result.libraryName
                    + '" > Manage Members, add yourself, then run Initialize again.';
            }
        }

        return result;
    }

    /**
     * Démarre la collecte de données si aucun export n'est encore planifié,
     * pour qu'un client n'ait pas de dashboard vide après l'installation.
     *
     * Appelée par le LWC juste APRÈS runSetup(), jamais depuis la même
     * méthode : System.schedule() insère un CronTrigger, et le combiner à
     * l'insert ContentWorkspace de runSetup() dans une même transaction
     * relèverait MIXED_DML_OPERATION (ContentWorkspace est lui-même traité
     * comme un "setup object" par Apex - cf. le commentaire de classe).
     *
     * Idempotente : ne crée rien si un export planifié existe déjà, quelle
     * que soit sa fréquence (peut avoir été configuré manuellement avant).
     */
    @AuraEnabled
    public static ScheduleResult ensureDefaultExportSchedule() {
        OrgWatchController.assertOrgWatchAdmin();

        ScheduleResult result = new ScheduleResult();

        if (OrgWatchScheduleController.hasActiveExportSchedule()) {
            result.alreadyActive = true;
            result.success = true;
            return result;
        }

        try {
            OrgWatchScheduleController.createSchedule('hourly', null);
            result.created = true;
            result.success = true;
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage();
        }

        return result;
    }

    /**
     * À lancer AVANT de désinstaller le package : arrête tous les jobs
     * planifiés d'OrgWatch. Sans ça, la plateforme refuse de supprimer les
     * classes Apex encore référencées par un job et la désinstallation échoue.
     */
    @AuraEnabled
    public static UninstallPrepResult prepareUninstall() {
        OrgWatchController.assertOrgWatchAdmin();

        UninstallPrepResult result = new UninstallPrepResult();

        for (CronTrigger job : queryOrgWatchJobs()) {
            String jobName = job.CronJobDetail.Name;
            try {
                System.abortJob(job.Id);
                result.abortedJobNames.add(jobName);
            } catch (Exception e) {
                // Un job déjà terminé entre la requête et l'abandon n'est pas
                // une erreur bloquante : on le signale sans interrompre le
                // nettoyage des autres.
                result.failedJobNames.add(jobName + ' (' + e.getMessage() + ')');
            }
        }

        result.abortedCount = result.abortedJobNames.size();
        result.remainingFileCount = countExportFiles();
        result.success = result.failedJobNames.isEmpty();
        return result;
    }

    /**
     * Supprime les données laissées derrière par OrgWatch. Rien de tout cela
     * ne part avec le package : les fichiers CSV et la bibliothèque sont des
     * données client (objets standard), ils survivent à la désinstallation et
     * continuent de consommer du stockage de fichiers.
     *
     * Destructif et irréversible : l'appelant doit confirmer explicitement.
     *
     * @param deleteLibrary supprime aussi la bibliothèque elle-même, une fois
     *        ses fichiers supprimés.
     */
    @AuraEnabled
    public static DataCleanupResult deleteAllOrgWatchData(Boolean deleteLibrary) {
        OrgWatchController.assertOrgWatchAdmin();

        DataCleanupResult result = new DataCleanupResult();

        // Des fichiers déjà passés à la corbeille (exécution précédente,
        // suppression manuelle) empêchent la suppression de la bibliothèque
        // même quand plus aucun fichier n'y est lié - Salesforce refuse tant
        // que sa corbeille contient du contenu supprimé (DEPENDENCY_EXISTS).
        // On la purge donc en premier, avant même de chercher la bibliothèque.
        purgeRecycledOrgWatchFiles(result);

        Id libraryId = findLibraryId();
        if (libraryId == null) {
            result.success = result.errors.isEmpty();
            return result;
        }

        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :libraryId
            LIMIT 10000
        ]) {
            docIds.add(cdl.ContentDocumentId);
        }

        List<ContentDocument> toDelete = new List<ContentDocument>();
        for (Id docId : docIds) {
            toDelete.add(new ContentDocument(Id = docId));
            if (toDelete.size() == DELETE_BATCH_SIZE) {
                result.deletedFileCount += deleteChunk(toDelete, result);
                toDelete.clear();
            }
        }
        if (!toDelete.isEmpty()) {
            result.deletedFileCount += deleteChunk(toDelete, result);
        }

        // La bibliothèque ne peut être supprimée qu'une fois vidée : s'il
        // reste des fichiers (limites de gouverneur, échecs), on la conserve
        // et l'admin relance l'action.
        result.remainingFileCount = countExportFiles();
        if (deleteLibrary == true && result.remainingFileCount == 0 && result.errors.isEmpty()) {
            // Ne peut pas être supprimée dans CETTE transaction : ContentWorkspace
            // est un "setup object" pour Apex, et cette même transaction vient de
            // faire du DML sur ContentDocument (non-setup) juste au-dessus -
            // MIXED_DML_OPERATION. Comme pour sa création (cf. le commentaire de
            // classe), elle doit être isolée dans sa propre transaction ; hors
            // contexte de test, System.runAs() n'existe pas, on utilise donc un
            // @future.
            deleteLibraryAsync(libraryId);
            result.libraryDeletionQueued = true;
        }

        result.success = result.errors.isEmpty();
        return result;
    }

    /**
     * Sans partage, explicitement : l'admin qui déclenche la suppression
     * n'est pas forcément lui-même membre de la bibliothèque (cf.
     * LibrarySync dans OrgWatchAdminController). Ne peut pas remonter
     * d'erreur à l'appelant (contexte @future) : un échec reste visible dans
     * Configuration > Tâches Apex, et la check-list de l'onglet Admin
     * continue d'afficher la bibliothèque comme présente si besoin.
     */
    @future
    private static void deleteLibraryAsync(Id libraryId) {
        try {
            new LibraryDeleter().deleteById(libraryId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'OrgWatch: échec de la suppression différée de la bibliothèque: ' + e.getMessage());
        }
    }

    private without sharing class LibraryDeleter {
        /**
         * Suppression DÉFINITIVE, et pas un simple passage à la corbeille :
         * une ContentWorkspace supprimée y conserve son nom (unique à
         * l'échelle de l'org) tout en devenant introuvable en SOQL - l'objet
         * n'expose même pas IsDeleted, donc ALL ROWS ne la ramène pas non
         * plus, et AccessLevel.SYSTEM_MODE n'y change rien. Sans cette purge,
         * "Initialiser OrgWatch" échouait ensuite définitivement sur
         * DUPLICATE_VALUE alors que la check-list annonçait la bibliothèque
         * comme absente : l'outil ne pouvait plus jamais recréer la sienne.
         */
        private void deleteById(Id libraryId) {
            ContentWorkspace library = new ContentWorkspace(Id = libraryId);
            delete library;

            for (Database.EmptyRecycleBinResult r : Database.emptyRecycleBin(new List<ContentWorkspace>{ library })) {
                if (!r.isSuccess() && !r.getErrors().isEmpty()) {
                    String message = r.getErrors()[0].getMessage();
                    // Déjà purgée définitivement : rien à corriger.
                    if (!String.isBlank(message) && message.containsIgnoreCase('no recycle bin entry found')) {
                        continue;
                    }
                    System.debug(LoggingLevel.ERROR, 'OrgWatch: purge définitive de la bibliothèque incomplète: ' + message);
                }
            }
        }
    }

    private static Integer deleteChunk(List<ContentDocument> chunk, DataCleanupResult result) {
        Integer deleted = 0;
        List<ContentDocument> toPurge = new List<ContentDocument>();

        Database.DeleteResult[] deleteResults = Database.delete(chunk, false);
        for (Integer i = 0; i < deleteResults.size(); i++) {
            Database.DeleteResult dr = deleteResults[i];
            if (dr.isSuccess()) {
                deleted++;
                toPurge.add(chunk[i]);
            } else if (!dr.getErrors().isEmpty()) {
                result.errors.add(dr.getErrors()[0].getMessage());
            }
        }

        // Suppression définitive, pas un simple passage à la corbeille :
        // cohérent avec l'avertissement "suppression définitive" affiché à
        // l'admin avant de confirmer, et évite qu'un contenu recyclé bloque
        // ensuite la suppression de la bibliothèque (DEPENDENCY_EXISTS).
        purgeFromRecycleBin(toPurge, result);

        return deleted;
    }

    /**
     * Purge définitivement des ContentDocument déjà supprimés (dans la
     * corbeille), en respectant la même taille de lot que les suppressions.
     */
    private static void purgeFromRecycleBin(List<ContentDocument> docs, DataCleanupResult result) {
        if (docs.isEmpty()) return;

        // Apex n'a pas d'équivalent à List.subList() : on découpe à la main.
        Integer offset = 0;
        while (offset < docs.size()) {
            Integer chunkEnd = Math.min(offset + DELETE_BATCH_SIZE, docs.size());
            List<ContentDocument> chunk = new List<ContentDocument>();
            for (Integer i = offset; i < chunkEnd; i++) {
                chunk.add(docs[i]);
            }
            try {
                // Ne lève pas d'exception pour un échec individuel (comme
                // Database.delete) : chaque résultat doit être vérifié.
                for (Database.EmptyRecycleBinResult r : Database.emptyRecycleBin(chunk)) {
                    if (r.isSuccess() || r.getErrors() == null || r.getErrors().isEmpty()) {
                        continue;
                    }
                    String errorMessage = r.getErrors()[0].getMessage();
                    // "no recycle bin entry found" : le fichier était déjà
                    // définitivement purgé (une exécution précédente, ou un
                    // léger délai de la plateforme entre confirmation de
                    // purge et disparition effective des requêtes ALL ROWS -
                    // cf. purgeRecycledOrgWatchFiles). L'état voulu est déjà
                    // atteint, ce n'est pas une vraie erreur à signaler.
                    if (errorMessage != null && errorMessage.containsIgnoreCase('no recycle bin entry found')) {
                        continue;
                    }
                    result.errors.add('Purge définitive incomplète : ' + errorMessage);
                }
            } catch (Exception e) {
                result.errors.add('Purge définitive incomplète : ' + e.getMessage());
            }
            offset = chunkEnd;
        }
    }

    /**
     * Purge tout fichier OrgWatch déjà présent dans la corbeille avant même
     * de commencer, qu'il y ait été déposé par une exécution précédente de
     * cette action ou supprimé manuellement par un admin. ALL ROWS est
     * nécessaire : un ContentDocument supprimé n'est plus retourné par une
     * requête standard, et son ContentDocumentLink vers la bibliothèque a
     * déjà disparu, donc il ne peut plus être retrouvé par association à la
     * bibliothèque - seul son nom de fichier permet de l'identifier ici.
     */
    private static void purgeRecycledOrgWatchFiles(DataCleanupResult result) {
        List<ContentDocument> recycled = [
            SELECT Id
            FROM ContentDocument
            WHERE IsDeleted = true
            AND (Title LIKE 'OrgWatch_Export_%' OR Title = 'OrgWatchUserPreferences.csv')
            LIMIT 10000
            ALL ROWS
        ];
        purgeFromRecycleBin(recycled, result);
    }

    /**
     * Sans partage : la visibilité des bibliothèques de fichiers ne suit pas
     * le modèle de partage Apex (cf. OrgWatchAdminController.LibrarySync),
     * l'admin appelant n'est pas forcément membre de la bibliothèque.
     */
    private static Id findLibraryId() {
        return new LibraryLookup().findId(OrgWatchController.getLibraryName());
    }

    /**
     * Récupère une bibliothèque « orpheline » : une ContentWorkspace créée
     * sans aucun membre est invisible pour TOUT LE MONDE - en SOQL comme dans
     * Fichiers > Bibliothèques - alors que son nom reste pris à l'échelle de
     * l'org. Ni les permissions de gestion de contenu, ni `without sharing`,
     * ni AccessLevel.SYSTEM_MODE ne la font réapparaître : la visibilité d'une
     * bibliothèque dépend uniquement de l'appartenance. L'outil se retrouvait
     * donc définitivement bloqué, sans aucun recours possible depuis Apex.
     *
     * La porte de sortie : ContentFolder et ContentFolderLink, eux, ne sont
     * PAS soumis à l'appartenance. Le dossier racine d'une bibliothèque pointe
     * sur elle via ContentFolderLink.ParentEntityId, ce qui donne son Id. On
     * s'ajoute alors comme membre pour pouvoir enfin lire son nom et vérifier
     * que c'est bien la nôtre - et on retire cette adhésion si ce n'est pas le
     * cas, pour ne rien laisser derrière nous sur la bibliothèque d'autrui.
     */
    private static Id adoptOrphanLibrary(String libraryName) {
        Set<Id> visible = new Set<Id>();
        for (ContentWorkspace w : [SELECT Id FROM ContentWorkspace]) {
            visible.add(w.Id);
        }

        Set<Id> candidates = new Set<Id>();
        for (SObject link : Database.query('SELECT ParentEntityId FROM ContentFolderLink')) {
            Id parentId = (Id) link.get('ParentEntityId');
            if (parentId != null
                && parentId.getSobjectType() == ContentWorkspace.SObjectType
                && !visible.contains(parentId)) {
                candidates.add(parentId);
            }
        }
        if (candidates.isEmpty()) {
            return null;
        }

        Id permissionId = libraryMembershipPermissionId();
        if (permissionId == null) {
            return null;
        }

        for (Id candidateId : candidates) {
            ContentWorkspaceMember membership = new ContentWorkspaceMember(
                ContentWorkspaceId = candidateId,
                ContentWorkspacePermissionId = permissionId,
                MemberId = UserInfo.getUserId()
            );
            try {
                insert membership;
            } catch (Exception e) {
                continue;
            }

            List<ContentWorkspace> found = [SELECT Id, Name FROM ContentWorkspace WHERE Id = :candidateId];
            if (!found.isEmpty() && found[0].Name == libraryName) {
                return candidateId;
            }

            try {
                delete membership;
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'OrgWatch: adhésion de test non retirée sur ' + candidateId + ' : ' + e.getMessage());
            }
        }
        return null;
    }

    /**
     * Palier d'accès à demander pour s'ajouter à la bibliothèque : Admin en
     * premier, car il faut pouvoir la gérer et pas seulement la lire - et
     * c'est fréquemment le seul palier existant dans une org.
     */
    private static Id libraryMembershipPermissionId() {
        for (String permissionType : new List<String>{ 'Admin', 'Author', 'Viewer' }) {
            List<ContentWorkspacePermission> permissions = [
                SELECT Id FROM ContentWorkspacePermission WHERE Type = :permissionType LIMIT 1
            ];
            if (!permissions.isEmpty()) {
                return permissions[0].Id;
            }
        }
        return null;
    }

    private without sharing class LibraryLookup {
        private Id findId(String libraryName) {
            List<ContentWorkspace> found = Database.query(
                'SELECT Id FROM ContentWorkspace WHERE Name = :libraryName LIMIT 1',
                AccessLevel.SYSTEM_MODE
            );
            return found.isEmpty() ? null : found[0].Id;
        }
    }

    private static List<CronTrigger> queryOrgWatchJobs() {
        String namePattern = JOB_NAME_PREFIX + '%';
        return [
            SELECT Id, CronJobDetail.Name, State
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :namePattern
            AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING', 'PAUSED', 'BLOCKED')
            LIMIT 200
        ];
    }

    private static Integer countExportFiles() {
        Id libraryId = findLibraryId();
        if (libraryId == null) {
            return 0;
        }
        return [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :libraryId
        ];
    }

    public class SetupStatus {
        @AuraEnabled public String libraryName;
        @AuraEnabled public Boolean libraryExists = false;
        @AuraEnabled public Boolean chartLibraryPresent = false;
        @AuraEnabled public Integer scheduledJobCount = 0;
        @AuraEnabled public List<String> scheduledJobNames = new List<String>();
        @AuraEnabled public Integer exportFileCount = 0;
    }

    public class SetupResult {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public String libraryName;
        @AuraEnabled public Boolean libraryCreated = false;
        @AuraEnabled public Boolean libraryAlreadyExisted = false;
        @AuraEnabled public Boolean libraryNameTaken = false;
        @AuraEnabled public Boolean libraryAdopted = false;
        @AuraEnabled public String errorMessage;
    }

    public class ScheduleResult {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public Boolean created = false;
        @AuraEnabled public Boolean alreadyActive = false;
        @AuraEnabled public String errorMessage;
    }

    public class UninstallPrepResult {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public Integer abortedCount = 0;
        @AuraEnabled public List<String> abortedJobNames = new List<String>();
        @AuraEnabled public List<String> failedJobNames = new List<String>();
        @AuraEnabled public Integer remainingFileCount = 0;
    }

    public class DataCleanupResult {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public Integer deletedFileCount = 0;
        @AuraEnabled public Integer remainingFileCount = 0;
        // La suppression de la bibliothèque est asynchrone (cf.
        // deleteLibraryAsync) : ce champ indique qu'elle a été mise en file,
        // pas qu'elle est terminée au moment où ce résultat est renvoyé.
        @AuraEnabled public Boolean libraryDeletionQueued = false;
        @AuraEnabled public List<String> errors = new List<String>();
    }
}