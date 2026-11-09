@IsTest(isParallel=false)
private class OrgWatchAdminControllerTest {

    private static User createTestUser(String lastName) {
        String uniqueSuffix = String.valueOf(Datetime.now().getTime());
        User u = new User(
            FirstName = 'OrgWatch',
            LastName = lastName,
            Email = 'orgwatch.test.' + lastName.toLowerCase() + '@example.com.invalid',
            Username = 'orgwatch.test.' + lastName.toLowerCase() + uniqueSuffix + '@example.com.invalid',
            Alias = ('ow' + uniqueSuffix).right(8),
            TimeZoneSidKey = 'Europe/Paris',
            LocaleSidKey = 'fr_FR',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'fr',
            ProfileId = UserInfo.getProfileId(),
            IsActive = true
        );
        // User est un "setup object" pour Apex : l'insérer puis insérer un
        // ContentVersion/PermissionSetAssignment dans la même transaction
        // lève MIXED_DML_OPERATION. runAs isole la création.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }

    private static void grantAdminPermissionSet(Id userId) {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'OrgWatch_Admin' LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = ps.Id);
        }
    }

    /**
     * À appeler depuis le même System.runAs() (ou la même absence de runAs)
     * que celui qui a créé la bibliothèque "OrgWatch Reporting TEST" : en
     * contexte de test, une Content Library n'est visible en SOQL que par
     * l'identité qui l'a créée (limitation constatée empiriquement,
     * indépendante du partage Apex/with sharing) - un runAs différent, même
     * "without sharing" côté production, ne la verra pas.
     */
    private static Boolean isLibraryMember(Id userId) {
        List<ContentWorkspace> ws = [SELECT Id FROM ContentWorkspace WHERE Name = 'OrgWatch Reporting TEST' LIMIT 1];
        if (ws.isEmpty()) return false;
        return !([SELECT Id FROM ContentWorkspaceMember WHERE ContentWorkspaceId = :ws[0].Id AND MemberId = :userId LIMIT 1].isEmpty());
    }

    @IsTest
    static void testAssertAdminRejectsNonAdmin() {
        User nonAdmin = createTestUser('NonAdmin');

        Boolean exceptionThrown = false;
        System.runAs(nonAdmin) {
            Test.startTest();
            try {
                OrgWatchAdminController.getUserAccessOverview();
                System.assert(false, 'Une AuraHandledException aurait dû être levée');
            } catch (AuraHandledException e) {
                exceptionThrown = true;
            }
            Test.stopTest();
        }
        System.assert(exceptionThrown, 'Un utilisateur sans OrgWatch_Admin_Access doit être rejeté');
    }

    @IsTest
    static void testGetUserAccessOverviewAndSearchUsersAsAdmin() {
        User admin = createTestUser('Admin');
        grantAdminPermissionSet(admin.Id);

        System.runAs(admin) {
            Test.startTest();
            OrgWatchController.writePreferencesForUser(admin.Id, null, 'DataStorageMB:80', 'OnlyOnBreach', null);
            List<OrgWatchAdminController.UserAccessRow> overview = OrgWatchAdminController.getUserAccessOverview();
            List<OrgWatchAdminController.UserAccessRow> searchResults = OrgWatchAdminController.searchUsers('OrgWatch');
            Test.stopTest();

            Boolean foundInOverview = false;
            for (OrgWatchAdminController.UserAccessRow row : overview) {
                if (row.userId == admin.Id) {
                    foundInOverview = true;
                    System.assertEquals(true, row.hasAlertsConfigured, 'Les seuils configurés doivent être détectés');
                }
            }
            System.assert(foundInOverview, 'L\'utilisateur avec des seuils configurés doit apparaître dans la vue d\'ensemble');
            System.assert(!searchResults.isEmpty(), 'La recherche doit retrouver les utilisateurs de test "OrgWatch*"');
        }
    }

    @IsTest
    static void testSetPermissionSetAssignmentGrantAndRevoke() {
        User admin = createTestUser('Admin2');
        grantAdminPermissionSet(admin.Id);
        User target = createTestUser('Target');

        System.runAs(admin) {
            Test.startTest();
            OrgWatchAdminController.setPermissionSetAssignment(target.Id, 'OrgWatch_User', true);
            OrgWatchAdminController.setPermissionSetAssignment(target.Id, 'OrgWatch_Admin', true);
            Test.stopTest();

            List<OrgWatchAdminController.UserAccessRow> overview = OrgWatchAdminController.getUserAccessOverview();
            OrgWatchAdminController.UserAccessRow targetRow = findRow(overview, target.Id);
            System.assertNotEquals(null, targetRow, 'La cible doit apparaître dans la vue d\'ensemble après assignation');
            System.assertEquals(true, targetRow.hasUserPS);
            System.assertEquals(true, targetRow.hasAdminPS);
        }
    }

    @IsTest
    static void testRevokingUserPSAlsoRevokesAdminPS() {
        User admin = createTestUser('Admin3');
        grantAdminPermissionSet(admin.Id);
        User target = createTestUser('Target2');

        System.runAs(admin) {
            OrgWatchAdminController.setPermissionSetAssignment(target.Id, 'OrgWatch_User', true);
            OrgWatchAdminController.setPermissionSetAssignment(target.Id, 'OrgWatch_Admin', true);

            Test.startTest();
            OrgWatchAdminController.setPermissionSetAssignment(target.Id, 'OrgWatch_User', false);
            Test.stopTest();

            List<OrgWatchAdminController.UserAccessRow> overview = OrgWatchAdminController.getUserAccessOverview();
            OrgWatchAdminController.UserAccessRow targetRow = findRow(overview, target.Id);
            System.assertEquals(null, targetRow, 'La cible ne doit plus apparaître : plus aucune PS ni alerte');
        }
    }

    @IsTest
    static void testGrantingUserPSSendsAccessNotificationAndGrantsLibraryAccess() {
        User admin = createTestUser('Admin7b');
        grantAdminPermissionSet(admin.Id);
        User target = createTestUser('Target4');

        System.runAs(admin) {
            // Créée directement par "admin" (pas par un autre utilisateur/contexte) :
            // une bibliothèque de fichiers créée par un AUTRE utilisateur dans la
            // même transaction de test n'est pas visible en SOQL depuis ce
            // System.runAs (limitation constatée empiriquement) - seul l'utilisateur
            // qui l'a créée la voit de manière fiable en contexte de test.
            insert new ContentWorkspace(Name = 'OrgWatch Reporting TEST');

            Test.startTest();
            OrgWatchAdminController.setPermissionSetAssignment(target.Id, 'OrgWatch_User', true);
            Test.stopTest();

            System.assertEquals(1, OrgWatchAdminController.lastAccessChangeEmailsSent, 'Octroyer OrgWatch_User doit notifier l\'utilisateur (avec lien vers l\'app)');
            System.assert(isLibraryMember(target.Id), 'L\'utilisateur doit être ajouté à la bibliothèque OrgWatch');
        }
    }

    @IsTest
    static void testGrantingAlreadyAssignedPSDoesNotResendNotification() {
        User admin = createTestUser('Admin8b');
        grantAdminPermissionSet(admin.Id);
        User target = createTestUser('Target5');

        System.runAs(admin) {
            OrgWatchAdminController.setPermissionSetAssignment(target.Id, 'OrgWatch_User', true);

            OrgWatchAdminController.lastAccessChangeEmailsSent = -1;
            Test.startTest();
            OrgWatchAdminController.setPermissionSetAssignment(target.Id, 'OrgWatch_User', true);
            Test.stopTest();

            System.assertEquals(-1, OrgWatchAdminController.lastAccessChangeEmailsSent, 'Assigner une PS déjà présente ne doit pas redéclencher de notification');
        }
    }

    @IsTest
    static void testRevokingUserPSSendsSingleCombinedNotification() {
        User admin = createTestUser('Admin9b');
        grantAdminPermissionSet(admin.Id);
        User target = createTestUser('Target6');

        System.runAs(admin) {
            OrgWatchAdminController.setPermissionSetAssignment(target.Id, 'OrgWatch_User', true);
            OrgWatchAdminController.setPermissionSetAssignment(target.Id, 'OrgWatch_Admin', true);

            OrgWatchAdminController.lastAccessChangeEmailsSent = -1;
            Test.startTest();
            OrgWatchAdminController.setPermissionSetAssignment(target.Id, 'OrgWatch_User', false);
            Test.stopTest();

            System.assertEquals(1, OrgWatchAdminController.lastAccessChangeEmailsSent, 'La révocation en cascade (User+Admin) doit tout de même notifier l\'utilisateur');
        }
    }

    @IsTest
    static void testRevokingAdminPSOnlySendsNotificationAndKeepsLibraryAccess() {
        User admin = createTestUser('Admin10b');
        grantAdminPermissionSet(admin.Id);
        User target = createTestUser('Target7');

        System.runAs(admin) {
            // Cf. testGrantingUserPSSendsAccessNotificationAndGrantsLibraryAccess :
            // créée par "admin" lui-même pour rester visible dans ce runAs.
            insert new ContentWorkspace(Name = 'OrgWatch Reporting TEST');

            OrgWatchAdminController.setPermissionSetAssignment(target.Id, 'OrgWatch_User', true);
            OrgWatchAdminController.setPermissionSetAssignment(target.Id, 'OrgWatch_Admin', true);

            OrgWatchAdminController.lastAccessChangeEmailsSent = -1;
            Test.startTest();
            OrgWatchAdminController.setPermissionSetAssignment(target.Id, 'OrgWatch_Admin', false);
            Test.stopTest();

            System.assertEquals(1, OrgWatchAdminController.lastAccessChangeEmailsSent, 'Retirer uniquement OrgWatch_Admin doit notifier l\'utilisateur');

            List<OrgWatchAdminController.UserAccessRow> overview = OrgWatchAdminController.getUserAccessOverview();
            OrgWatchAdminController.UserAccessRow targetRow = findRow(overview, target.Id);
            System.assertNotEquals(null, targetRow, 'La cible garde son accès User, elle doit toujours apparaître');
            System.assertEquals(true, targetRow.hasUserPS);
            System.assertEquals(false, targetRow.hasAdminPS);
            System.assert(isLibraryMember(target.Id), 'L\'utilisateur garde OrgWatch_User : l\'accès à la bibliothèque doit être conservé');
        }
    }

    @IsTest
    static void testGrantingUserPSToBrandNewUserSendsWelcomeEmail() {
        User admin = createTestUser('Admin11b');
        grantAdminPermissionSet(admin.Id);
        User target = createTestUser('Target8');

        System.runAs(admin) {
            Test.startTest();
            OrgWatchAdminController.setPermissionSetAssignment(target.Id, 'OrgWatch_User', true);
            Test.stopTest();

            System.assertEquals(1, OrgWatchAdminController.lastAccessChangeEmailsSent);
            System.assert(
                OrgWatchAdminController.lastAccessChangeEmailSubject.contains('Bienvenue'),
                'Un tout nouvel utilisateur (aucune préférence préexistante) doit recevoir le mail de bienvenue, était: ' + OrgWatchAdminController.lastAccessChangeEmailSubject
            );
            System.assert(
                OrgWatchAdminController.lastAccessChangeEmailHtmlBody.contains('Ouvrir OrgWatch'),
                'Le mail de bienvenue doit inclure un lien vers l\'app'
            );
        }
    }

    @IsTest
    static void testGrantingUserPSToReturningUserSendsRestoredEmail() {
        User admin = createTestUser('Admin12b');
        grantAdminPermissionSet(admin.Id);
        User target = createTestUser('Target9');

        System.runAs(admin) {
            // Simule un utilisateur ayant déjà utilisé l'app par le passé (une ligne
            // de préférences existe) mais dont l'accès a été retiré autrement que via
            // cette classe (ex: retrait manuel du Permission Set Assignment via
            // Setup) : le fichier n'a donc pas été nettoyé par removePreferencesForUser.
            OrgWatchController.writePreferencesForUser(target.Id, 'DataStorageMB', '', null, null);

            Test.startTest();
            OrgWatchAdminController.setPermissionSetAssignment(target.Id, 'OrgWatch_User', true);
            Test.stopTest();

            System.assertEquals(1, OrgWatchAdminController.lastAccessChangeEmailsSent);
            System.assert(
                OrgWatchAdminController.lastAccessChangeEmailSubject.contains('réactivé'),
                'Un utilisateur ayant déjà des préférences doit recevoir le mail de réactivation, pas le mail de bienvenue, était: ' + OrgWatchAdminController.lastAccessChangeEmailSubject
            );
        }
    }

    @IsTest
    static void testFullRevokeRemovesPreferencesLibraryAccessAndSendsGoodbyeWithoutAppLink() {
        User admin = createTestUser('Admin13b');
        grantAdminPermissionSet(admin.Id);
        User target = createTestUser('Target10');

        System.runAs(admin) {
            // Cf. testGrantingUserPSSendsAccessNotificationAndGrantsLibraryAccess :
            // créée par "admin" lui-même pour rester visible dans ce runAs.
            insert new ContentWorkspace(Name = 'OrgWatch Reporting TEST');

            OrgWatchAdminController.setPermissionSetAssignment(target.Id, 'OrgWatch_User', true);
            OrgWatchController.writePreferencesForUser(target.Id, 'DataStorageMB', 'DataStorageMB:80', 'Always', 'en');
            System.assert(isLibraryMember(target.Id), 'Pré-requis : doit être membre avant le test du retrait');

            Test.startTest();
            OrgWatchAdminController.setPermissionSetAssignment(target.Id, 'OrgWatch_User', false);
            Test.stopTest();

            System.assertEquals(
                null,
                OrgWatchController.readAllPreferences().get(target.Id),
                'Un utilisateur sans plus aucune PS ne doit plus avoir de ligne de préférences (plus un utilisateur de l\'app)'
            );
            System.assert(
                OrgWatchAdminController.lastAccessChangeEmailSubject.contains('retiré') || OrgWatchAdminController.lastAccessChangeEmailSubject.contains('removed'),
                'Le retrait complet doit envoyer le mail "au revoir", était: ' + OrgWatchAdminController.lastAccessChangeEmailSubject
            );
            System.assert(
                !OrgWatchAdminController.lastAccessChangeEmailHtmlBody.contains('Ouvrir OrgWatch') && !OrgWatchAdminController.lastAccessChangeEmailHtmlBody.contains('Open OrgWatch'),
                'Le mail "au revoir" ne doit pas inclure de lien vers l\'app (l\'utilisateur n\'y a plus accès)'
            );
            System.assert(!isLibraryMember(target.Id), 'L\'accès à la bibliothèque doit être retiré');
        }
    }

    @IsTest
    static void testAlertsDisabledEmailIncludesAppLink() {
        User admin = createTestUser('Admin14b');
        grantAdminPermissionSet(admin.Id);

        System.runAs(admin) {
            OrgWatchController.writePreferencesForUser(admin.Id, null, 'DataStorageMB:80', 'OnlyOnBreach', null);

            Test.startTest();
            OrgWatchAdminController.disableUserAlerts(admin.Id, true);
            Test.stopTest();

            System.assertEquals(1, OrgWatchAdminController.lastNotificationEmailsSent);
            System.assert(
                OrgWatchAdminController.lastNotificationEmailHtmlBody.contains('Ouvrir OrgWatch'),
                'Le mail de désactivation des alertes doit maintenant inclure un lien vers l\'app'
            );
        }
    }

    @IsTest
    static void testSetPermissionSetAssignmentRejectsUnknownPermissionSet() {
        User admin = createTestUser('Admin4');
        grantAdminPermissionSet(admin.Id);
        User target = createTestUser('Target3');

        Boolean exceptionThrown = false;
        System.runAs(admin) {
            Test.startTest();
            try {
                OrgWatchAdminController.setPermissionSetAssignment(target.Id, 'Some_Other_PermissionSet', true);
                System.assert(false, 'Une AuraHandledException aurait dû être levée');
            } catch (AuraHandledException e) {
                exceptionThrown = true;
            }
            Test.stopTest();
        }
        System.assert(exceptionThrown, 'Seuls OrgWatch_User et OrgWatch_Admin doivent être acceptés');
    }

    @IsTest
    static void testDisableUserAlertsWithNotification() {
        User admin = createTestUser('Admin5');
        grantAdminPermissionSet(admin.Id);

        System.runAs(admin) {
            OrgWatchController.writePreferencesForUser(admin.Id, null, 'DataStorageMB:80', 'OnlyOnBreach', null);

            Test.startTest();
            String result = OrgWatchAdminController.disableUserAlerts(admin.Id, true);
            Test.stopTest();

            System.assertEquals('SUCCESS', result);
            System.assertEquals(1, OrgWatchAdminController.lastNotificationEmailsSent, 'Un email de notification doit être envoyé quand demandé');

            OrgWatchController.UserPreferences prefs = OrgWatchController.readAllPreferences().get(admin.Id);
            System.assertNotEquals(null, prefs);
            System.assertEquals('', prefs.metricThresholds, 'Les seuils doivent être vidés');
        }
    }

    @IsTest
    static void testDisableUserAlertsWithoutNotification() {
        User admin = createTestUser('Admin6');
        grantAdminPermissionSet(admin.Id);

        System.runAs(admin) {
            OrgWatchController.writePreferencesForUser(admin.Id, null, 'DataStorageMB:80', 'OnlyOnBreach', null);

            Test.startTest();
            String result = OrgWatchAdminController.disableUserAlerts(admin.Id, false);
            Test.stopTest();

            System.assertEquals('SUCCESS', result);
            System.assertEquals(0, OrgWatchAdminController.lastNotificationEmailsSent, 'Aucun email ne doit être envoyé si non demandé');
        }
    }

    @IsTest
    static void testSetAlertScheduleTimeRejectsNonAdmin() {
        User nonAdmin = createTestUser('NonAdmin2');

        Boolean exceptionThrown = false;
        System.runAs(nonAdmin) {
            Test.startTest();
            try {
                OrgWatchAdminController.setAlertScheduleTime('09:00');
                System.assert(false, 'Une AuraHandledException aurait dû être levée');
            } catch (AuraHandledException e) {
                exceptionThrown = true;
            }
            Test.stopTest();
        }
        System.assert(exceptionThrown, 'Un utilisateur sans OrgWatch_Admin_Access doit être rejeté');
    }

    @IsTest
    static void testSetAlertScheduleTimeRejectsInvalidFormat() {
        User admin = createTestUser('Admin7');
        grantAdminPermissionSet(admin.Id);

        Boolean exceptionThrown = false;
        System.runAs(admin) {
            Test.startTest();
            try {
                OrgWatchAdminController.setAlertScheduleTime('25:99');
                System.assert(false, 'Une AuraHandledException aurait dû être levée');
            } catch (AuraHandledException e) {
                exceptionThrown = true;
            }
            Test.stopTest();
        }
        System.assert(exceptionThrown, 'Un format d\'heure invalide doit être rejeté');
    }

    @IsTest
    static void testSetAlertScheduleTimePersistsAndReschedulesActiveJob() {
        User admin = createTestUser('Admin8');
        grantAdminPermissionSet(admin.Id);

        System.runAs(admin) {
            // Un utilisateur avec une alerte active -> le job existe déjà à l'heure par défaut
            OrgWatchController.writePreferencesForUser(admin.Id, null, 'DataStorageMB:80', 'Always', null);
            OrgWatchAlertController.ensureAlertJobState();

            Test.startTest();
            String result = OrgWatchAdminController.setAlertScheduleTime('07:15');
            Test.stopTest();

            System.assertEquals('SUCCESS', result);
            System.assertEquals('07:15', OrgWatchAlertController.getConfiguredAlertTime(), 'La nouvelle heure doit être persistée dans le Custom Setting');

            List<CronTrigger> jobs = [
                SELECT Id, CronJobDetail.Name
                FROM CronTrigger
                WHERE CronJobDetail.Name LIKE 'OrgWatchAlert_Daily_%'
                AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING', 'PAUSED')
            ];
            System.assertEquals(1, jobs.size(), 'Le job actif doit avoir été recréé (une seule occurrence)');
            System.assertEquals('OrgWatchAlert_Daily_07h15', jobs[0].CronJobDetail.Name, 'Le job recréé doit porter la nouvelle heure');
        }
    }

    @IsTest
    static void testSetAlertScheduleTimePersistsEvenWithoutActiveJob() {
        User admin = createTestUser('Admin9');
        grantAdminPermissionSet(admin.Id);

        System.runAs(admin) {
            // Personne n'a d'alerte configurée -> aucun job actif
            Test.startTest();
            String result = OrgWatchAdminController.setAlertScheduleTime('06:45');
            Test.stopTest();

            System.assertEquals('SUCCESS', result);
            System.assertEquals('06:45', OrgWatchAlertController.getConfiguredAlertTime(), 'La valeur configurée doit survivre même sans job actif');

            List<CronTrigger> jobs = [
                SELECT Id
                FROM CronTrigger
                WHERE CronJobDetail.Name LIKE 'OrgWatchAlert_Daily_%'
                AND State IN ('WAITING', 'ACQUIRED', 'EXECUTING', 'PAUSED')
            ];
            System.assertEquals(0, jobs.size(), 'Aucune alerte configurée -> pas de job créé, uniquement le réglage sauvegardé');
        }
    }

    private static OrgWatchAdminController.UserAccessRow findRow(List<OrgWatchAdminController.UserAccessRow> rows, Id userId) {
        for (OrgWatchAdminController.UserAccessRow row : rows) {
            if (row.userId == userId) {
                return row;
            }
        }
        return null;
    }

    /**
     * "OrgWatch - Admin" est additive : accordée seule elle ne donnerait accès
     * à rien, car elle ne porte ni la visibilité de l'onglet ni l'accès à
     * OrgWatchController. Cocher l'interrupteur Admin doit donc entraîner
     * l'accès de base, sans que l'admin ait à y penser - réciproque du retrait
     * en cascade déjà testé par testRevokingUserPSAlsoRevokesAdminPS.
     */
    @IsTest
    static void testGrantingAdminPSAlsoGrantsUserPS() {
        User admin = createTestUser('Admin11b');
        grantAdminPermissionSet(admin.Id);
        User target = createTestUser('Target8');

        System.runAs(admin) {
            OrgWatchAdminController.lastAccessChangeEmailsSent = -1;
            Test.startTest();
            OrgWatchAdminController.setPermissionSetAssignment(target.Id, 'OrgWatch_Admin', true);
            Test.stopTest();

            List<OrgWatchAdminController.UserAccessRow> overview = OrgWatchAdminController.getUserAccessOverview();
            OrgWatchAdminController.UserAccessRow targetRow = findRow(overview, target.Id);

            System.assertNotEquals(null, targetRow, 'La cible doit apparaître dans le tableau des accès');
            System.assertEquals(true, targetRow.hasAdminPS, 'La PS Admin demandée doit être accordée');
            System.assertEquals(true, targetRow.hasUserPS,
                'L\'accès de base doit être accordé avec : sans lui, la PS Admin ne donne accès à rien');
            System.assertEquals(1, OrgWatchAdminController.lastAccessChangeEmailsSent,
                'Une seule action admin ne doit envoyer qu\'une seule notification');
        }
    }
}