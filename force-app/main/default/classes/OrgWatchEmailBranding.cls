/**
 * Gabarit de marque commun à tous les emails HTML d'OrgWatch (alertes,
 * notifications d'accès admin...) : palette de couleurs, logo, bandeau de
 * marque et pied de page partagés pour un rendu cohérent d'un email à
 * l'autre. Centralisé ici pour éviter que chaque classe d'envoi ne
 * réimplémente/dérive sa propre variante du template.
 */
public class OrgWatchEmailBranding {

    // Couleurs alignées sur les tokens --ow-* d'orgWatchMonitoring.css (thème clair) :
    // un email HTML n'a pas de "thème sombre" côté client mail, on reste sur la
    // palette claire quel que soit le thème choisi dans l'app.
    public static final String COLOR_ACCENT = '#5b4fe0';
    public static final String COLOR_ACCENT_SOFT = '#eeecfb';
    public static final String COLOR_TEXT_PRIMARY = '#1a1530';
    public static final String COLOR_TEXT_SECONDARY = '#6d6884';
    public static final String COLOR_BORDER = '#e7e4f2';
    public static final String COLOR_SURFACE_ALT = '#f7f6fc';
    public static final String COLOR_SUCCESS = '#14805a';
    public static final String COLOR_SUCCESS_SOFT = '#e2f5ec';
    public static final String COLOR_WARNING = '#b3730e';
    public static final String COLOR_WARNING_SOFT = '#fbeed9';
    public static final String COLOR_CRITICAL = '#c2264a';
    public static final String COLOR_CRITICAL_SOFT = '#fbe6ec';

    private static final String LOGO_RESOURCE_NAME = 'org_watch_logo';
    @TestVisible private static String logoDataUriCache;

    private static final Map<String, String> TAGLINE = new Map<String, String>{
        'fr' => 'L\'inspecteur de vos limites Salesforce',
        'en' => 'The detective for your Salesforce limits'
    };

    private static final String APP_TAB_NAME = 'OrgWatch';

    /**
     * Le logo statique est encodé en base64 et inliné dans le HTML (data URI)
     * plutôt que référencé par son URL /resource/... : cette dernière exige
     * souvent une session Salesforce active pour être résolue, donc l'image
     * casse dans un client mail externe non connecté. Mise en cache statique
     * (une requête par exécution du job/action, pas par email envoyé).
     */
    public static String getLogoDataUri() {
        if (logoDataUriCache == null) {
            List<StaticResource> resources = [SELECT Body FROM StaticResource WHERE Name = :LOGO_RESOURCE_NAME LIMIT 1];
            logoDataUriCache = !resources.isEmpty()
                ? 'data:image/png;base64,' + EncodingUtil.base64Encode(resources[0].Body)
                : '';
        }
        return logoDataUriCache;
    }

    public static String tagline(String lang) {
        String value = TAGLINE.get(lang);
        return value != null ? value : TAGLINE.get('fr');
    }

    /**
     * URL vers l'onglet OrgWatch dans Lightning Experience, utilisable dans un
     * lien d'email ("cliquez ici pour ouvrir l'app") sans connaître l'Id de la
     * CustomApplication (non suivie en source, créée manuellement).
     */
    public static String getAppUrl() {
        return URL.getOrgDomainUrl().toExternalForm() + '/lightning/n/' + APP_TAB_NAME;
    }

    public static String escapeHtml(String value) {
        if (value == null) return '';
        return value.replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;')
            .replace('\'', '&#39;');
    }

    /**
     * Enveloppe bodyHtml dans le gabarit de marque OrgWatch (bandeau logo +
     * wordmark, liseré d'accent, pied de page) commun à tous les emails de
     * l'outil.
     */
    public static String wrap(String bodyHtml, String lang) {
        String logoDataUri = getLogoDataUri();
        String logoImgHtml = String.isNotBlank(logoDataUri)
            ? '<img src="' + logoDataUri + '" width="152" height="104" style="display:block;" alt="OrgWatch" />'
            : '';

        return '<html><body style="font-family:Arial,Helvetica,sans-serif;color:' + COLOR_TEXT_PRIMARY + ';background:' + COLOR_SURFACE_ALT + ';padding:24px 0;margin:0;">'
            + '<div style="max-width:680px;margin:0 auto;background:#ffffff;border-radius:12px;overflow:hidden;border:1px solid ' + COLOR_BORDER + ';">'
            + '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:' + COLOR_ACCENT_SOFT + ';">'
            + '<tr><td style="padding:26px 28px;">'
            + '<table role="presentation" cellpadding="0" cellspacing="0"><tr>'
            + '<td style="vertical-align:middle;padding-right:18px;">' + logoImgHtml + '</td>'
            + '<td style="vertical-align:middle;">'
            + '<div style="font-size:38px;font-weight:800;color:' + COLOR_ACCENT + ';letter-spacing:-0.01em;line-height:1.2;">OrgWatch</div>'
            + '<div style="font-size:21px;color:' + COLOR_TEXT_SECONDARY + ';">' + tagline(lang) + '</div>'
            + '</td>'
            + '</tr></table>'
            + '</td></tr></table>'
            + '<div style="height:4px;line-height:4px;font-size:0;background-color:' + COLOR_ACCENT + ';">&nbsp;</div>'
            + '<div style="padding:28px;">' + bodyHtml + '</div>'
            + '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-top:1px solid ' + COLOR_BORDER + ';background:' + COLOR_SURFACE_ALT + ';">'
            + '<tr><td style="padding:14px 28px;text-align:center;color:' + COLOR_TEXT_SECONDARY + ';font-size:11px;">OrgWatch &middot; ' + tagline(lang) + '</td></tr>'
            + '</table>'
            + '</div></body></html>';
    }

    /**
     * Bouton d'action générique (ex: "Ouvrir OrgWatch") pour un email HTML,
     * même style que le bandeau de marque.
     */
    public static String buildActionButtonHtml(String url, String label) {
        return '<table role="presentation" cellpadding="0" cellspacing="0"><tr><td style="border-radius:8px;background:' + COLOR_ACCENT + ';">'
            + '<a href="' + url + '" style="display:inline-block;padding:12px 22px;color:#ffffff;font-weight:700;text-decoration:none;font-family:Arial,Helvetica,sans-serif;">' + escapeHtml(label) + '</a>'
            + '</td></tr></table>';
    }
}