"--------------------------------------------------------------------
" Nur 4 eigene Domänen – ausschließlich für Festwert-Listen (F4-Hilfe)
" Alle anderen Felder verwenden SAP-Standardtypen direkt.
"--------------------------------------------------------------------

" ZPA_PRIORITAET  CHAR 10
" Festwerte:
"   KRITISCH  Kritisch – sofortiger Handlungsbedarf
"   HOCH      Hoch – kurzfristiger Handlungsbedarf
"   MITTEL    Mittel – mittelfristiger Handlungsbedarf
"   NIEDRIG   Niedrig – nächste Entwicklungswelle
"   HINWEIS   Hinweis – Best-Practice-Abweichung

" ZPA_KATEGORIE  CHAR 20
" Festwerte:
"   DB_ACCESS   Datenbankzugriff
"   ABAP_LOGIK  ABAP-seitige Logik
"   CDS_ODATA   CDS-View / OData
"   RFC_BAPI    RFC / BAPI / Schnittstelle
"   CUSTOM_CODE Kundeneigener Code (Z*/Y*)
"   STD_EXIT    SAP-Standard-Erweiterungspunkt
"   ARCHITEKTUR Strukturelles / Architekturproblem

" ZPA_FINDING_TYPE  CHAR 30
" Festwerte:
"   SELECT_LOOP    SELECT-Statement in ABAP-Schleife
"   FULL_SCAN      Full Table Scan ohne Index
"   NO_WHERE       SELECT ohne WHERE-Bedingung
"   HIGH_RUNTIME   Hohe Einzellaufzeit
"   EXPENSIVE_JOIN Teurer JOIN
"   CDS_EXPENSIVE  Teurer CDS-View-Zugriff
"   LOW_SELECT     Geringe Selektivität
"   DUPLICATE_SQL  Identisches SQL mehrfach ausgeführt
"   ODATA_SLOW     OData/Gateway hohe Laufzeit
"   RFC_SLOW       RFC/BAPI hohe Laufzeit
"   TIME_ANOMALY   DB/ABAP-Zeitverhältnis auffällig
"   CLUSTER_ACCESS Zugriff auf Cluster-/Pool-Tabelle

" ZPA_OPT_HEBEL  CHAR 10
" Festwerte:
"   HOCH    > 80% Laufzeitreduktion erwartet
"   MITTEL  30-80% Laufzeitreduktion erwartet
"   NIEDRIG < 30% Laufzeitreduktion erwartet
