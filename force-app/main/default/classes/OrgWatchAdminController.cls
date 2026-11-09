public with sharing class OrgWatchAdminController {

    private static final String PS_USER = 'OrgWatch_User';
    private static final String PS_ADMIN = 'OrgWatch_Admin';
    private static final String DEFAULT_LANGUAGE = 'fr';
    // Paliers d'accès bibliothèque par ordre de préférence (du moins au plus
    // privilégié) : cf. LibrarySync.getPermissionId(). 'Custom' est
    // volontairement absent, son contenu est imprévisible d'une org à l'autre.
    private static final List<String> LIBRARY_PERMISSION_TYPES_BY_PREFERENCE =
        new List<String>{ 'Viewer', 'Author', 'Admin' };
    private static final String LIBRARY_NAME = Test.isRunningTest() ? 'OrgWatch Reporting TEST' : 'OrgWatch Reporting';

    @TestVisible private static Integer lastNotificationEmailsSent = -1;
    @TestVisible private static Integer lastAccessChangeEmailsSent = -1;
    @TestVisible private static String lastAccessChangeEmailHtmlBody;
    @TestVisible private static String lastAccessChangeEmailSubject;
    @TestVisible private static String lastNotificationEmailHtmlBody;

    private static final Map<String, Map<String, String>> ADMIN_EMAIL_TEXT = new Map<String, Map<String, String>>{
        'greetingPrefix' => new Map<String, String>{ 'fr' => 'Bonjour ', 'en' => 'Hello ' },
        'goToAppButton' => new Map<String, String>{ 'fr' => 'Ouvrir OrgWatch', 'en' => 'Open OrgWatch' },

        // Octroi de l'accès standard à un tout nouvel utilisateur : ton
        // chaleureux, explique ce que l'outil permet de faire concrètement.
        'welcomeNewSubject' => new Map<String, String>{ 'fr' => 'Bienvenue sur OrgWatch !', 'en' => 'Welcome to OrgWatch!' },
        'welcomeNewBody' => new Map<String, String>{
            'fr' => ', un administrateur vient de vous donner accès à OrgWatch, l\'outil de suivi des limites de votre org Salesforce. Vous pourrez y suivre l\'évolution de vos métriques (stockage, appels API, emails...), configurer des alertes par seuil sur celles qui vous intéressent, et recevoir un récapitulatif quotidien par email si vous le souhaitez. Bonne découverte !',
            'en' => ', an administrator just gave you access to OrgWatch, the tool for monitoring your Salesforce org limits. You can track how your metrics evolve (storage, API calls, emails...), set threshold-based alerts on the ones you care about, and get a daily summary email if you\'d like. Enjoy exploring it!'
        },

        // Octroi de l'accès standard à quelqu'un qui l'avait déjà eu par le
        // passé (préférences existantes retrouvées) : ton plus bref, pas de
        // "bienvenue" pour quelqu'un qui connaît déjà l'outil.
        'accessRestoredSubject' => new Map<String, String>{ 'fr' => 'Votre accès OrgWatch a été réactivé', 'en' => 'Your OrgWatch access has been restored' },
        'accessRestoredBody' => new Map<String, String>{
            'fr' => ', un administrateur vient de réactiver votre accès à OrgWatch. Vos anciennes préférences (métriques affichées, seuils d\'alerte, langue) ont été conservées.',
            'en' => ', an administrator just restored your access to OrgWatch. Your previous preferences (displayed metrics, alert thresholds, language) have been kept.'
        },

        'adminGrantedSubject' => new Map<String, String>{ 'fr' => 'Accès Admin OrgWatch activé', 'en' => 'OrgWatch Admin access granted' },
        'adminGrantedBody' => new Map<String, String>{
            'fr' => ', un administrateur vient de vous donner l\'accès Admin à OrgWatch. Vous pouvez désormais, depuis l\'onglet Admin : donner ou retirer l\'accès à d\'autres utilisateurs, désactiver les alertes d\'un utilisateur en particulier, et configurer l\'heure d\'envoi du mail récapitulatif quotidien.',
            'en' => ', an administrator just gave you Admin access to OrgWatch. From the Admin tab, you can now: grant or remove access for other users, disable a specific user\'s alerts, and configure the daily summary email\'s send time.'
        },

        'adminRevokedSubject' => new Map<String, String>{ 'fr' => 'Accès Admin OrgWatch retiré', 'en' => 'OrgWatch Admin access removed' },
        'adminRevokedBody' => new Map<String, String>{
            'fr' => ', un administrateur a retiré votre accès Admin à OrgWatch. Vous conservez votre accès standard : vous pouvez toujours consulter vos métriques et gérer vos propres alertes, mais l\'onglet Admin n\'est plus disponible.',
            'en' => ', an administrator removed your Admin access to OrgWatch. You keep your standard access: you can still view your metrics and manage your own alerts, but the Admin tab is no longer available.'
        },

        // Retrait complet (plus aucune PS) : "au revoir", pas de bouton vers
        // l'app puisque l'utilisateur n'y a justement plus accès.
        'goodbyeSubject' => new Map<String, String>{ 'fr' => 'Votre accès OrgWatch a été retiré', 'en' => 'Your OrgWatch access has been removed' },
        'goodbyeBody' => new Map<String, String>{
            'fr' => ', un administrateur a retiré votre accès à OrgWatch. Vous ne recevrez plus d\'alertes ni de mail récapitulatif, et vos préférences enregistrées (métriques masquées, seuils, langue) ont été supprimées. Merci d\'avoir utilisé OrgWatch !',
            'en' => ', an administrator removed your access to OrgWatch. You will no longer receive alerts or the summary email, and your saved preferences (hidden metrics, thresholds, language) have been deleted. Thank you for using OrgWatch!'
        },

        'alertsDisabledSubject' => new Map<String, String>{ 'fr' => 'Vos alertes OrgWatch ont été désactivées', 'en' => 'Your OrgWatch alerts have been disabled' },
        'alertsDisabledBody' => new Map<String, String>{
            'fr' => ', un administrateur a désactivé vos alertes de limites Org dans OrgWatch. Vous conservez votre accès à l\'application ; vous ne recevrez plus le mail récapitulatif tant que vous n\'aurez pas reconfiguré au moins un seuil dans l\'onglet Alertes.',
            'en' => ', an administrator disabled your Org limits alerts in OrgWatch. You keep your access to the app; you will no longer receive the summary email until you configure at least one threshold again in the Alerts tab.'
        }
    };

    private static String t(String key, String lang) {
        Map<String, String> entry = ADMIN_EMAIL_TEXT.get(key);
        if (entry == null) return '';
        String value = entry.get(lang);
        return value != null ? value : entry.get(DEFAULT_LANGUAGE);
    }

    private static String resolveLanguage(Id targetUserId) {
        OrgWatchController.UserPreferences prefs = OrgWatchController.readAllPreferences().get(targetUserId);
        return (prefs != null && String.isNotBlank(prefs.language)) ? prefs.language : DEFAULT_LANGUAGE;
    }

    /**
     * Deuxième verrou en plus de l'accès à la classe (accordée uniquement via
     * le Permission Set "OrgWatch - Admin") : cette classe peut modifier les
     * accès et les préférences d'autres utilisateurs, donc chaque méthode
     * revérifie explicitement la permission côté serveur plutôt que de faire
     * confiance au seul appel côté client à isAdminUser().
     */
    private static void assertAdmin() {
        OrgWatchController.assertOrgWatchAdmin();
    }

    // Pas de cacheable=true : cette liste est rafraîchie juste après des
    // actions (octroi/retrait de PS...) qui modifient son contenu - un appel
    // impératif à une méthode cacheable peut renvoyer un résultat mis en
    // cache côté client antérieur à ces changements (l'utilisateur semble
    // alors disparaître de la liste jusqu'à un rafraîchissement complet).
    @AuraEnabled
    public static List<UserAccessRow> getUserAccessOverview() {
        assertAdmin();

        Set<Id> userPsAssignees = permissionSetAssigneeIds(PS_USER);
        Set<Id> adminPsAssignees = permissionSetAssigneeIds(PS_ADMIN);
        Map<String, OrgWatchController.UserPreferences> allPrefs = OrgWatchController.readAllPreferences();

        Set<Id> relevantUserIds = new Set<Id>();
        relevantUserIds.addAll(userPsAssignees);
        relevantUserIds.addAll(adminPsAssignees);
        for (String uid : allPrefs.keySet()) {
            if (String.isNotBlank(allPrefs.get(uid).metricThresholds)) {
                relevantUserIds.add((Id) uid);
            }
        }

        if (relevantUserIds.isEmpty()) {
            return new List<UserAccessRow>();
        }

        List<User> users = [
            SELECT Id, Name, Email
            FROM User
            WHERE Id IN :relevantUserIds
            ORDER BY Name
        ];

        return buildRows(users, userPsAssignees, adminPsAssignees, allPrefs);
    }

    @AuraEnabled
    public static List<UserAccessRow> searchUsers(String searchTerm) {
        assertAdmin();

        if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
            return new List<UserAccessRow>();
        }

        String term = '%' + searchTerm.trim() + '%';
        List<User> users = [
            SELECT Id, Name, Email
            FROM User
            WHERE IsActive = true
            AND UserType = 'Standard'
            AND Name LIKE :term
            ORDER BY Name
            LIMIT 25
        ];

        Set<Id> userPsAssignees = permissionSetAssigneeIds(PS_USER);
        Set<Id> adminPsAssignees = permissionSetAssigneeIds(PS_ADMIN);
        Map<String, OrgWatchController.UserPreferences> allPrefs = OrgWatchController.readAllPreferences();

        return buildRows(users, userPsAssignees, adminPsAssignees, allPrefs);
    }

    private static List<UserAccessRow> buildRows(List<User> users, Set<Id> userPsAssignees, Set<Id> adminPsAssignees, Map<String, OrgWatchController.UserPreferences> allPrefs) {
        List<UserAccessRow> rows = new List<UserAccessRow>();
        for (User u : users) {
            UserAccessRow row = new UserAccessRow();
            row.userId = u.Id;
            row.name = u.Name;
            row.email = u.Email;
            row.hasUserPS = userPsAssignees.contains(u.Id);
            row.hasAdminPS = adminPsAssignees.contains(u.Id);

            OrgWatchController.UserPreferences prefs = allPrefs.get(u.Id);
            row.hasAlertsConfigured = prefs != null && String.isNotBlank(prefs.metricThresholds);
            row.alertEmailMode = prefs != null ? prefs.emailMode : null;

            rows.add(row);
        }
        return rows;
    }

    /**
     * NB : PermissionSetAssignment ne supporte ni les triggers Apex ni le
     * Change Data Capture (restriction de plateforme confirmée, sans
     * contournement natif) - la notification et la synchronisation de
     * l'accès bibliothèque ne peuvent donc se déclencher que depuis cette
     * action explicite de l'onglet Admin, pas depuis un ajout/retrait fait
     * directement dans Setup.
     */
    @AuraEnabled
    public static void setPermissionSetAssignment(Id targetUserId, String permissionSetName, Boolean assign) {
        assertAdmin();

        if (permissionSetName != PS_USER && permissionSetName != PS_ADMIN) {
            throw new AuraHandledException('Permission Set non autorisé pour cette action.');
        }

        try {
            // Capturée avant tout changement : au retrait complet, les
            // préférences (et donc la langue enregistrée) sont supprimées,
            // il faut connaître la langue avant de perdre cette information.
            String lang = resolveLanguage(targetUserId);

            if (assign) {
                // "Nouveau" utilisateur = aucune ligne de préférences retrouvée avant
                // cet octroi (une ligne n'existe que si l'utilisateur a déjà utilisé
                // l'app, donc déjà eu OrgWatch_User par le passé) : ton d'accueil
                // différent d'une simple réactivation.
                Boolean isNewUser = permissionSetName == PS_USER
                    && !OrgWatchController.readAllPreferences().containsKey(targetUserId);
                Boolean changed = grantPermissionSet(targetUserId, permissionSetName);

                // Réciproque du retrait ci-dessous : "OrgWatch - Admin" est
                // additive et ne porte ni la visibilité de l'onglet ni l'accès
                // à OrgWatchController. Accordée seule, elle ne donne donc
                // accès à rien - un état incohérent que l'admin ne peut pas
                // deviner depuis le tableau. On accorde l'accès de base avec.
                // Une seule action admin reste une seule notification : celle
                // de l'octroi Admin, qui est l'action réellement demandée.
                if (permissionSetName == PS_ADMIN) {
                    changed = grantPermissionSet(targetUserId, PS_USER) || changed;
                }

                if (changed) {
                    sendAccessChangeNotification(targetUserId, permissionSetName, true, lang, isNewUser);
                }
            } else if (permissionSetName == PS_USER) {
                // "OrgWatch - Admin" est additive : sans la PS de base "OrgWatch - User",
                // elle ne donne plus accès à rien. On les retire ensemble pour éviter
                // un état incohérent (l'UI prévient l'admin avant l'appel) mais on
                // n'envoie qu'un seul email reflétant la perte complète d'accès,
                // pas deux notifications distinctes pour une seule action admin.
                Boolean userChanged = revokePermissionSet(targetUserId, PS_USER);
                Boolean adminChanged = revokePermissionSet(targetUserId, PS_ADMIN);
                if (userChanged || adminChanged) {
                    // Plus aucune PS -> ce n'est plus un utilisateur de l'app : ses
                    // données (métriques masquées, seuils, langue) n'ont plus lieu
                    // d'exister, pas seulement ses seuils d'alerte.
                    OrgWatchController.removePreferencesForUser(targetUserId);
                    sendAccessChangeNotification(targetUserId, PS_USER, false, lang, false);
                }
            } else {
                Boolean changed = revokePermissionSet(targetUserId, PS_ADMIN);
                if (changed) {
                    sendAccessChangeNotification(targetUserId, PS_ADMIN, false, lang, false);
                }
            }

            // Reflète l'état COURANT (après le changement ci-dessus), peu importe
            // quelle PS précise vient de changer.
            syncLibraryMembership(targetUserId);
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('Erreur: ' + e.getMessage());
        }
    }

    /**
     * Ajoute/retire l'utilisateur de la bibliothèque de fichiers OrgWatch
     * ("Library Administrator", seul palier de permission existant dans cet
     * org) selon qu'il a encore, ou non, au moins une des deux PS OrgWatch.
     */
    private static void syncLibraryMembership(Id userId) {
        Boolean hasAnyOrgWatchAccess = permissionSetAssigneeIds(PS_USER).contains(userId)
            || permissionSetAssigneeIds(PS_ADMIN).contains(userId);
        new LibrarySync().sync(userId, hasAnyOrgWatchAccess);
    }

    /**
     * En mode système explicite : la visibilité des bibliothèques de
     * fichiers (Content Libraries) n'est pas gouvernée par le modèle de
     * partage Apex standard ("with/without sharing" n'a aucun effet dessus),
     * mais par le modèle d'appartenance propre aux Content Workspaces. L'admin
     * qui déclenche cette synchro (déjà vérifié par assertAdmin()) n'est pas
     * forcément lui-même membre de la bibliothèque OrgWatch : AccessLevel.SYSTEM_MODE
     * élève explicitement l'exécution pour que la synchro fonctionne quel que
     * soit l'admin appelant.
     */
    private without sharing class LibrarySync {
        private void sync(Id userId, Boolean hasAccess) {
            Id workspaceId = getWorkspaceId();
            if (workspaceId == null) return;

            List<ContentWorkspaceMember> existing = Database.query(
                'SELECT Id FROM ContentWorkspaceMember WHERE ContentWorkspaceId = :workspaceId AND MemberId = :userId LIMIT 1',
                AccessLevel.SYSTEM_MODE
            );

            if (hasAccess) {
                if (existing.isEmpty()) {
                    Id permissionId = getPermissionId();
                    if (permissionId != null) {
                        Database.insert(
                            new ContentWorkspaceMember(
                                ContentWorkspaceId = workspaceId,
                                MemberId = userId,
                                ContentWorkspacePermissionId = permissionId
                            ),
                            AccessLevel.SYSTEM_MODE
                        );
                    }
                }
            } else if (!existing.isEmpty()) {
                Database.delete(existing, AccessLevel.SYSTEM_MODE);
            }
        }

        private Id getWorkspaceId() {
            List<ContentWorkspace> ws = Database.query(
                'SELECT Id FROM ContentWorkspace WHERE Name = :LIBRARY_NAME LIMIT 1',
                AccessLevel.SYSTEM_MODE
            );
            return ws.isEmpty() ? null : ws[0].Id;
        }

        /**
         * Sélectionne le palier d'accès le MOINS privilégié qui permette de
         * consulter la bibliothèque : l'app écrit les CSV via Apex (mode
         * système), un membre n'a besoin que de les lire/télécharger. Un
         * palier Admin donnerait à chaque utilisateur OrgWatch le droit de
         * supprimer tout l'historique et de modifier le fichier de
         * préférences de ses collègues.
         *
         * La sélection se fait sur Type et non sur Name : le nom des paliers
         * standard est localisé (« Administrateur de bibliothèque » dans une
         * org française), donc non fiable dans l'org d'un client.
         */
        private Id getPermissionId() {
            Map<String, Id> permissionIdByType = new Map<String, Id>();
            for (ContentWorkspacePermission perm : (List<ContentWorkspacePermission>) Database.query(
                'SELECT Id, Type FROM ContentWorkspacePermission',
                AccessLevel.SYSTEM_MODE
            )) {
                if (!permissionIdByType.containsKey(perm.Type)) {
                    permissionIdByType.put(perm.Type, perm.Id);
                }
            }
            for (String preferredType : LIBRARY_PERMISSION_TYPES_BY_PREFERENCE) {
                if (permissionIdByType.containsKey(preferredType)) {
                    return permissionIdByType.get(preferredType);
                }
            }
            return null;
        }
    }

    /**
     * Notifie l'utilisateur cible d'un changement d'accès OrgWatch (PS
     * ajoutée ou retirée). Un lien direct vers l'app est inclus dans tous
     * les cas SAUF le retrait complet ("au revoir") : l'utilisateur n'a
     * justement plus accès, un lien y serait inutile/trompeur.
     */
    private static void sendAccessChangeNotification(Id targetUserId, String permissionSetName, Boolean granted, String lang, Boolean isNewUser) {
        List<User> users = [SELECT Id, Name, Email FROM User WHERE Id = :targetUserId LIMIT 1];
        if (users.isEmpty() || String.isBlank(users[0].Email)) {
            lastAccessChangeEmailsSent = 0;
            return;
        }
        User u = users[0];

        String subjectKey;
        String bodyKey;
        Boolean includeAppLink = true;

        if (granted && permissionSetName == PS_USER) {
            subjectKey = isNewUser ? 'welcomeNewSubject' : 'accessRestoredSubject';
            bodyKey = isNewUser ? 'welcomeNewBody' : 'accessRestoredBody';
        } else if (granted && permissionSetName == PS_ADMIN) {
            subjectKey = 'adminGrantedSubject';
            bodyKey = 'adminGrantedBody';
        } else if (!granted && permissionSetName == PS_USER) {
            subjectKey = 'goodbyeSubject';
            bodyKey = 'goodbyeBody';
            includeAppLink = false;
        } else {
            subjectKey = 'adminRevokedSubject';
            bodyKey = 'adminRevokedBody';
        }

        String bodyHtml = '<h2 style="margin:0 0 4px;color:' + OrgWatchEmailBranding.COLOR_TEXT_PRIMARY + ';">' + t(subjectKey, lang) + '</h2>'
            + '<p style="color:' + OrgWatchEmailBranding.COLOR_TEXT_SECONDARY + ';margin:0 0 20px;">' + t('greetingPrefix', lang) + OrgWatchEmailBranding.escapeHtml(u.Name) + t(bodyKey, lang) + '</p>';

        if (includeAppLink) {
            bodyHtml += OrgWatchEmailBranding.buildActionButtonHtml(OrgWatchEmailBranding.getAppUrl(), t('goToAppButton', lang));
        }

        String subject = t(subjectKey, lang);
        String html = OrgWatchEmailBranding.wrap(bodyHtml, lang);

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setTargetObjectId(targetUserId);
        mail.setSaveAsActivity(false);
        mail.setSubject(subject);
        mail.setHtmlBody(html);

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);
        lastAccessChangeEmailsSent = 1;
        lastAccessChangeEmailSubject = subject;
        lastAccessChangeEmailHtmlBody = html;
    }

    @AuraEnabled
    public static String disableUserAlerts(Id targetUserId, Boolean notifyUser) {
        assertAdmin();

        try {
            String result = OrgWatchController.writePreferencesForUser(targetUserId, null, '', null, null);
            OrgWatchAlertController.ensureAlertJobState();

            if (result == 'SUCCESS' && notifyUser == true) {
                sendDisableNotification(targetUserId);
            } else {
                lastNotificationEmailsSent = 0;
            }

            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Erreur: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String setAlertScheduleTime(String timeValue) {
        assertAdmin();

        if (String.isBlank(timeValue) || !Pattern.matches('^([01][0-9]|2[0-3]):[0-5][0-9]$', timeValue)) {
            throw new AuraHandledException('Heure invalide, format attendu HH:MM.');
        }

        try {
            OrgWatch_Settings__c settings = OrgWatch_Settings__c.getOrgDefaults();
            if (settings.Id == null) {
                settings.SetupOwnerId = UserInfo.getOrganizationId();
            }
            settings.Alert_Send_Time__c = timeValue;
            upsert settings;

            // ensureAlertJobState() seule ne réagit qu'à un changement d'état
            // actif/inactif : un job déjà actif doit être explicitement recréé
            // pour prendre en compte la nouvelle heure.
            OrgWatchAlertController.forceRescheduleAtConfiguredTime();

            return 'SUCCESS';
        } catch (Exception e) {
            throw new AuraHandledException('Erreur: ' + e.getMessage());
        }
    }

    private static void sendDisableNotification(Id targetUserId) {
        List<User> users = [SELECT Id, Name, Email FROM User WHERE Id = :targetUserId LIMIT 1];
        if (users.isEmpty() || String.isBlank(users[0].Email)) {
            lastNotificationEmailsSent = 0;
            return;
        }
        User u = users[0];
        String lang = resolveLanguage(targetUserId);

        String bodyHtml = '<h2 style="margin:0 0 4px;color:' + OrgWatchEmailBranding.COLOR_TEXT_PRIMARY + ';">' + t('alertsDisabledSubject', lang) + '</h2>'
            + '<p style="color:' + OrgWatchEmailBranding.COLOR_TEXT_SECONDARY + ';margin:0 0 20px;">' + t('greetingPrefix', lang) + OrgWatchEmailBranding.escapeHtml(u.Name) + t('alertsDisabledBody', lang) + '</p>'
            + OrgWatchEmailBranding.buildActionButtonHtml(OrgWatchEmailBranding.getAppUrl(), t('goToAppButton', lang));

        String html = OrgWatchEmailBranding.wrap(bodyHtml, lang);

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setTargetObjectId(targetUserId);
        mail.setSaveAsActivity(false);
        mail.setSubject(t('alertsDisabledSubject', lang));
        mail.setHtmlBody(html);

        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);
        lastNotificationEmailsSent = 1;
        lastNotificationEmailHtmlBody = html;
    }

    private static Boolean grantPermissionSet(Id targetUserId, String permissionSetName) {
        Id psId = permissionSetIdByName(permissionSetName);
        List<PermissionSetAssignment> existing = [
            SELECT Id FROM PermissionSetAssignment
            WHERE AssigneeId = :targetUserId AND PermissionSetId = :psId
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            insert new PermissionSetAssignment(AssigneeId = targetUserId, PermissionSetId = psId);
            return true;
        }
        return false;
    }

    private static Boolean revokePermissionSet(Id targetUserId, String permissionSetName) {
        Id psId = permissionSetIdByName(permissionSetName);
        List<PermissionSetAssignment> existing = [
            SELECT Id FROM PermissionSetAssignment
            WHERE AssigneeId = :targetUserId AND PermissionSetId = :psId
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            delete existing;
            return true;
        }
        return false;
    }

    private static Id permissionSetIdByName(String permissionSetName) {
        List<PermissionSet> psList = [SELECT Id FROM PermissionSet WHERE Name = :permissionSetName LIMIT 1];
        if (psList.isEmpty()) {
            throw new AuraHandledException('Permission Set introuvable : ' + permissionSetName);
        }
        return psList[0].Id;
    }

    private static Set<Id> permissionSetAssigneeIds(String permissionSetName) {
        Set<Id> assigneeIds = new Set<Id>();
        List<PermissionSet> psList = [SELECT Id FROM PermissionSet WHERE Name = :permissionSetName LIMIT 1];
        if (psList.isEmpty()) {
            return assigneeIds;
        }
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId FROM PermissionSetAssignment WHERE PermissionSetId = :psList[0].Id
        ]) {
            assigneeIds.add(psa.AssigneeId);
        }
        return assigneeIds;
    }

    public class UserAccessRow {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public Boolean hasUserPS;
        @AuraEnabled public Boolean hasAdminPS;
        @AuraEnabled public Boolean hasAlertsConfigured;
        @AuraEnabled public String alertEmailMode;
    }
}