/**
 * Job planifie d'envoi du recapitulatif quotidien d'alertes.
 *
 * Sans partage, explicitement : ce job lit les preferences de TOUS les
 * utilisateurs pour savoir a qui envoyer un mail, et agit pour le compte de
 * l'org, jamais pour le compte de l'utilisateur courant (il n'y en a pas).
 */
public without sharing class OrgWatchAlertScheduler implements Schedulable {

    private static final Integer WINDOW_HOURS = 24;
    private static final Integer BAR_SEGMENTS = 12;
    private static final String DEFAULT_LANGUAGE = 'fr';

    @TestVisible private static Integer lastEmailsBuiltCount = -1;
    @TestVisible private static Integer lastAlertingUserCount = -1;
    @TestVisible private static String lastEmailSubject;
    @TestVisible private static String lastEmailHtmlBody;

    // Palette et gabarit de marque (logo, bandeau, pied de page) centralisés
    // dans OrgWatchEmailBranding, partagés avec OrgWatchAdminController.

    // Doit rester aligné avec METRICS_CONFIG dans orgWatchMonitoring.js : Apex et
    // JS ne peuvent pas partager un même objet, cette table est dupliquée
    // volontairement (mêmes libellés FR/EN) pour que l'email et l'app affichent
    // les mêmes noms de métriques conviviaux.
    private static final Map<String, Map<String, String>> METRIC_LABELS = new Map<String, Map<String, String>>{
        'DataStorageMB' => new Map<String, String>{ 'fr' => 'Stockage de Données', 'en' => 'Data Storage' },
        'FileStorageMB' => new Map<String, String>{ 'fr' => 'Stockage de Fichiers', 'en' => 'File Storage' },
        'SingleEmail' => new Map<String, String>{ 'fr' => 'Emails Unitaires', 'en' => 'Single Emails' },
        'MassEmail' => new Map<String, String>{ 'fr' => 'Emails en Masse', 'en' => 'Mass Emails' },
        'DailyApiRequests' => new Map<String, String>{ 'fr' => 'Appels API Quotidiens', 'en' => 'Daily API Calls' },
        'DailyBulkApiRequests' => new Map<String, String>{ 'fr' => 'API Bulk Quotidienne', 'en' => 'Daily Bulk API' },
        'DailyDurableStreamingApiEvents' => new Map<String, String>{ 'fr' => 'Événements Streaming', 'en' => 'Streaming Events' },
        'DailyStreamingApiEvents' => new Map<String, String>{ 'fr' => 'Événements Streaming Standard', 'en' => 'Standard Streaming Events' },
        'DurableStreamingApiConcurrentClients' => new Map<String, String>{ 'fr' => 'Clients Streaming Actifs', 'en' => 'Active Streaming Clients' },
        'StreamingApiConcurrentClients' => new Map<String, String>{ 'fr' => 'Clients Streaming Standard', 'en' => 'Standard Streaming Clients' },
        'DailyAsyncApexExecutions' => new Map<String, String>{ 'fr' => 'Exécutions Apex Asynchrones', 'en' => 'Async Apex Executions' },
        'DailyWorkflowEmails' => new Map<String, String>{ 'fr' => 'Emails Automatiques', 'en' => 'Automated Emails' },
        'HourlyPublishedPlatformEvents' => new Map<String, String>{ 'fr' => 'Événements Plateforme/Heure', 'en' => 'Platform Events/Hour' },
        'HourlyPublishedStandardVolumePlatformEvents' => new Map<String, String>{ 'fr' => 'Événements Standard/Heure', 'en' => 'Standard Events/Hour' },
        'PermissionSets' => new Map<String, String>{ 'fr' => 'Ensembles de Permissions', 'en' => 'Permission Sets' },
        'DailyGenericStreamingApiEvents' => new Map<String, String>{ 'fr' => 'Événements Streaming Génériques', 'en' => 'Generic Streaming Events' },
        'ConcurrentAsyncGetReportInstances' => new Map<String, String>{ 'fr' => 'Rapports Asynchrones Actifs', 'en' => 'Active Async Reports' },
        'ConcurrentEinsteinDataInsightsStoryCreation' => new Map<String, String>{ 'fr' => 'Création Stories Einstein', 'en' => 'Einstein Stories Creation' },
        'ConcurrentEinsteinDiscoveryStoryCreation' => new Map<String, String>{ 'fr' => 'Discovery Einstein Actif', 'en' => 'Active Einstein Discovery' },
        'DailyEinsteinDiscoveryPredictAPICalls' => new Map<String, String>{ 'fr' => 'Prédictions Einstein/Jour', 'en' => 'Einstein Predictions/Day' },
        'MonthlyEinsteinDiscoveryStoryCreation' => new Map<String, String>{ 'fr' => 'Stories Einstein/Mois', 'en' => 'Einstein Stories/Month' },
        'ScheduledFlowRunLimit' => new Map<String, String>{ 'fr' => 'Flows Planifiés', 'en' => 'Scheduled Flows' },
        'DailyBulkV2QueryJobs' => new Map<String, String>{ 'fr' => 'Jobs Bulk Query V2', 'en' => 'Bulk Query V2 Jobs' },
        'DailyBulkV2QueryFileStorageMB' => new Map<String, String>{ 'fr' => 'Stockage Bulk Query V2', 'en' => 'Bulk Query V2 Storage' }
    };

    private static final Map<String, Map<String, String>> EMAIL_TEXT = new Map<String, Map<String, String>>{
        'title' => new Map<String, String>{ 'fr' => 'Récapitulatif de vos alertes', 'en' => 'Your Alerts Summary' },
        'greetingPrefix' => new Map<String, String>{ 'fr' => 'Bonjour ', 'en' => 'Hello ' },
        'greetingSuffix' => new Map<String, String>{
            'fr' => ', voici l\'état de vos métriques surveillées sur les dernières 24 heures.',
            'en' => ', here is the status of your monitored metrics over the last 24 hours.'
        },
        'bannerBreachMid' => new Map<String, String>{ 'fr' => ' métrique(s) sur ', 'en' => ' out of ' },
        'bannerBreachSuffix' => new Map<String, String>{
            'fr' => ' ont dépassé leur seuil au moins une fois dans les dernières 24h',
            'en' => ' metric(s) exceeded their threshold at least once in the last 24h'
        },
        'bannerOk' => new Map<String, String>{ 'fr' => 'Aucun dépassement détecté dans les dernières 24h', 'en' => 'No breach detected in the last 24 hours' },
        'colMetric' => new Map<String, String>{ 'fr' => 'Métrique', 'en' => 'Metric' },
        'colBreakdown' => new Map<String, String>{ 'fr' => 'Répartition 24h', 'en' => '24h Breakdown' },
        'colBreaches' => new Map<String, String>{ 'fr' => 'Dépassements', 'en' => 'Breaches' },
        'colCurrentValue' => new Map<String, String>{ 'fr' => 'Valeur actuelle', 'en' => 'Current value' },
        'colThreshold' => new Map<String, String>{ 'fr' => 'Seuil', 'en' => 'Threshold' },
        'footerPrefix' => new Map<String, String>{
            'fr' => 'Vous recevez cet email car vous avez configuré des alertes dans l\'onglet Alertes d\'OrgWatch. ',
            'en' => 'You are receiving this email because you configured alerts in the OrgWatch Alerts tab. '
        },
        'footerLinkText' => new Map<String, String>{ 'fr' => 'Ouvrir OrgWatch', 'en' => 'Open OrgWatch' },
        'footerSuffix' => new Map<String, String>{
            'fr' => ' pour les modifier ou les désactiver.',
            'en' => ' to change or disable them.'
        },
        'subjectBreach' => new Map<String, String>{ 'fr' => 'Alertes OrgWatch : ', 'en' => 'OrgWatch Alerts: ' },
        'subjectBreachSuffix' => new Map<String, String>{ 'fr' => ' dépassement(s)', 'en' => ' breach(es)' },
        'subjectOk' => new Map<String, String>{ 'fr' => 'Alertes OrgWatch : tout va bien', 'en' => 'OrgWatch Alerts: all good' }
    };

    public void execute(SchedulableContext sc) {
        Map<String, OrgWatchController.UserPreferences> allPrefs = OrgWatchController.readAllPreferences();

        List<Id> alertingUserIds = new List<Id>();
        for (OrgWatchController.UserPreferences p : allPrefs.values()) {
            if (String.isNotBlank(p.metricThresholds)) {
                alertingUserIds.add((Id) p.userId);
            }
        }

        lastAlertingUserCount = alertingUserIds.size();

        if (alertingUserIds.isEmpty()) {
            lastEmailsBuiltCount = 0;
            return;
        }

        Map<String, List<OrgWatchController.DataPoint>> history =
            OrgWatchController.getLimitsHistorySince(DateTime.now().addHours(-WINDOW_HOURS));

        Map<Id, User> users = new Map<Id, User>([SELECT Id, Email, Name FROM User WHERE Id IN :alertingUserIds]);

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Id userId : alertingUserIds) {
            User u = users.get(userId);
            if (u == null || String.isBlank(u.Email)) {
                continue;
            }

            OrgWatchController.UserPreferences prefs = allPrefs.get(userId);
            List<AlertRow> rows = buildAlertRows(prefs.metricThresholds, history);

            if (rows.isEmpty()) {
                continue;
            }

            Boolean anyBreach = false;
            for (AlertRow r : rows) {
                if (r.breachCount > 0) {
                    anyBreach = true;
                    break;
                }
            }

            if (prefs.emailMode == 'OnlyOnBreach' && !anyBreach) {
                continue;
            }

            String lang = String.isNotBlank(prefs.language) ? prefs.language : DEFAULT_LANGUAGE;

            rows.sort();
            emails.add(buildEmail(u, rows, anyBreach, lang));
        }

        lastEmailsBuiltCount = emails.size();

        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails, false);
        }
    }

    @TestVisible
    private static List<AlertRow> buildAlertRows(String metricThresholdsRaw, Map<String, List<OrgWatchController.DataPoint>> history) {
        List<AlertRow> rows = new List<AlertRow>();
        Map<String, Integer> thresholds = parseThresholds(metricThresholdsRaw);

        for (String metricName : thresholds.keySet()) {
            List<OrgWatchController.DataPoint> points = history.get(metricName);
            if (points == null || points.isEmpty()) {
                continue;
            }

            Integer threshold = thresholds.get(metricName);
            Integer breachCount = 0;

            for (OrgWatchController.DataPoint dp : points) {
                Decimal pct = dp.max > 0 ? (Decimal.valueOf(dp.current) / Decimal.valueOf(dp.max) * 100) : 0;
                if (pct >= threshold) {
                    breachCount++;
                }
            }

            OrgWatchController.DataPoint latest = points[points.size() - 1];
            Decimal latestPct = latest.max > 0
                ? (Decimal.valueOf(latest.current) / Decimal.valueOf(latest.max) * 100).setScale(1)
                : 0;

            rows.add(new AlertRow(metricName, threshold, breachCount, points.size(), latest.current, latest.max, latestPct));
        }

        return rows;
    }

    @TestVisible
    private static Map<String, Integer> parseThresholds(String metricThresholdsRaw) {
        Map<String, Integer> result = new Map<String, Integer>();
        if (String.isBlank(metricThresholdsRaw)) {
            return result;
        }

        for (String pair : metricThresholdsRaw.split(',')) {
            List<String> kv = pair.split(':');
            if (kv.size() == 2 && String.isNotBlank(kv[0]) && kv[1].trim().isNumeric()) {
                result.put(kv[0].trim(), Integer.valueOf(kv[1].trim()));
            }
        }

        return result;
    }

    private static String t(String key, String lang) {
        Map<String, String> entry = EMAIL_TEXT.get(key);
        if (entry == null) return '';
        String value = entry.get(lang);
        return value != null ? value : entry.get(DEFAULT_LANGUAGE);
    }

    private static String metricLabel(String metricName, String lang) {
        Map<String, String> entry = METRIC_LABELS.get(metricName);
        if (entry == null) return metricName;
        String label = entry.get(lang);
        return String.isNotBlank(label) ? label : metricName;
    }

    private static Messaging.SingleEmailMessage buildEmail(User u, List<AlertRow> rows, Boolean anyBreach, String lang) {
        Integer breachedMetricsCount = 0;
        for (AlertRow r : rows) {
            if (r.breachCount > 0) {
                breachedMetricsCount++;
            }
        }

        String bannerBg = anyBreach ? OrgWatchEmailBranding.COLOR_WARNING_SOFT : OrgWatchEmailBranding.COLOR_SUCCESS_SOFT;
        String bannerFg = anyBreach ? OrgWatchEmailBranding.COLOR_WARNING : OrgWatchEmailBranding.COLOR_SUCCESS;
        String bannerText = anyBreach
            ? breachedMetricsCount + t('bannerBreachMid', lang) + rows.size() + t('bannerBreachSuffix', lang)
            : t('bannerOk', lang);

        String rowsHtml = '';
        for (AlertRow r : rows) {
            rowsHtml += buildRowHtml(r, lang);
        }

        String subject = anyBreach
            ? t('subjectBreach', lang) + breachedMetricsCount + t('subjectBreachSuffix', lang)
            : t('subjectOk', lang);

        String bodyHtml = '<h2 style="margin:0 0 4px;color:' + OrgWatchEmailBranding.COLOR_TEXT_PRIMARY + ';">' + t('title', lang) + '</h2>'
            + '<p style="color:' + OrgWatchEmailBranding.COLOR_TEXT_SECONDARY + ';margin:0 0 20px;">' + t('greetingPrefix', lang) + OrgWatchEmailBranding.escapeHtml(u.Name) + t('greetingSuffix', lang) + '</p>'
            + '<div style="background:' + bannerBg + ';color:' + bannerFg + ';padding:14px 16px;border-radius:8px;font-weight:700;margin-bottom:20px;">'
            + (anyBreach ? '&#9888;&#65039; ' : '&#9989; ') + bannerText
            + '</div>'
            + '<table style="width:100%;border-collapse:collapse;">'
            + '<thead><tr style="font-size:11px;text-transform:uppercase;letter-spacing:0.03em;color:' + OrgWatchEmailBranding.COLOR_TEXT_SECONDARY + ';">'
            + '<th style="padding:6px 10px;text-align:left;">' + t('colMetric', lang) + '</th>'
            + '<th style="padding:6px 10px;text-align:left;">' + t('colBreakdown', lang) + '</th>'
            + '<th style="padding:6px 10px;text-align:left;">' + t('colBreaches', lang) + '</th>'
            + '<th style="padding:6px 10px;text-align:left;">' + t('colCurrentValue', lang) + '</th>'
            + '<th style="padding:6px 10px;text-align:left;">' + t('colThreshold', lang) + '</th>'
            + '</tr></thead>'
            + '<tbody>' + rowsHtml + '</tbody>'
            + '</table>'
            + '<p style="color:#9a9a9a;font-size:11px;margin-top:24px;">'
            + t('footerPrefix', lang)
            + '<a href="' + OrgWatchEmailBranding.getAppUrl() + '" style="color:' + OrgWatchEmailBranding.COLOR_ACCENT + ';font-weight:600;text-decoration:underline;">' + t('footerLinkText', lang) + '</a>'
            + t('footerSuffix', lang)
            + '</p>';

        String html = OrgWatchEmailBranding.wrap(bodyHtml, lang);

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setTargetObjectId(u.Id);
        mail.setSaveAsActivity(false);
        mail.setSubject(subject);
        mail.setHtmlBody(html);

        lastEmailSubject = subject;
        lastEmailHtmlBody = html;

        return mail;
    }

    private static String buildRowHtml(AlertRow r, String lang) {
        Decimal ratio = r.breachRatio();
        String color = ratio == 0 ? OrgWatchEmailBranding.COLOR_SUCCESS : (ratio < 0.34 ? OrgWatchEmailBranding.COLOR_WARNING : OrgWatchEmailBranding.COLOR_CRITICAL);
        Integer filled = (Integer) Math.round(ratio * BAR_SEGMENTS);

        return '<tr style="border-top:1px solid ' + OrgWatchEmailBranding.COLOR_BORDER + ';">'
            + '<td style="padding:10px;font-weight:600;color:' + OrgWatchEmailBranding.COLOR_TEXT_PRIMARY + ';">' + OrgWatchEmailBranding.escapeHtml(metricLabel(r.metricName, lang)) + '</td>'
            + '<td style="padding:10px;">' + buildBarHtml(filled, color) + '</td>'
            + '<td style="padding:10px;font-weight:700;color:' + color + ';white-space:nowrap;">' + r.breachCount + '/' + r.totalPoints + '</td>'
            + '<td style="padding:10px;color:' + OrgWatchEmailBranding.COLOR_TEXT_SECONDARY + ';font-size:12px;white-space:nowrap;">' + r.currentValue + ' / ' + r.maxValue + ' (' + r.currentPercent + '%)</td>'
            + '<td style="padding:10px;color:' + OrgWatchEmailBranding.COLOR_TEXT_SECONDARY + ';font-size:12px;white-space:nowrap;">' + r.threshold + '%</td>'
            + '</tr>';
    }

    /**
     * Barre segmentée en <table>/<td>, pas en <span style="display:inline-block">
     * (l'ancienne version) : Outlook (moteur Word) et d'autres clients mail
     * n'appliquent pas fiablement inline-block ni les couleurs de fond sur des
     * span, ce qui faisait apparaître la colonne "Répartition 24h" vide à la
     * réception. Une table imbriquée avec largeur/hauteur en attributs HTML
     * (en plus du style inline) est la technique standard, fiable, en email HTML.
     */
    private static String buildBarHtml(Integer filled, String color) {
        String html = '<table cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;"><tr>';
        for (Integer i = 0; i < BAR_SEGMENTS; i++) {
            String segColor = i < filled ? color : '#e5e5e5';
            String paddingStyle = i < BAR_SEGMENTS - 1 ? 'padding-right:2px;' : '';
            html += '<td width="12" height="10" style="' + paddingStyle + '">'
                + '<div style="width:12px;height:10px;line-height:10px;font-size:0;background-color:' + segColor + ';border-radius:2px;">&nbsp;</div>'
                + '</td>';
        }
        html += '</tr></table>';
        return html;
    }

    public class AlertRow implements Comparable {
        public String metricName;
        public Integer threshold;
        public Integer breachCount;
        public Integer totalPoints;
        public Long currentValue;
        public Long maxValue;
        public Decimal currentPercent;

        public AlertRow(String metricName, Integer threshold, Integer breachCount, Integer totalPoints, Long currentValue, Long maxValue, Decimal currentPercent) {
            this.metricName = metricName;
            this.threshold = threshold;
            this.breachCount = breachCount;
            this.totalPoints = totalPoints;
            this.currentValue = currentValue;
            this.maxValue = maxValue;
            this.currentPercent = currentPercent;
        }

        public Decimal breachRatio() {
            return totalPoints > 0 ? (Decimal.valueOf(breachCount) / Decimal.valueOf(totalPoints)) : 0;
        }

        public Integer compareTo(Object other) {
            AlertRow o = (AlertRow) other;
            Decimal diff = o.breachRatio() - this.breachRatio();
            if (diff > 0) return 1;
            if (diff < 0) return -1;
            return 0;
        }
    }
}