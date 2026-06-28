# ST05 Performance Analyser – Installationsanleitung

## Voraussetzungen

| Kriterium | Anforderung |
|-----------|-------------|
| SAP-Release | S/4HANA On-Premise 2023 SP4 oder höher |
| Datenbank | SAP HANA (für HANA-spezifische Felder) |
| Benutzerrechte | Basis-Entwickler (S_DEVELOP ACTVT 01/02) |
| ST05-Traces | Mindestens ein gesicherter ST05-Trace in PTC_DIRECTORY (TYPE = 'ST05') |

---

## Schritt 1: Paket anlegen

In SE80 oder ABAP Development Tools (Eclipse):

1. Paket **ZPERFORMANCE_ANALYSER** anlegen
   - Paketart: Erweiterbares Paket
   - Anwendungskomponente: leer oder eigene
   - Transportschicht: eigene (z. B. ZDEV)
2. Transportauftrag erstellen oder vorhandenen auswählen

---

## Schritt 2: Dictionary-Objekte anlegen

### 2.1 Domänen (4 Stück)

Alle Domänen aus `src/dictionary/ZPA_DOMAINS.abap` in SE11 anlegen:

| Domänenname | Typ | Länge | Feste Werte |
|-------------|-----|-------|-------------|
| ZPA_PRIORITAET | CHAR | 10 | KRITISCH, HOCH, MITTEL, NIEDRIG, HINWEIS |
| ZPA_KATEGORIE | CHAR | 20 | DB_ACCESS, ABAP_LOGIK, CDS_ODATA, RFC_BAPI, CUSTOM_CODE, STD_EXIT, ARCHITEKTUR |
| ZPA_FINDING_TYPE | CHAR | 30 | SELECT_LOOP, FULL_SCAN, NO_WHERE, HIGH_RUNTIME, EXPENSIVE_JOIN, CDS_EXPENSIVE, LOW_SELECT, DUPLICATE_SQL, ODATA_SLOW, RFC_SLOW, TIME_ANOMALY, CLUSTER_ACCESS |
| ZPA_OPT_HEBEL | CHAR | 10 | HOCH, MITTEL, NIEDRIG |

> Tipp: Ohne F4-Wertehilfe kann man die Domänen weglassen und direkt mit CHAR-Typen arbeiten. Die Detektoren funktionieren ohne Domänen.

### 2.2 Transparente Tabellen

Alle Tabellen in SE11 als **Transparente Tabelle** mit Delivery Class **A** anlegen.

#### ZPA_TRACE_SESSION (Analyse-Sessions)

| Feld | Typ | Schlüssel | Beschreibung |
|------|-----|-----------|--------------|
| MANDT | MANDT | X | Mandant |
| SESSION_ID | RAW(16) | X | UUID (sysuuid_x16) |
| SESSION_NAME | CHAR(80) | | Beschreibungstext |
| TRACE_SOURCE | CHAR(10) | | PTC / SQLM / FILE |
| SYSTEM_ID | CHAR(10) | | SID |
| UMGEBUNG | CHAR(20) | | DEV / QAS / PRD |
| MODUL | CHAR(20) | | FI, MM, SD, ... |
| DATE_FROM | DATS | | Trace-Zeitraum von |
| DATE_TO | DATS | | Trace-Zeitraum bis |
| ERFASST_AM | DATS | | Erfassungsdatum |
| ERFASST_UM | TIMS | | Erfassungszeit |
| ERFASST_VON | CHAR(12) | | Benutzername |
| TOTAL_FINDINGS | INT4 | | Gesamtanzahl Findings |
| KRITISCH_COUNT | INT4 | | Kritische Findings |
| HOCH_COUNT | INT4 | | Hohe Findings |
| PTC_GUID | RAW(16) | | GUID aus PTC_DIRECTORY |
| PTC_OWNER | CHAR(12) | | Owner aus PTC_DIRECTORY |
| PTC_INSTANCE | CHAR(20) | | Instance-Name |

#### ZPA_TRACE_ITEM (Trace-Einzelsätze)

