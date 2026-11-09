/**
 * Construit l'export CSV des limites de l'org et l'ecrit dans la
 * bibliotheque OrgWatch.
 *
 * Sans partage, explicitement : appele par un job planifie, pour le compte de
 * l'org et non d'un utilisateur.
 */
public without sharing class OrgWatchExporter {

    // Configuration constantes
    private static final String LIBRARY_NAME = Test.isRunningTest() ? 'OrgWatch Reporting TEST' : 'OrgWatch Reporting';
    private static final String LIBRARY_DEV_NAME = Test.isRunningTest() ? 'OrgWatch_Reporting_TEST' : 'OrgWatch_Reporting';
    private static final String CSV_HEADER = 'Catégorie;Nom de la Limite;Valeur Actuelle;Maximum;Consommation (%)\n';
    private static final String BOM_UTF8 = '\uFEFF';

    // Categories
    private static final String CATEGORY_ORG = 'Organisation';


    /**
     * Permet d'éprouver le chemin d'échec de l'export (bibliothèque absente,
     * écriture impossible), désormais remonté par OrgWatchExporterScheduler
     * au lieu d'être silencieux. Ce chemin n'est pas déclenchable autrement en
     * contexte de test : l'export recrée la bibliothèque de test s'il ne la
     * trouve pas, et donc réussit toujours.
     */
    @TestVisible
    private static Boolean forceFailureForTests = false;

    public static Boolean exportLimitsToLibrary() {
        if (Test.isRunningTest() && forceFailureForTests) {
            return false;
        }

        try {
            // 1. Build CSV content from org limits
            String csvContent = buildCsvContent();

            // 2. Find or create the library
            ContentWorkspace library = getLibrary();

            // 3. Create and upload the CSV file
            Id documentId = createCsvFile(csvContent);

            // 4. Link file to library
            linkFileToLibrary(documentId, library.Id);

            System.debug('Success! File available in library: ' + LIBRARY_NAME);
            return true;

        } catch (QueryException qe) {
            System.debug('Error: Library "' + LIBRARY_NAME + '" not found. Please create it first.');
            return false;
        } catch (Exception e) {
            System.debug('Error during export: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            return false;
        }
    }

    /**
     * Builds CSV content from all org limits, Agentforce and Data Cloud
     * @return String - CSV formatted content
     */
    private static String buildCsvContent() {
        String csvContent = '';
        csvContent += buildOrgLimitsSection();
        return csvContent;
    }

    /**
     * Builds the standard org limits section
     * @return String - CSV lines for org limits
     */
    private static String buildOrgLimitsSection() {
        String content = '';

        // Get all org limits
        Map<String, System.OrgLimit> limitsMap = OrgLimits.getMap();

        for (String limitName : limitsMap.keySet()) {
            System.OrgLimit lim = limitsMap.get(limitName);
            Long maxValue = lim.getLimit();
            Long currentValue = lim.getValue();

            content += formatCsvLine(CATEGORY_ORG, limitName, currentValue, maxValue);
        }

        return content;
    }


    @TestVisible
    private static Decimal getDecimalValue(Object value) {
        if (value == null) return 0;
        if (value instanceof Decimal) return (Decimal)value;
        if (value instanceof Long) return Decimal.valueOf((Long)value);
        if (value instanceof Integer) return Decimal.valueOf((Integer)value);
        return Decimal.valueOf(String.valueOf(value));
    }


    @TestVisible
    private static Long getLongValue(Object value) {
        if (value == null) return 0;
        if (value instanceof Long) return (Long)value;
        if (value instanceof Integer) return (Long)((Integer)value);
        if (value instanceof Decimal) return ((Decimal)value).longValue();
        return Long.valueOf(String.valueOf(value));
    }

    /**
     * Formats a CSV line with percentage calculation
     * @param category - The category name
     * @param limitName - The limit name
     * @param currentValue - Current usage value
     * @param maxValue - Maximum allowed value (can be null)
     * @return String - Formatted CSV line
     */
    private static String formatCsvLine(String category, String limitName, Long currentValue, Long maxValue) {
        // Calculate percentage
        String percentStr = '-';
        if (maxValue != null && maxValue > 0) {
            Decimal percentUsed = (Decimal.valueOf(currentValue) / Decimal.valueOf(maxValue) * 100).setScale(2);
            percentStr = String.valueOf(percentUsed).replace('.', ',') + '%';
        }

        String maxStr = maxValue != null ? String.valueOf(maxValue) : '-';
        String currentStr = currentValue != null ? String.valueOf(currentValue) : '-';

        return category + ';' + limitName + ';' + currentStr + ';' + maxStr + ';' + percentStr + '\n';
    }


    private static ContentWorkspace getLibrary() {
        // Try to find existing library
        List<ContentWorkspace> existingLibraries = [
            SELECT Id
            FROM ContentWorkspace
            WHERE Name = :LIBRARY_NAME
            LIMIT 1
        ];

        if (!existingLibraries.isEmpty()) {
            return existingLibraries[0];
        }

        // Library doesn't exist - create it
        System.debug('Creating library: ' + LIBRARY_NAME);

        ContentWorkspace newLibrary = new ContentWorkspace();
        newLibrary.Name = LIBRARY_NAME;
        newLibrary.DeveloperName = LIBRARY_DEV_NAME;
        newLibrary.Description = 'Librairie pour les exports OrgWatch des limites Salesforce';

        // ContentWorkspace est un "setup object" pour Apex : l'insérer puis
        // insérer un ContentVersion dans la même transaction lève
        // MIXED_DML_OPERATION. runAs isole la création dans son propre
        // contexte DML (uniquement utilisable en contexte de test).
        if (Test.isRunningTest()) {
            System.runAs(new User(Id = UserInfo.getUserId())) {
                insert newLibrary;
            }
        } else {
            insert newLibrary;
        }

        System.debug('Library created: ' + LIBRARY_NAME);
        return newLibrary;
    }


    private static Id createCsvFile(String csvContent) {
        // Generate filename with timestamp
        String timestamp = DateTime.now().format('yyyy-MM-dd_HH-mm');
        String fileName = 'OrgWatch_Export_' + timestamp;

        // Create ContentVersion (this creates the file)
        ContentVersion cv = new ContentVersion();
        cv.Title = fileName;
        cv.PathOnClient = 'OrgWatch.csv';
        // Add UTF-8 BOM to ensure Excel recognizes encoding correctly
        cv.VersionData = Blob.valueOf(BOM_UTF8 + CSV_HEADER + csvContent);
        cv.IsMajorVersion = true;
        insert cv;

        // Retrieve the ContentDocumentId that was automatically created
        ContentVersion insertedVersion = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];

        return insertedVersion.ContentDocumentId;
    }


    private static void linkFileToLibrary(Id documentId, Id libraryId) {
        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.ContentDocumentId = documentId;
        cdl.LinkedEntityId = libraryId;
        cdl.ShareType = 'I'; // 'I' for Inferred (inherits library permissions)
        cdl.Visibility = 'AllUsers';
        insert cdl;
    }
}