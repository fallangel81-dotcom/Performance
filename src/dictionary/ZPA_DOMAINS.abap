"--------------------------------------------------------------------
" Domänen – in SE11 anlegen (Typ: Domäne)
"--------------------------------------------------------------------

" ZPA_SESSION_ID – UUID einer Analyse-Sitzung
" Datentyp: RAW, Länge: 16

" ZPA_ITEM_SEQ – Laufende Nummer eines Trace-Satzes
" Datentyp: INT4

" ZPA_FINDING_ID – UUID eines Findings
" Datentyp: RAW, Länge: 16

" ZPA_TRACE_SOURCE – Quelle des Traces
" Datentyp: CHAR, Länge: 10
" Festwerte: PTC | HANA | STAD | FILE | MANUAL

" ZPA_STMT_TYPE – Typ des SQL-Statements oder Aggregats
" Datentyp: CHAR, Länge: 12
" Festwerte: SELECT | INSERT | UPDATE | DELETE | OPEN_CURSOR |
"            SUMM_TAB | SUMM_IDENT | SUMM_STRUCT

" ZPA_DATA_SOURCE – Herkunft des Trace-Satzes
" Datentyp: CHAR, Länge: 15
" Festwerte: PTC_MAIN | PTC_VALUEID | PTC_STRUCTID | PTC_TBLACCESS | HANA | STAD

" ZPA_FINDING_TYPE – Art des Performance-Anti-Pattern
" Datentyp: CHAR, Länge: 30
" Festwerte:
"   SELECT_LOOP    – SELECT in ABAP-Schleife
"   FULL_SCAN      – Full Table Scan
"   NO_WHERE       – SELECT ohne WHERE
"   HIGH_RUNTIME   – Hohe Einzellaufzeit
"   EXPENSIVE_JOIN – Teurer JOIN
"   CDS_EXPENSIVE  – Teurer CDS-View-Zugriff
"   LOW_SELECT     – Geringe Selektivität
"   DUPLICATE_SQL  – Identische SQLs mehrfach
"   ODATA_SLOW     – OData-Aufruf mit hoher Laufzeit
"   RFC_SLOW       – RFC/BAPI mit hoher Laufzeit
"   TIME_ANOMALY   – DB/ABAP-Zeitverhältnis auffällig
"   CLUSTER_ACCESS – Cluster-/Pool-Tabellenzugriff

" ZPA_KATEGORIE – fachliche Kategorie des Findings
" Datentyp: CHAR, Länge: 20
" Festwerte:
"   DB_ACCESS   – Datenbankzugriff
"   ABAP_LOGIK  – ABAP-seitige Logik
"   CDS_ODATA   – CDS-View / OData
"   RFC_BAPI    – RFC / BAPI / Schnittstelle
"   CUSTOM_CODE – Kundeneigener Code
"   STD_EXIT    – SAP-Standard-Erweiterungspunkt
"   ARCHITEKTUR – Strukturelles / Architekturproblem

" ZPA_PRIORITAET – Priorität / Schweregrad
" Datentyp: CHAR, Länge: 10
" Festwerte: KRITISCH | HOCH | MITTEL | NIEDRIG | HINWEIS

" ZPA_OPT_HEBEL – Erwarteter Optimierungshebel
" Datentyp: CHAR, Länge: 10
" Festwerte: HOCH | MITTEL | NIEDRIG

" ZPA_SCORE – Numerischer Bewertungs-Score
" Datentyp: INT1 (0-100)

" ZPA_LAUFZEIT_US – Laufzeit in Mikrosekunden
" Datentyp: INT8

" ZPA_ANZAHL – Allgemeine Mengenangabe
" Datentyp: INT4

" ZPA_BOOLEAN – Ja/Nein-Flag
" Datentyp: CHAR, Länge: 1 (identisch mit ABAP_BOOL)

" ZPA_MODUL – SAP-Modul / Applikationsbereich
" Datentyp: CHAR, Länge: 20
" Festwerte: FI | CO | MM | SD | PP | PM | QM | HR | BASIS | CUSTOM | ...

" ZPA_UMGEBUNG – Systemumgebung
" Datentyp: CHAR, Länge: 5
" Festwerte: DEV | QAS | PRD

" ZPA_SQL_HASH – HANA Statement Hash
" Datentyp: CHAR, Länge: 32

" ZPA_SESSION_NAME – Frei wählbarer Sitzungsname
" Datentyp: CHAR, Länge: 80

" ZPA_BESCHREIBUNG – Freitext-Beschreibung
" Datentyp: CHAR, Länge: 255

" ZPA_SQL_SHORT – SQL-Kurzform für Anzeige
" Datentyp: CHAR, Länge: 200