| Feld | Typ | Schlüssel | Beschreibung |
|------|-----|-----------|--------------|
| MANDT | MANDT | X | Mandant |
| SESSION_ID | RAW(16) | X | Session-Referenz |
| ITEM_SEQ | INT4 | X | Laufende Nummer |
| DATA_SOURCE | CHAR(20) | | PTC_MAIN / PTC_VALUEID / ... |
| STMT_TYPE | CHAR(30) | | SELECT / INSERT / SUMM_IDENT / ... |
| SQL_TEXT | STRING | | SQL mit Named-Parametern |
| SQL_HASH | CHAR(32) | | HANA Statement Hash |
| TABNAME | CHAR(30) | | Primärtabelle |
| OBJECTS_RAW | STRING | | Alle Tabellen (bei JOIN) |
| LAUFZEIT_US | INT8 | | Gesamtlaufzeit in µs |
| AVG_DURATION_US | INT8 | | Ø-Laufzeit je Ausführung |
| HANA_PROC_TIME_US | INT8 | | HANA-Verarbeitungszeit |
| HANA_CPU_TIME_US | INT8 | | HANA-CPU-Zeit |
| HANA_MAX_MEMORY_KB | INT8 | | HANA-Speicher (KB) |
| ANZAHL_EXEC | INT4 | | Ausführungsanzahl |
| RECORDS_FETCHED | INT4 | | Gelesene Datensätze |
| AVG_ROWS | INT4 | | Ø-Datensätze je Ausführung |
| ARRAY_SIZE | INT4 | | Array-Fetch-Größe |
| PROGRAM_NAME | CHAR(40) | | ABAP-Programm |
| TRANSACTION | CHAR(20) | | Transaktion |
| USER_NAME | CHAR(12) | | Ausführender Benutzer |
| WP_ID | INT4 | | Work-Prozess-ID |
| WP_TYPE | CHAR(2) | | DI / BT / UP / ... |
| EPP_ROOT_ID | CHAR(32) | | EPP Korrelations-ID |
| TRACE_DATE | DATS | | Datum des Traces |
| TRACE_TIME | TIMS | | Startzeit des Traces |
| INSTANCE_NM | CHAR(20) | | Instanzname |
| HAS_WHERE | CHAR(1) | | X = WHERE-Klausel vorhanden |
| IS_CUSTOM_CODE | CHAR(1) | | X = Z*/Y* Programm |
| BUFFER_TYPE | CHAR(1) | | Puffertyp der Tabelle |
| TABCLASS | CHAR(10) | | Tabellenklasse |
| RETURN_CODE | INT4 | | SQL Return Code |

#### ZPA_FINDING (Performance-Findings)

| Feld | Typ | Schlüssel | Beschreibung |
|------|-----|-----------|--------------|
| MANDT | MANDT | X | Mandant |
| FINDING_ID | RAW(16) | X | UUID (sysuuid_x16) |
| SESSION_ID | RAW(16) | | Session-Referenz |
| ITEM_SEQ | INT4 | | Referenz auf ZPA_TRACE_ITEM |
| FINDING_TYPE | ZPA_FINDING_TYPE | | Art des Findings |
| KATEGORIE | ZPA_KATEGORIE | | Kategorie |
| PRIORITAET | ZPA_PRIORITAET | | Bewertete Priorität |
| SCORE | INT1 | | Numerischer Score 0-100 |
| OPTIM_HEBEL | ZPA_OPT_HEBEL | | Optimierungshebel |
| PROGRAMM | CHAR(40) | | ABAP-Programm |
| TABNAME | CHAR(30) | | Primärtabelle |
| SQL_HASH | CHAR(32) | | HANA Statement Hash |
| SQL_KURZFORM | CHAR(200) | | SQL (erste 200 Zeichen) |
| LAUFZEIT_US | INT8 | | Laufzeit in µs |
| ANZAHL_EXEC | INT4 | | Ausführungsanzahl |
| DATENMENGE | INT4 | | Datensätze |
| IS_CUSTOM_CODE | CHAR(1) | | X = Custom Code |
| TECHNISCHE_URSACHE | STRING | | Technische Erläuterung |
| FACHLICHE_EINSCH | STRING | | Fachliche Einschätzung |
| EMPF_MASSNAHME | STRING | | Empfohlene Maßnahme |
| CALL_HIERARCHY | STRING | | Aufrufhierarchie (Phase 2) |
| NOTIZ | STRING | | Manuelle Notizen |
| STATUS | CHAR(1) | | O=Offen G=Gelöst I=Ignoriert |
| GEAENDERT_AM | DATS | | Letzte Änderung |
| GEAENDERT_VON | CHAR(12) | | Geändert von |

#### ZPA_FINDING_TYPE (Customizing-Katalog)

| Feld | Typ | Schlüssel | Beschreibung |
|------|-----|-----------|--------------|
| MANDT | MANDT | X | Mandant |
| FINDING_TYPE | ZPA_FINDING_TYPE | X | Finding-Typ |
| BESCHREIBUNG | CHAR(60) | | Kurzbeschreibung |
| KATEGORIE | ZPA_KATEGORIE | | Standard-Kategorie |
| BASIS_SCORE | INT1 | | Basis-Score 0-100 |
| SCHWELLE_LAUFZEIT | INT8 | | Laufzeit-Schwelle (µs) |
| SCHWELLE_ANZAHL | INT4 | | Mindest-Ausführungen |
| SCHWELLE_ROWS | INT4 | | Mindest-Datensätze |
| AKTIV | CHAR(1) | | X = Detektor aktiv |

#### ZPA_CONFIG (Konfigurationsparameter)

| Feld | Typ | Schlüssel | Beschreibung |
|------|-----|-----------|--------------|
| MANDT | MANDT | X | Mandant |
| PARAMETER | CHAR(30) | X | Parametername |
| WERT_NUM | INT8 | | Numerischer Wert |
| WERT_DEC | DEC(5,2) | | Dezimalwert |
| BESCHREIBUNG | CHAR(60) | | Erläuterung |

---

## Schritt 3: Startwerte in ZPA_CONFIG eintragen (SM30)

```
PARAMETER          WERT_NUM    Beschreibung
RT_KRITISCH        10000000    Kritisch: > 10 Sek (µs)
RT_HOCH             2000000    Hoch: > 2 Sek (µs)
RT_MITTEL            500000    Mittel: > 0,5 Sek (µs)
LOOP_MIN_EXEC              5    Mindest-Ausführungen SELECT-Loop
DUPLICATE_MIN              3    Mindest-Ausführungen Duplikat
ODATA_MIN_RT        2000000    OData-Schwelle (µs)
RFC_MIN_RT          5000000    RFC-Schwelle (µs)
FULL_SCAN_MIN_ROWS    10000    Mindest-Zeilen für Full-Scan
FULL_SCAN_MIN_RT     100000    Mindest-Laufzeit Full-Scan (µs)
```

Dezimalwerte für Scoring-Gewichtung (WERT_DEC):
```
SCORE_W_RUNTIME     0.35
SCORE_W_FREQUENCY   0.25
SCORE_W_DATAVOLUME  0.20
SCORE_W_PATTERN     0.15
SCORE_W_CUSTOM      0.05
```

---

## Schritt 4: Startwerte in ZPA_FINDING_TYPE eintragen (SM30)

```
FINDING_TYPE    BESCHREIBUNG                      BASIS_SCORE  AKTIV
SELECT_LOOP     SELECT in Schleife                90           X
FULL_SCAN       Full Table Scan                   80           X
NO_WHERE        SELECT ohne WHERE-Klausel         85           X
HIGH_RUNTIME    Hohe Einzellaufzeit               70           X
EXPENSIVE_JOIN  Teurer JOIN                       75           X
CDS_EXPENSIVE   Teurer CDS-View-Zugriff           70           X
LOW_SELECT      Minimale Datenselektion           40           X
DUPLICATE_SQL   Duplizierter SQL                  65           X
ODATA_SLOW      Langsame OData-Operation          70           X
RFC_SLOW        Langsame RFC/BAPI-Operation       60           X
TIME_ANOMALY    Zeitliche Anomalie                50           X
CLUSTER_ACCESS  Cluster-/Pool-Tabellenzugriff     55           X
```

---

## Schritt 5: ABAP-Objekte anlegen

Die folgenden Objekte aus dem Verzeichnis `src/` in der aufgeführten Reihenfolge anlegen:

### Reihenfolge (Abhängigkeiten beachten)

| Schritt | Objekt | Typ | Beschreibung |
|---------|--------|-----|--------------|
| 5.1 | ZIF_PA_DETECTOR | Interface | Detektor-Schnittstelle |
| 5.2 | ZCX_PA_IMPORT_ERROR | Exception | Fehlerklasse |
| 5.3 | ZIF_PA_DATA_SOURCE | Interface | Datenquellen-Schnittstelle |
| 5.4 | ZCL_PA_SCORER | Klasse | Scoring-Engine |
| 5.5 | ZCL_PA_SRC_PTC | Klasse | ST05-Trace-Connector |
| 5.6 | ZCL_PA_DET_SELECT_LOOP | Klasse | Detektor SELECT-Loop |
| 5.7 | ZCL_PA_DET_FULL_SCAN | Klasse | Detektor Full-Scan |
| 5.8 | ZCL_PA_DET_HIGH_RUNTIME | Klasse | Detektor Hohe Laufzeit |
| 5.9 | ZCL_PA_DET_DUPLICATE | Klasse | Detektor Duplikat-SQL |
| 5.10 | ZCL_PA_DET_ODATA | Klasse | Detektor OData/RFC |
| 5.11 | ZCL_PA_ANALYSER | Klasse | Orchestrierung |
| 5.12 | ZCL_PA_OUTPUT_ALV | Klasse | ALV-Ausgabe |
| 5.13 | ZRPA_PERF_ANALYSE | Report | Hauptprogramm |

### 5.2 Fehlerklasse ZCX_PA_IMPORT_ERROR

In SE24 als Exception-Klasse anlegen, die von CX_STATIC_CHECK erbt:

- Superklasse: `CX_STATIC_CHECK`
- Attribut: `MV_INFO TYPE STRING` (öffentlich, Instanz)
- Text-ID: `ZCX_PA_IMPORT_ERROR` mit Standard-Text „{MV_INFO}"

Alternativ ohne eigene Texte:

```abap
CLASS zcx_pa_import_error DEFINITION PUBLIC
  INHERITING FROM cx_static_check FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    DATA mv_info TYPE string.
    METHODS constructor
      IMPORTING
        mv_info  TYPE string OPTIONAL
        previous TYPE REF TO cx_root OPTIONAL.
ENDCLASS.

CLASS zcx_pa_import_error IMPLEMENTATION.
  METHOD constructor.
    super->constructor( previous = previous ).
    me->mv_info = mv_info.
  ENDMETHOD.
ENDCLASS.
```

### 5.3 Datenquellen-Interface ZIF_PA_DATA_SOURCE

```abap
INTERFACE zif_pa_data_source PUBLIC.
  METHODS get_source_type
    RETURNING VALUE(rv_type) TYPE char10.
  METHODS fetch
    IMPORTING
      is_criteria TYPE zpa_fetch_criteria
    RETURNING
      VALUE(rt_items) TYPE zif_pa_detector=>tt_items.
ENDINTERFACE.
```

Struktur **ZPA_FETCH_CRITERIA** (lokal oder als Dictionary-Struktur):

```abap
TYPES: BEGIN OF zpa_fetch_criteria,
         session_id TYPE sysuuid_x16,
         date_from  TYPE dats,
         date_to    TYPE dats,
         username   TYPE syuname,
       END OF zpa_fetch_criteria.
```

---

## Schritt 6: Report ZRPA_PERF_ANALYSE als ausführbares Programm

In SE38:
1. Neues Programm `ZRPA_PERF_ANALYSE` anlegen
2. Programmtyp: **Ausführbares Programm** (Typ 1)
3. Quellcode aus `src/ZRPA_PERF_ANALYSE.abap` einfügen
4. Screen 100 anlegen (PAI/PBO leer – nur für ALV-Fullscreen benötigt)

### Screen 100 (Minimal-Screen für ALV)

Über Menu-Painter (SE51) für Programm ZRPA_PERF_ANALYSE:
- Screen 0100 anlegen
- PBO-Modul: STATUS_0100 (leer oder mit SET PF-STATUS)
- PAI-Modul: USER_COMMAND_0100 mit LEAVE TO SCREEN 0 bei COMMAND = 'BACK'/'EXIT'/'CANC'

Einfachste Implementierung im Report selbst:

```abap
MODULE status_0100 OUTPUT.
  " ALV zeigt eigene Toolbar – kein eigener Status nötig
ENDMODULE.

MODULE user_command_0100 INPUT.
  CASE sy-ucomm.
    WHEN 'BACK' OR 'EXIT' OR 'CANC'.
      LEAVE TO SCREEN 0.
  ENDCASE.
ENDMODULE.
```

---

## Schritt 7: Berechtigungsobjekte prüfen

Der Report benötigt:
- **S_TCODE**: Transaktion ST05 aufrufen (für Verständnis, nicht zwingend)
- **S_TABU_DIS / S_TABU_NAM**: Lesezugriff auf PTC_DIRECTORY
- **S_DEVELOP**: Lesezugriff auf Entwicklungsobjekte (nur für eigene Z-Objekte)

Eigene Berechtigungsprüfung im Report (empfohlen für Produktivbetrieb):

```abap
AUTHORITY-CHECK OBJECT 'S_TABU_NAM'
  ID 'ACTVT' FIELD '03'
  ID 'TABLE' FIELD 'PTC_DIRECTORY'.
IF sy-subrc <> 0.
  MESSAGE 'Keine Berechtigung für PTC_DIRECTORY' TYPE 'E'.
ENDIF.
```

---

## Schritt 8: Erster Test

1. ST05 starten → Trace aufzeichnen → **Sichern** (nicht nur Anzeigen)
2. Report `ZRPA_PERF_ANALYSE` starten (SA38)
3. Modus **Neuer Import** wählen
4. Datumsbereich: heute, eigener Benutzer
5. **Ausführen** → Import-Log prüfen, Findings erscheinen im ALV

### Häufige Fehler beim ersten Start

| Fehler | Ursache | Lösung |
|--------|---------|--------|
| „kein Inhalt in PTC_DIRECTORY" | Trace nur angezeigt, nicht gesichert | ST05 → Trace sichern (Speichern-Button) |
| „IMPORT FROM DATA BUFFER fehlgeschlagen" | Trace-Typ nicht SQL | Nur SQL-Traces werden verarbeitet |
| Leere Findings-Liste | Keine Items über Schwellwert | ZPA_CONFIG-Schwellen reduzieren oder längere Traces aufzeichnen |
| Dump TYPE_MISMATCH in SRC_PTC | Falsches ST05-Release | Typdefinitionen mit SE11 gegen lokales System prüfen |

---

## Transportauftrag

Alle Objekte in einen einzigen Workbench-Transportauftrag aufnehmen:

```
Paket:         ZPERFORMANCE_ANALYSER
Auftrag-Typ:   Workbench-Auftrag
Ziel-System:   QAS → PRD (normaler Transport-Weg)
```

Reihenfolge beim Transport:
1. Dictionary-Objekte (Tabellen, Domänen) aktivieren und transportieren
2. Startwerte (ZPA_CONFIG, ZPA_FINDING_TYPE) als Customizing-Transport
3. ABAP-Objekte transportieren

---

## Erweiterung: Neue Detektoren

Neuen Detektor hinzufügen:

1. Klasse `ZCL_PA_DET_<NAME>` anlegen, Interface `ZIF_PA_DETECTOR` implementieren
2. In `ZCL_PA_ANALYSER->REGISTER_DETECTORS` eintragen:
   ```abap
   APPEND NEW zcl_pa_det_<name>( ) TO mt_detectors.
   ```
3. Finding-Typ in `ZPA_FINDING_TYPE` eintragen
4. Fertig – kein weiterer Code-Eingriff nötig

---

## Kontakt / Support

Bei Fragen zur technischen Basis (PTC_DIRECTORY-Struktur, ST05-Typen):
- SAP Note **[2170788]** – ST05: Trace-Dateien und Datenformate
- SAP Note **[2399174]** – HANA Statement Hash im SQL-Trace
- Transaktion **ST12** – ABAP-Trace (ergänzend zu ST05)
