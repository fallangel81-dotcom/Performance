# ST05 Performance Analyser – Fachlich-Technisches Konzept
## SAP S/4HANA On-Premise 2023 SP4 | Version 1.0 | Juni 2026

---

## Inhaltsverzeichnis

1. [Zielbild](#1-zielbild)
2. [Architektur](#2-architektur)
3. [Datenmodell](#3-datenmodell)
4. [Auswertungslogik & Performance-Indikatoren](#4-auswertungslogik--performance-indikatoren)
5. [Scoring- und Klassifikationsmodell](#5-scoring--und-klassifikationsmodell)
6. [UI- und Ausgabekonzept](#6-ui--und-ausgabekonzept)
7. [Erweiterbarkeit](#7-erweiterbarkeit)
8. [Konkrete technische Umsetzung](#8-konkrete-technische-umsetzung)
9. [Implementierungsplan](#9-implementierungsplan)
10. [Namenskonventionen & Paketstruktur](#10-namenskonventionen--paketstruktur)

---

## 1. Zielbild

### 1.1 Problemstellung

ST05 (SQL Trace / Performance Trace) ist das zentrale Werkzeug zur SQL-Analyse in SAP. Die Auswertung ist jedoch:

- **Manuell und zeitaufwändig** – jeder Trace wird einzeln betrachtet
- **Nicht vergleichbar** – kein historischer Kontext, kein Trend
- **Nicht priorisiert** – alle Probleme erscheinen gleichwertig
- **Nicht managementfähig** – keine Zusammenfassung für Entscheidungsträger
- **Nicht wiederverwendbar** – Erkenntnisse gehen verloren

### 1.2 Lösungsziel

Ein wiederverwendbarer **ST05 Performance Analyser** (Kurzname: **Z_PERF_ANALYSER**), der:

1. ST05-Exportdaten (XML/TXT) sowie ST12-ABAP-Traces importiert und strukturiert speichert
2. Automatisch Performance-Anti-Pattern erkennt und klassifiziert
3. Eine **priorisierte Mängelliste** mit Optimierungsempfehlungen erzeugt
4. Eine **managementfähige Übersicht** über Performance-Baustellen bereitstellt
5. **Historische Vergleiche** ermöglicht (Trend: besser/schlechter nach Optimierung)
6. Sowohl als **ABAP-Transaktion** als auch als **OData/RAP-Service** für Fiori verfügbar ist

### 1.3 Variantenentscheidung

| Kriterium | Variante A: ABAP Report | Variante B: RAP/OData Service |
|---|---|---|
| Time-to-Market | Schnell (Wochen) | Mittel (Monate) |
| Infrastruktur | Keine zusätzliche | Fiori Launchpad erforderlich |
| Historisierung | Über Persistenztabellen | Natürlich integriert |
| Visualisierung | ALV Grid (klassisch) | Fiori-Charts & KPI-Kacheln |
| Erweiterbarkeit | Mittel | Hoch (BTP-Integration möglich) |
| Zielgruppe | Entwickler/Basis | Entwickler + Management |

**Empfehlung: Hybridansatz**

- **Phase 1**: ABAP Report + ALV (sofort nutzbar, Datenbasis aufbauen)
- **Phase 2**: RAP-basierter OData-Service + Fiori-App (Management-Dashboard)
- **Optional Phase 3**: BTP-Integration für systemübergreifende Auswertung

---

## 2. Architektur

### 2.1 Gesamtarchitektur

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Z_PERF_ANALYSER – Gesamtarchitektur              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  DATENQUELLEN              IMPORT/PARSE           PERSISTENZ        │
│  ─────────────             ────────────           ─────────         │
│  ST05 XML-Export    ──►    XML-Parser      ──►    ZPA_TRACE_HDR     │
│  ST05 TXT-Export    ──►    TXT-Parser      ──►    ZPA_TRACE_ITEM    │
│  ST12 ABAP-Trace    ──►    ST12-Parser     ──►    ZPA_CALL_HIER     │
│  Direkt via API     ──►    API-Connector   ──►    ZPA_FINDINGS      │
│  (DBCON/DBTI)                                     ZPA_HISTORY       │
│                                                                     │
│  ANALYSE-ENGINE             SCORING                AUSGABE          │
│  ──────────────             ───────                ───────          │
│  SQL-Analyser       ──►    Scorer/Prio    ──►    ALV-Report        │
│  Pattern-Detector   ──►    Klassifier    ──►    Fiori-App          │
│  CDS-Analyser       ──►    Recommender   ──►    OData-Service      │
│  RFC-Analyser       ──►    Aggregator    ──►    Excel-Export        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 Komponentenübersicht

```
ZCL_PA_IMPORTER           – Orchestrierung des Imports
  ├── ZCL_PA_PARSER_ST05_XML   – ST05 XML-Format Parser
  ├── ZCL_PA_PARSER_ST05_TXT   – ST05 Text-Export Parser
  └── ZCL_PA_PARSER_ST12       – ST12 ABAP-Trace Parser

ZCL_PA_ANALYSER           – Orchestrierung der Analyse
  ├── ZCL_PA_ANAL_SQL          – SQL-Pattern-Erkennung
  ├── ZCL_PA_ANAL_LOOP         – SELECT-in-Loop-Erkennung
  ├── ZCL_PA_ANAL_CDS          – CDS/OData-Analyse
  ├── ZCL_PA_ANAL_RFC          – RFC/BAPI-Analyse
  └── ZCL_PA_ANAL_ABAP         – ABAP-Zeit-Analyse

ZCL_PA_SCORER             – Scoring & Priorisierung
ZCL_PA_RECOMMENDER        – Maßnahmen-Engine
ZCL_PA_OUTPUT_ALV         – ALV-Ausgabe
ZCL_PA_OUTPUT_SERVICE     – OData/RAP-Ausgabe

ZRPA_PERF_ANALYSE         – Haupt-Report (ABAP)
ZTX_PERF_ANALYSER         – Transaktion
```

### 2.3 Technologie-Stack

| Schicht | Technologie | SAP-Objekt |
|---|---|---|
| Persistenz | ABAP Dictionary Transparente Tabellen | ZPA_* Tabellen |
| Business Logic | ABAP OO (Klassen/Interfaces) | ZCL_PA_* |
| Import | ABAP XML-Transformation / String-Processing | ZCL_PA_PARSER_* |
| Ausgabe klassisch | ALV Grid Control (CL_GUI_ALV_GRID) | ZCL_PA_OUTPUT_ALV |
| Ausgabe modern | RAP (ABAP RESTful Application Programming) | ZI_PA_*, ZC_PA_* |
| Fiori-UI | Fiori Elements (List Report + Object Page) | Fiori-App |
| Transaktion | SE93 Transaktion | ZTX_PERF_ANALYSER |

---

## 3. Datenmodell

### 3.1 Persistenztabellen

#### ZPA_TRACE_SESSION – Trace-Sitzungen (Header)

```abap
@EndUserText.label : 'PA: Trace-Sitzungen'
@AbapCatalog.enhancement.category : #NOT_EXTENSIBLE
define table zpa_trace_session {
  key session_id    : zpa_session_id;      " UUID
  session_name      : zpa_session_name;    " Frei wählbarer Name
  trace_source      : zpa_trace_source;    " ST05 / ST12 / MANUAL
  trace_type        : zpa_trace_type;      " SQL / RFC / ENQUEUE / ALL
  system_id         : sysid;               " SAP System-ID
  mandant           : mandt;
  erfasst_am        : dats;
  erfasst_um        : tims;
  erfasst_von       : uname;
  beschreibung      : zpa_beschreibung;    " Freitext
  modul             : zpa_modul;           " FI / MM / SD / Custom etc.
  umgebung          : zpa_umgebung;        " DEV / QAS / PRD
  session_status    : zpa_sess_status;     " NEU / IN_ANALYSE / FERTIG
  gesamt_laufzeit   : zpa_laufzeit_us;     " Gesamtlaufzeit µs
  db_laufzeit       : zpa_laufzeit_us;     " DB-Zeit µs
  abap_laufzeit     : zpa_laufzeit_us;     " ABAP-Zeit µs
  anzahl_statements : zpa_anzahl;          " Summe SQL-Statements
}
```

#### ZPA_TRACE_ITEM – Einzelne Trace-Einträge

```abap
@EndUserText.label : 'PA: Trace-Einträge'
define table zpa_trace_item {
  key session_id    : zpa_session_id;
  key item_seq      : zpa_item_seq;        " Laufende Nummer
  stmt_type         : zpa_stmt_type;       " SELECT/INSERT/UPDATE/DELETE/OPEN CURSOR
  tabname           : tabname;             " Tabelle oder CDS-View
  program_name      : progname;            " ABAP-Programm
  include_name      : include;             " Include
  klasse            : seoclsname;          " Klasse (falls ermittelbar)
  methode           : seocpdname;          " Methode
  zeile             : i;                   " Zeilennummer
  laufzeit_us       : zpa_laufzeit_us;     " Laufzeit in µs
  anzahl_exec       : zpa_anzahl;          " Anzahl Ausführungen
  records_fetched   : zpa_anzahl;          " Gelesene Datensätze
  records_selected  : zpa_anzahl;          " Selektierte Datensätze (nach WHERE)
  buffer_hit        : zpa_boolean;         " Aus Puffer gelesen
  sql_text          : string;              " SQL-Statement (Kurzform/Hash)
  sql_hash          : zpa_sql_hash;        " Hash für Deduplizierung
  has_where         : zpa_boolean;         " WHERE-Bedingung vorhanden
  where_fields      : string;              " WHERE-Felder (kommasepariert)
  index_used        : zpa_boolean;         " Index genutzt
  index_name        : zpa_index_name;      " Genutzter Index
  call_depth        : i;                   " Aufruftiefe in Call-Hierarchie
  parent_seq        : zpa_item_seq;        " Übergeordneter Eintrag
}
```

#### ZPA_FINDING – Erkannte Performance-Probleme

```abap
@EndUserText.label : 'PA: Performance-Findings'
define table zpa_finding {
  key finding_id    : zpa_finding_id;      " UUID
  session_id        : zpa_session_id;
  item_seq          : zpa_item_seq;        " Bezug auf Trace-Item (optional)
  finding_type      : zpa_finding_type;    " Typ des Anti-Pattern
  kategorie         : zpa_kategorie;       " DB/ABAP/CDS/RFC/CUSTOM/etc.
  prioritaet        : zpa_prioritaet;      " KRITISCH/HOCH/MITTEL/NIEDRIG/HINWEIS
  score             : zpa_score;           " Numerischer Score 0-100
  programm          : progname;
  include_name      : include;
  klasse            : seoclsname;
  methode           : seocpdname;
  zeile             : i;
  tabname           : tabname;
  sql_kurzform      : zpa_sql_short;       " Kurzdarstellung des SQL
  laufzeit_us       : zpa_laufzeit_us;
  anzahl_exec       : zpa_anzahl;
  datenmenge        : zpa_anzahl;
  technische_ursache: string;
  fachliche_einsch  : string;
  empf_massnahme    : string;
  optim_hebel       : zpa_opt_hebel;       " HOCH/MITTEL/NIEDRIG
  is_custom_code    : zpa_boolean;         " Z* / Y* Namensraum
  call_hierarchy    : string;              " JSON: Aufrufpfad
  erstellt_am       : dats;
  erstellt_von      : uname;
}
```

#### ZPA_FINDING_TYPE – Katalog der Anti-Pattern (Customizing)

```abap
@EndUserText.label : 'PA: Finding-Typen Katalog'
define table zpa_finding_type {
  key finding_type  : zpa_finding_type;
  beschreibung      : zpa_beschreibung;
  kategorie         : zpa_kategorie;
  basis_score       : zpa_score;           " Basis-Bewertung 0-100
  aktiv             : zpa_boolean;
  dokumentation     : string;              " Detailbeschreibung / Hilfstext
  massnahme_vorlage : string;              " Textbaustein Maßnahme
}
```

#### ZPA_HISTORY – Historische Auswertungen (für Trending)

```abap
@EndUserText.label : 'PA: Historische Aggregationen'
define table zpa_history {
  key hist_id       : zpa_hist_id;
  key erfasst_am    : dats;
  modul             : zpa_modul;
  programm          : progname;
  finding_type      : zpa_finding_type;
  anzahl_findings   : zpa_anzahl;
  avg_score         : zpa_score;
  max_laufzeit_us   : zpa_laufzeit_us;
  gesamt_laufzeit   : zpa_laufzeit_us;
}
```

### 3.2 Domänen und Typen

```abap
" Domänen (Auswahl)
DOMAIN zpa_prioritaet   CHAR 10  " KRITISCH | HOCH | MITTEL | NIEDRIG | HINWEIS
DOMAIN zpa_kategorie    CHAR 20  " DB_ACCESS | ABAP_LOGIK | CDS_ODATA | RFC_BAPI |
                                 " CUSTOM_CODE | STD_EXIT | ARCHITEKTUR
DOMAIN zpa_finding_type CHAR 30  " SELECT_LOOP | FULL_SCAN | NO_WHERE |
                                 " EXPENSIVE_JOIN | HIGH_RUNTIME | etc.
DOMAIN zpa_trace_source CHAR 10  " ST05 | ST12 | MANUAL | API
DOMAIN zpa_opt_hebel    CHAR 10  " HOCH | MITTEL | NIEDRIG
DOMAIN zpa_score        INT1     " 0-100
DOMAIN zpa_laufzeit_us  INT8     " Laufzeit in Mikrosekunden
```

---

## 4. Auswertungslogik & Performance-Indikatoren

### 4.1 Anti-Pattern-Katalog

#### AP-01: SELECT in Schleife (LOOP-SELECT)

```
Erkennungskriterium:
  - Gleiches SQL-Statement (Hash) mit Anzahl_exec > Schwellwert (Default: 5)
  - Oder: call_depth zeigt LOOP-Kontext im ABAP-Trace (ST12)
  - Oder: identisches Statement mit variierenden WHERE-Einzelwerten

Score-Formel:
  base_score = 80
  modifier   = MIN( anzahl_exec / 10, 2.0 )   " max. Faktor 2
  final_score = MIN( base_score * modifier, 100 )

Empfehlung:
  "SELECT ... FOR ALL ENTRIES oder JOIN verwenden.
   Bei CDS-Views: Zugriff via Assoziation oder JOIN-View."
```

#### AP-02: Full Table Scan (FULL_SCAN)

```
Erkennungskriterium:
  - records_fetched > Schwellwert (Default: 10.000)
  - UND (has_where = false ODER index_used = false)
  - UND records_selected / records_fetched < 0.1 (Selektivität < 10%)

Score-Formel:
  base_score = 70
  size_factor = LOG10( records_fetched / 1000 ) * 10
  final_score = MIN( base_score + size_factor, 100 )

Empfehlung:
  "WHERE-Bedingung prüfen und Index anlegen bzw. bestehenden Index nutzen.
   Mandantenfeld und führende Felder des gewünschten Index in WHERE aufnehmen."
```

#### AP-03: Kein WHERE / Fehlende Einschränkung (NO_WHERE)

```
Erkennungskriterium:
  - has_where = false
  - stmt_type IN ( 'SELECT', 'OPEN CURSOR' )
  - records_fetched > 100

Score: 85 (fix, weil strukturelles Problem)

Empfehlung:
  "SELECT ohne WHERE ist ein Architekturproblem.
   Prüfen ob MANDT-Einschränkung fehlt oder intentionales Full-Read vorliegt."
```

#### AP-04: Hohe Laufzeit Einzelstatement (HIGH_RUNTIME)

```
Schwellwerte (konfigurierbar in ZPA_FINDING_TYPE):
  KRITISCH  : laufzeit_us > 10.000.000  (10 Sekunden)
  HOCH      : laufzeit_us >  2.000.000  (2 Sekunden)
  MITTEL    : laufzeit_us >    500.000  (0,5 Sekunden)
  NIEDRIG   : laufzeit_us >    100.000  (0,1 Sekunden)

Score-Formel:
  score = MIN( LOG10( laufzeit_us / 1000 ) * 25, 100 )
```

#### AP-05: Teurer JOIN (EXPENSIVE_JOIN)

```
Erkennungskriterium:
  - sql_text enthält JOIN-Schlüsselwort
  - laufzeit_us > Schwellwert (Default: 500.000 µs)
  - records_fetched > 1.000

Zusatz-Indikator:
  - Mehr als 4 JOINs im Statement → +10 Score
  - Kein Index auf JOIN-Feld erkennbar → +15 Score
```

#### AP-06: CDS-View mit hoher Laufzeit (CDS_EXPENSIVE)

```
Erkennungskriterium:
  - tabname LIKE 'I_%' ODER tabname LIKE 'C_%' ODER enthält '_CDS'
    (SAP-Standard CDS-Naming-Konvention)
  - ODER: tabname entspricht bekanntem CDS-View (via DD02L.TABCLASS = 'VIEW')
  - laufzeit_us > 1.000.000 µs

Empfehlung:
  "CDS-View auf Komplexität prüfen: Unnötige Assoziationen, fehlende
   @ObjectModel.filter.transformedBy oder fehlende Parameter."
```

#### AP-07: Niedriges Selektivitätsverhältnis (LOW_SELECTIVITY)

```
Erkennungskriterium:
  - records_selected / records_fetched < 0.05  (weniger als 5% genutzt)
  - records_fetched > 500
  - NOT buffer_hit

Score: 60 + MIN( (1 - selectivity) * 40, 40 )

Empfehlung:
  "Datenbankfilterung verbessern. Aufwändige ABAP-Filterung nach DB-Zugriff
   durch präzisere WHERE-Bedingung ersetzen."
```

#### AP-08: Identische SELECTs (DUPLICATE_SELECT)

```
Erkennungskriterium:
  - sql_hash tritt mehr als Schwellwert (Default: 3) mal auf
  - Gleiche WHERE-Parameter (Parametervergleich)

Empfehlung:
  "Ergebnis puffern (interne Tabelle, Klassen-Attribut, EXPORT TO MEMORY).
   Bei häufigem systemweiten Zugriff: SAP-Puffer (SPOOL, CL_ABAP_BUFFER) prüfen."
```

#### AP-09: OData / Gateway hohe Laufzeit (ODATA_HIGH_RUNTIME)

```
Erkennungskriterium:
  - program_name ENTHÄLT '/IWFND/' ODER '/IWBEP/' ODER 'CL_SADL'
  - laufzeit_us > 2.000.000 µs

Empfehlung:
  "OData-Request in Einzelkomponenten aufteilen:
   $expand-Tiefe reduzieren, serverseitiges Paging aktivieren,
   $select statt * verwenden."
```

#### AP-10: RFC / BAPI hohe Laufzeit (RFC_HIGH_RUNTIME)

```
Erkennungskriterium:
  - stmt_type = 'RFC' ODER program_name enthält RFC-Funktionsgruppe
  - laufzeit_us > 1.000.000 µs

Empfehlung:
  "RFC-Aufruf auf Parallelisierung oder Bündelung prüfen.
   Bei BAPI: Batch-Input oder Inbound-IDoc als Alternative bewerten."
```

#### AP-11: DB-Zeit vs. ABAP-Zeit Ungleichgewicht (TIME_SPLIT_ANOMALY)

```
Erkennungskriterium (auf Session-Ebene):
  db_ratio    = db_laufzeit / gesamt_laufzeit
  abap_ratio  = abap_laufzeit / gesamt_laufzeit

  Muster A: db_ratio > 0.85  → "DB-lastig: SQL-Optimierung priorisieren"
  Muster B: abap_ratio > 0.80 → "ABAP-lastig: Algorithmus/Logik optimieren"
  Muster C: db_ratio < 0.10 AND abap_ratio < 0.10 → "Wartezeiten prüfen (Locks, RFC)"

Score: 40 (Indikator, kein hartes Problem)
```

#### AP-12: Tabellenzugriff auf Cluster-/Pool-Tabellen (CLUSTER_ACCESS)

```
Erkennungskriterium:
  - tabname IN ( Tabellen aus DD02L mit TABCLASS = 'CLUSTER' oder 'POOL' )
  - Bekannte Cluster: BSEG, PCL1, PCL2, STXL, INDX, EDI40

Empfehlung:
  "Cluster-Tabellen sind in S/4HANA weitgehend aufgelöst. Wenn noch vorhanden,
   Zugriff über Aggregations-CDS oder Migration auf transparente Tabelle prüfen."
```

### 4.2 Erkennungsalgorithmus – Flussdiagramm

```
ST05-Daten importiert
        │
        ▼
┌──────────────────┐
│ Deduplizierung   │  sql_hash berechnen, gleiche Statements zusammenfassen
│ & Normalisierung │  Programmnamen normalisieren (Z* / Y* markieren)
└────────┬─────────┘
         │
         ▼
┌──────────────────────────────────────────┐
│         Pattern-Detektoren               │
│  (alle parallel ausführbar)              │
│                                          │
│  AP-01: Loop-Detector                    │
│  AP-02: FullScan-Detector                │
│  AP-03: NoWhere-Detector                 │
│  AP-04: HighRuntime-Detector             │
│  AP-05: ExpensiveJoin-Detector           │
│  AP-06: CDS-Detector                     │
│  AP-07: Selectivity-Detector             │
│  AP-08: Duplicate-Detector               │
│  AP-09: OData-Detector                   │
│  AP-10: RFC-Detector                     │
│  AP-11: TimeSplit-Detector               │
│  AP-12: Cluster-Detector                 │
└────────┬─────────────────────────────────┘
         │
         ▼
┌──────────────────┐
│   Scorer         │  Score berechnen, Priorität ableiten
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│   Recommender    │  Maßnahmen-Text generieren, Optimierungshebel bestimmen
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│   Persistenz     │  ZPA_FINDING befüllen
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│   Ausgabe        │  ALV / OData / Excel
└──────────────────┘
```

---

## 5. Scoring- und Klassifikationsmodell

### 5.1 Prioritätsklassen

| Priorität | Score-Bereich | Bedeutung | Handlungsbedarf |
|---|---|---|---|
| **KRITISCH** | 90–100 | Systemstabilität gefährdet, massive Laufzeit | Sofort (< 1 Woche) |
| **HOCH** | 70–89 | Signifikante Performance-Einbuße, Nutzer betroffen | Kurzfristig (< 1 Monat) |
| **MITTEL** | 50–69 | Spürbare Verlangsamung, strukturelles Problem | Mittelfristig (< Quartal) |
| **NIEDRIG** | 20–49 | Optimierungspotenzial vorhanden | Nächste Entwicklungswelle |
| **HINWEIS** | 1–19 | Best-Practice-Abweichung, kein akuter Bedarf | Backlog |

### 5.2 Kategorien

| Kategorie | Beschreibung | Typische Patterns |
|---|---|---|
| **DB_ACCESS** | Datenbankzugriffsprobleme | Full Scan, kein WHERE, teurer JOIN |
| **ABAP_LOGIK** | ABAP-seitige Ineffizienz | SELECT in Loop, Duplikate, schlechte Selektivität |
| **CDS_ODATA** | CDS-Views und OData-Services | Teure CDS, OData ohne Paging |
| **RFC_BAPI** | Schnittstellen und Remote-Calls | Lange RFC-Laufzeiten, kein Batching |
| **CUSTOM_CODE** | Kundeneigene Entwicklungen (Z*/Y*) | Alle obigen in eigenem Code |
| **STD_EXIT** | SAP-Standard-Erweiterungspunkte | BAdI, User-Exit mit Performance-Problem |
| **ARCHITEKTUR** | Strukturelles Problem | Cluster-Zugriff, grundsätzlich falscher Ansatz |

### 5.3 Score-Gewichtungsmodell

```
Gesamt-Score einer Fundstelle:

  S_final = w1 * S_runtime    (Laufzeit-Score)
           + w2 * S_frequency  (Häufigkeits-Score)
           + w3 * S_datavolume (Datenmenge-Score)
           + w4 * S_pattern    (Pattern-Score)
           + w5 * S_custom     (Custom-Code-Bonus)

Standardgewichte:
  w1 = 0.35  (Laufzeit ist primäres Kriterium)
  w2 = 0.25  (Häufigkeit: wiederholte Probleme wiegen schwerer)
  w3 = 0.20  (Datenmenge: Ressourcenverbrauch)
  w4 = 0.15  (Pattern-Typ: strukturelle Schwere)
  w5 = 0.05  (Custom Code: leichter zu ändern, daher leichter priorisierbar)

Konfiguration: Gewichte in Tabelle ZPA_SCORE_CONFIG speicherbar
```

### 5.4 Optimierungshebel-Einschätzung

```
Optimierungshebel = erwartete Laufzeitreduktion nach Maßnahme

HOCH   : > 80% Reduktion erwartet
         Beispiel: SELECT in Loop → FOR ALL ENTRIES: Faktor 10-100x
         
MITTEL : 30–80% Reduktion erwartet
         Beispiel: Index ergänzen: Faktor 2-5x
         
NIEDRIG: < 30% Reduktion erwartet
         Beispiel: Puffer-Optimierung: Faktor 1.1-1.5x
```

---

## 6. UI- und Ausgabekonzept

### 6.1 ABAP-Report ALV – Selektionsbild

```
┌──────────────────────────────────────────────────────────────┐
│  Z_PERF_ANALYSER – Performance Trace Analyse                 │
├──────────────────────────────────────────────────────────────┤
│  Modus:     ○ Import neu   ● Vorhandene Analyse              │
│                                                              │
│  Import-Quelle:                                              │
│    ST05-Datei:  [____________________________] [Browse]      │
│    ST12-Datei:  [____________________________] [Browse]      │
│    Session-ID:  [__________________]                         │
│                                                              │
│  Filter:                                                     │
│    Priorität:   [KRITISCH] [HOCH  ] [____  ] [____  ]       │
│    Kategorie:   [DB_ACCESS] [ABAP_LOGIK] [CDS_ODATA] ...    │
│    Modul:       [____________________]                       │
│    Programm:    [____________________]                       │
│    Von Datum:   [________]  Bis: [________]                  │
│                                                              │
│  Ausgabe:       ○ ALV  ○ Excel  ○ Zusammenfassung            │
│                                                              │
│  [F8 Ausführen]                                              │
└──────────────────────────────────────────────────────────────┘
```

### 6.2 ALV-Ausgabe – Management-Summary (Kopf)

```
┌──────────────────────────────────────────────────────────────────────────┐
│ PERFORMANCE ANALYSE ZUSAMMENFASSUNG                                      │
│ Session: MM-Beleg-Buchung-Test | Datum: 09.06.2026 | System: S4H_PRD    │
├─────────────┬──────────────┬───────────────┬────────────────────────────┤
│ KRITISCH: 3 │  HOCH: 12   │  MITTEL: 28   │  NIEDRIG: 15   HINWEIS: 7  │
├─────────────┴──────────────┴───────────────┴────────────────────────────┤
│ Gesamtlaufzeit: 45,3 Sek  │ DB-Zeit: 38,1 Sek (84%)  │ ABAP: 6,2 Sek  │
│ Top-Tabellen: BKPF, BSEG, EKPO │ Top-Programme: ZRFBU100, MRM_MIRO     │
│ Custom-Code-Anteil: 67%   │ Optimierungshebel gesamt: HOCH              │
└─────────────────────────────────────────────────────────────────────────┘
```

### 6.3 ALV-Ausgabe – Detailtabelle

```
Spalten (konfigurierbar, Breite automatisch):

| Prio     | Score | Kategorie   | Programm          | Tabelle    | Laufzeit  | Exec | Datensätze | Typ         | Custom | Maßnahme (Kurzform)           |
|----------|-------|-------------|-------------------|------------|-----------|------|------------|-------------|--------|-------------------------------|
| KRITISCH |  97   | DB_ACCESS   | ZRFBU100          | BSEG       | 28,4 Sek  | 1    | 2.450.000  | FULL_SCAN   | Ja     | WHERE-Bed. + Index ergänzen   |
| KRITISCH |  94   | ABAP_LOGIK  | ZRFBU100          | BKPF       | 12,1 Sek  | 847  | 847        | SELECT_LOOP | Ja     | FOR ALL ENTRIES verwenden     |
| HOCH     |  82   | CDS_ODATA   | /IWFND/CL_MGW_ABS | I_JournalEntry | 4,2 Sek | 1  | 180.000    | CDS_EXP     | Nein   | $select/$top/$skip aktivieren |
...
```

### 6.4 Fiori-App Konzept (Phase 2)

```
Startseite – KPI-Kacheln:
  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
  │ KRITISCH  3 │  │ HOCH     12 │  │ Sessions  8 │  │ Top-Hebel   │
  │ ▲ +1 vs.   │  │ ▼ -3 vs.   │  │ letzte 30T  │  │ HOCH: 4     │
  │   Vorwoche │  │   Vorwoche  │  │             │  │             │
  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘

Hauptliste:
  - Fiori List Report mit allen Findings
  - Filter: Priorität, Kategorie, Modul, Zeitraum, Custom/Standard
  - Sortierung nach Score DESC

Detailseite (Object Page):
  - Alle Finding-Felder
  - Call-Hierarchie als Tree-Darstellung
  - SQL-Statement mit Syntax-Highlighting
  - Trend-Chart: Score dieser Fundstelle über Zeit
  - Maßnahmen-Checkliste (umsetzbar als Aufgabe markieren)
```

### 6.5 Management-Report (Excel/PDF-Export)

```
Seite 1: Executive Summary
  - Top 5 kritische Findings mit Kurzbeschreibung
  - Ampelgrafik je Modul
  - Geschätztes Einsparpotenzial (Laufzeiteinsparung in Sekunden/Stunden)

Seite 2: Findings nach Programm/Modul aggregiert
Seite 3: Findings-Detail-Liste (vollständig)
Seite 4: Trend-Vergleich mit Vorperiode (falls Historiedaten vorhanden)
```

---

## 7. Erweiterbarkeit

### 7.1 Erweiterungspunkte

#### BAdI: ZPA_BADI_CUSTOM_DETECTOR

```abap
INTERFACE ZIF_PA_CUSTOM_DETECTOR.
  METHODS detect
    IMPORTING
      it_trace_items TYPE zpa_tt_trace_item
    CHANGING
      ct_findings    TYPE zpa_tt_finding.
ENDINTERFACE.
```

Ermöglicht: Eigene Anti-Pattern ohne Core-Modifikation hinzufügen.

#### Erweiterungstabelle: ZPA_FINDING_TYPE

Neue Pattern-Typen können jederzeit in der Customizing-Tabelle angelegt werden, ohne Code-Änderung.

#### Score-Gewichte: ZPA_SCORE_CONFIG

Schwellwerte und Gewichte per Mandant und Systemtyp konfigurierbar.

### 7.2 Geplante Erweiterungen

| Erweiterung | Phase | Aufwand | Nutzen |
|---|---|---|---|
| ST12-ABAP-Trace Integration | Phase 1 | M | Call-Hierarchie wird vollständig |
| Automatischer ST05-Export-Trigger | Phase 2 | M | Kein manueller Export mehr nötig |
| Historien-Trending (n Perioden) | Phase 2 | S | Fortschritt nach Optimierungen messbar |
| BTP-Integration / SAP Analytics Cloud | Phase 3 | L | Systemübergreifendes Dashboard |
| KI-gestützte Maßnahmen-Empfehlung | Phase 3 | L | Automatische Code-Vorschläge |
| Integration mit ATC (ABAP Test Cockpit) | Phase 2 | M | Performance-Checks in CI/CD |
| HANA Plan Visualizer Integration | Phase 2 | L | SQL-Execution-Plan direkt in Findings |

---

## 8. Konkrete technische Umsetzung

### 8.1 Hauptinterfaces

```abap
"--------------------------------------------------------------------
" ZIF_PA_PARSER – Interface für alle Trace-Parser
"--------------------------------------------------------------------
INTERFACE zif_pa_parser.
  TYPES:
    tt_trace_item TYPE STANDARD TABLE OF zpa_trace_item
                  WITH DEFAULT KEY.

  METHODS parse
    IMPORTING
      iv_raw_data    TYPE xstring        " Binärinhalt der Datei
      iv_session_id  TYPE zpa_session_id
    RETURNING
      VALUE(rt_items) TYPE tt_trace_item
    RAISING
      zcx_pa_parse_error.

  METHODS get_session_header
    RETURNING
      VALUE(rs_header) TYPE zpa_trace_session.
ENDINTERFACE.

"--------------------------------------------------------------------
" ZIF_PA_DETECTOR – Interface für Pattern-Detektoren
"--------------------------------------------------------------------
INTERFACE zif_pa_detector.
  TYPES:
    tt_trace_item TYPE STANDARD TABLE OF zpa_trace_item
                  WITH DEFAULT KEY,
    tt_finding    TYPE STANDARD TABLE OF zpa_finding
                  WITH DEFAULT KEY.

  METHODS detect
    IMPORTING
      it_items       TYPE tt_trace_item
      is_session     TYPE zpa_trace_session
    RETURNING
      VALUE(rt_findings) TYPE tt_finding.

  METHODS get_pattern_id
    RETURNING
      VALUE(rv_type) TYPE zpa_finding_type.
ENDINTERFACE.

"--------------------------------------------------------------------
" ZIF_PA_SCORER – Interface für Scoring
"--------------------------------------------------------------------
INTERFACE zif_pa_scorer.
  METHODS score
    CHANGING
      cs_finding TYPE zpa_finding.

  METHODS get_priority
    IMPORTING
      iv_score        TYPE zpa_score
    RETURNING
      VALUE(rv_prio)  TYPE zpa_prioritaet.
ENDINTERFACE.
```

### 8.2 Hauptklassen

```abap
"--------------------------------------------------------------------
" ZCL_PA_IMPORTER – Orchestrierung Import
"--------------------------------------------------------------------
CLASS zcl_pa_importer DEFINITION
  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS import_from_file
      IMPORTING
        iv_file_path   TYPE string
        iv_trace_source TYPE zpa_trace_source
        is_session_meta TYPE zpa_trace_session
      RETURNING
        VALUE(rv_session_id) TYPE zpa_session_id
      RAISING
        zcx_pa_import_error.

    METHODS import_from_xstring
      IMPORTING
        iv_data         TYPE xstring
        iv_trace_source TYPE zpa_trace_source
        is_session_meta TYPE zpa_trace_session
      RETURNING
        VALUE(rv_session_id) TYPE zpa_session_id
      RAISING
        zcx_pa_import_error.

  PRIVATE SECTION.
    METHODS get_parser
      IMPORTING
        iv_source TYPE zpa_trace_source
      RETURNING
        VALUE(ro_parser) TYPE REF TO zif_pa_parser.

    METHODS persist_session
      IMPORTING
        is_session TYPE zpa_trace_session
        it_items   TYPE zif_pa_parser=>tt_trace_item.
ENDCLASS.

"--------------------------------------------------------------------
" ZCL_PA_ANALYSER – Orchestrierung Analyse
"--------------------------------------------------------------------
CLASS zcl_pa_analyser DEFINITION
  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS analyse_session
      IMPORTING
        iv_session_id    TYPE zpa_session_id
      RETURNING
        VALUE(rt_findings) TYPE zpa_tt_finding
      RAISING
        zcx_pa_analyse_error.

    METHODS analyse_and_persist
      IMPORTING
        iv_session_id TYPE zpa_session_id
      RAISING
        zcx_pa_analyse_error.

  PRIVATE SECTION.
    DATA mt_detectors TYPE STANDARD TABLE OF REF TO zif_pa_detector.
    DATA mo_scorer    TYPE REF TO zif_pa_scorer.

    METHODS load_detectors.
    METHODS load_trace_items
      IMPORTING
        iv_session_id TYPE zpa_session_id
      RETURNING
        VALUE(rt_items) TYPE zif_pa_parser=>tt_trace_item.
ENDCLASS.

"--------------------------------------------------------------------
" ZCL_PA_ANAL_SQL – SQL Pattern Detector (Basisklasse)
"--------------------------------------------------------------------
CLASS zcl_pa_anal_sql DEFINITION
  PUBLIC ABSTRACT CREATE PUBLIC
  INTERFACES zif_pa_detector.

  PROTECTED SECTION.
    METHODS is_custom_code
      IMPORTING
        iv_program     TYPE progname
      RETURNING
        VALUE(rv_flag) TYPE zpa_boolean.

    METHODS calc_sql_hash
      IMPORTING
        iv_sql         TYPE string
      RETURNING
        VALUE(rv_hash) TYPE zpa_sql_hash.

    METHODS build_call_hierarchy_json
      IMPORTING
        it_items       TYPE zif_pa_parser=>tt_trace_item
        iv_item_seq    TYPE zpa_item_seq
      RETURNING
        VALUE(rv_json) TYPE string.
ENDCLASS.

"--------------------------------------------------------------------
" ZCL_PA_ANAL_LOOP – SELECT in Loop Detector
"--------------------------------------------------------------------
CLASS zcl_pa_anal_loop DEFINITION
  PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_pa_anal_sql.

  PUBLIC SECTION.
    METHODS zif_pa_detector~detect REDEFINITION.
    METHODS zif_pa_detector~get_pattern_id REDEFINITION.

  PRIVATE SECTION.
    CONSTANTS:
      c_min_executions TYPE i VALUE 5,
      c_pattern_id     TYPE zpa_finding_type VALUE 'SELECT_LOOP'.

    METHODS group_by_sql_hash
      IMPORTING
        it_items    TYPE zif_pa_parser=>tt_trace_item
      RETURNING
        VALUE(rt_grouped) TYPE zpa_tt_sql_group.
ENDCLASS.

"--------------------------------------------------------------------
" ZCL_PA_SCORER – Standard-Scorer
"--------------------------------------------------------------------
CLASS zcl_pa_scorer DEFINITION
  PUBLIC FINAL CREATE PUBLIC
  INTERFACES zif_pa_scorer.

  PUBLIC SECTION.
    METHODS constructor.

  PRIVATE SECTION.
    DATA ms_weights TYPE zpa_score_weights.

    METHODS load_weights.
    METHODS calc_runtime_score
      IMPORTING iv_runtime    TYPE zpa_laufzeit_us
      RETURNING VALUE(rv_score) TYPE zpa_score.
    METHODS calc_frequency_score
      IMPORTING iv_exec_count TYPE zpa_anzahl
      RETURNING VALUE(rv_score) TYPE zpa_score.
    METHODS calc_datavolume_score
      IMPORTING iv_records    TYPE zpa_anzahl
      RETURNING VALUE(rv_score) TYPE zpa_score.
ENDCLASS.
```

### 8.3 Parser-Implementierung (ST05 XML)

```abap
"--------------------------------------------------------------------
" ZCL_PA_PARSER_ST05_XML
"--------------------------------------------------------------------
CLASS zcl_pa_parser_st05_xml DEFINITION
  PUBLIC FINAL CREATE PUBLIC
  INTERFACES zif_pa_parser.

  PUBLIC SECTION.
    METHODS zif_pa_parser~parse         REDEFINITION.
    METHODS zif_pa_parser~get_session_header REDEFINITION.

  PRIVATE SECTION.
    DATA ms_session TYPE zpa_trace_session.

    " ST05-XML hat folgende Struktur (vereinfacht):
    " <PERFTRACERESULT>
    "   <HEADER>...</HEADER>
    "   <RECORDS>
    "     <RECORD>
    "       <STMT_TYPE>SELECT</STMT_TYPE>
    "       <TABNAME>BKPF</TABNAME>
    "       <DURATION>125430</DURATION>  <!-- µs -->
    "       <RECORDS>1250</RECORDS>
    "       <PROGRAM>ZRFBU100</PROGRAM>
    "       <INCLUDE>ZRFBU100_F01</INCLUDE>
    "       <LINE>450</LINE>
    "       <SQLSTATEMENT>SELECT * FROM BKPF ...</SQLSTATEMENT>
    "     </RECORD>
    "   </RECORDS>
    " </PERFTRACERESULT>

    METHODS parse_header
      IMPORTING io_node TYPE REF TO if_ixml_node.
    METHODS parse_record
      IMPORTING
        io_node        TYPE REF TO if_ixml_node
        iv_seq         TYPE zpa_item_seq
        iv_session_id  TYPE zpa_session_id
      RETURNING
        VALUE(rs_item) TYPE zpa_trace_item.
    METHODS extract_where_info
      IMPORTING
        iv_sql         TYPE string
      EXPORTING
        ev_has_where   TYPE zpa_boolean
        ev_where_flds  TYPE string.
ENDCLASS.

CLASS zcl_pa_parser_st05_xml IMPLEMENTATION.
  METHOD zif_pa_parser~parse.
    DATA lo_ixml      TYPE REF TO if_ixml.
    DATA lo_document  TYPE REF TO if_ixml_document.
    DATA lo_parser    TYPE REF TO if_ixml_parser.
    DATA lo_records   TYPE REF TO if_ixml_node_list.
    DATA lo_record    TYPE REF TO if_ixml_node.
    DATA lv_seq       TYPE zpa_item_seq VALUE 1.

    lo_ixml     = cl_ixml=>create( ).
    lo_document = lo_ixml->create_document( ).
    lo_parser   = lo_ixml->create_parser(
                    istream   = cl_ixml_string_istream=>create( iv_raw_data )
                    document  = lo_document ).

    IF lo_parser->parse( ) <> 0.
      RAISE EXCEPTION TYPE zcx_pa_parse_error
        EXPORTING
          textid  = zcx_pa_parse_error=>invalid_xml
          mv_info = 'ST05 XML Parse-Fehler'.
    ENDIF.

    " Header lesen
    parse_header( lo_document->find_from_name( 'HEADER' ) ).
    ms_session-session_id = iv_session_id.

    " Records iterieren
    lo_records = lo_document->get_elements_by_tag_name( 'RECORD' ).
    DATA lv_i TYPE i.
    WHILE lv_i < lo_records->get_length( ).
      lo_record = lo_records->get_item( lv_i ).
      APPEND parse_record(
        io_node       = lo_record
        iv_seq        = lv_seq
        iv_session_id = iv_session_id ) TO rt_items.
      lv_seq += 1.
      lv_i   += 1.
    ENDWHILE.
  ENDMETHOD.
ENDCLASS.
```

### 8.4 Hauptreport ZRPA_PERF_ANALYSE

```abap
"--------------------------------------------------------------------
" ZRPA_PERF_ANALYSE – Selektionsbild und Steuerung
"--------------------------------------------------------------------
REPORT zrpa_perf_analyse.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  PARAMETERS:
    p_mode   TYPE c LENGTH 1 DEFAULT 'N'    " N=Neu, A=Analyse vorhanden
             AS LISTBOX VISIBLE LENGTH 25,
    p_sessid TYPE zpa_session_id,           " Vorhandene Session
    p_name   TYPE zpa_session_name,         " Name für neue Session
    p_modul  TYPE zpa_modul,               " Modul-Zuordnung
    p_env    TYPE zpa_umgebung DEFAULT 'PRD'.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-002.
  PARAMETERS:
    p_st05   TYPE localfile,               " ST05-Exportdatei
    p_st12   TYPE localfile.               " ST12-Exportdatei (optional)
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE TEXT-003.
  PARAMETERS:
    p_out    TYPE c LENGTH 1 DEFAULT 'A'   " A=ALV, E=Excel, S=Summary
             AS LISTBOX VISIBLE LENGTH 20.
  SELECT-OPTIONS:
    so_prio  FOR zpa_finding-prioritaet,
    so_kat   FOR zpa_finding-kategorie.
SELECTION-SCREEN END OF BLOCK b3.

START-OF-SELECTION.
  DATA lo_controller TYPE REF TO zcl_pa_main_controller.
  lo_controller = NEW zcl_pa_main_controller( ).

  CASE p_mode.
    WHEN 'N'.  " Neuer Import + Analyse
      lo_controller->import_and_analyse(
        iv_st05_file   = p_st05
        iv_st12_file   = p_st12
        is_session_meta = VALUE #(
          session_name = p_name
          modul        = p_modul
          umgebung     = p_env ) ).

    WHEN 'A'.  " Vorhandene Session erneut auswerten
      lo_controller->analyse_existing(
        iv_session_id = p_sessid ).
  ENDCASE.

  lo_controller->display(
    iv_output_type = p_out
    it_prio_range  = so_prio[]
    it_kat_range   = so_kat[] ).
```

### 8.5 ALV-Ausgabeklasse (Kernstruktur)

```abap
CLASS zcl_pa_output_alv DEFINITION
  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS display_findings
      IMPORTING
        it_findings    TYPE zpa_tt_finding
        is_session     TYPE zpa_trace_session.

  PRIVATE SECTION.
    DATA mo_alv       TYPE REF TO cl_gui_alv_grid.
    DATA mo_container TYPE REF TO cl_gui_custom_container.

    METHODS build_fieldcat
      RETURNING VALUE(rt_fcat) TYPE lvc_t_fcat.
    METHODS build_layout
      RETURNING VALUE(rs_layout) TYPE lvc_s_layo.
    METHODS build_sort
      RETURNING VALUE(rt_sort) TYPE lvc_t_sort.
    METHODS set_colors
      CHANGING ct_findings TYPE zpa_tt_finding.
    METHODS display_summary_header
      IMPORTING is_session TYPE zpa_trace_session
                it_findings TYPE zpa_tt_finding.

    METHODS on_double_click
        FOR EVENT double_click OF cl_gui_alv_grid
        IMPORTING e_row e_column.
ENDCLASS.

CLASS zcl_pa_output_alv IMPLEMENTATION.
  METHOD set_colors.
    " Zeilen farblich markieren je nach Priorität
    LOOP AT ct_findings ASSIGNING FIELD-SYMBOL(<fs>).
      <fs>-color = SWITCH #( <fs>-prioritaet
        WHEN 'KRITISCH' THEN 'C610'  " Rot
        WHEN 'HOCH'     THEN 'C510'  " Orange
        WHEN 'MITTEL'   THEN 'C410'  " Gelb
        WHEN 'NIEDRIG'  THEN 'C310'  " Grün (hell)
        WHEN 'HINWEIS'  THEN 'C110'  " Grau
        ELSE                 'C010' ).
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.
```

### 8.6 RAP-Entitäten (Phase 2 – OData/Fiori)

```abap
"--------------------------------------------------------------------
" ZI_PA_FINDING – CDS Interface View
"--------------------------------------------------------------------
@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'PA: Findings Interface View'
@Metadata.ignorePropagatedAnnotations: true

define view entity ZI_PA_FINDING
  as select from zpa_finding

  association [0..1] to ZI_PA_TRACE_SESSION as _Session
    on $projection.SessionId = _Session.SessionId

{
  key finding_id         as FindingId,
      session_id         as SessionId,
      finding_type       as FindingType,
      kategorie          as Kategorie,
      prioritaet         as Prioritaet,
      score              as Score,
      programm           as Programm,
      include_name       as IncludeName,
      klasse             as Klasse,
      methode            as Methode,
      zeile              as Zeile,
      tabname            as Tabname,
      sql_kurzform       as SqlKurzform,
      laufzeit_us        as LaufzeitUs,
      anzahl_exec        as AnzahlExec,
      datenmenge         as Datenmenge,
      technische_ursache as TechnischeUrsache,
      fachliche_einsch   as FachlicheEinsch,
      empf_massnahme     as EmpfMassnahme,
      optim_hebel        as OptimHebel,
      is_custom_code     as IsCustomCode,
      erstellt_am        as ErstelltAm,

      /* Calculated Fields */
      case prioritaet
        when 'KRITISCH' then 1
        when 'HOCH'     then 2
        when 'MITTEL'   then 3
        when 'NIEDRIG'  then 4
        else                 5
      end                as PrioritaetSort,

      laufzeit_us / 1000000 as LaufzeitSek,   " Sekunden für Anzeige

      _Session
}

"--------------------------------------------------------------------
" ZC_PA_FINDING – CDS Consumption View (RAP)
"--------------------------------------------------------------------
@EndUserText.label: 'PA: Findings Consumption View'
@AccessControl.authorizationCheck: #CHECK
@Metadata.allowExtensions: true

@UI.headerInfo: {
  typeName: 'Finding',
  typeNamePlural: 'Findings',
  title: { type: #STANDARD, value: 'FindingType' },
  description: { type: #STANDARD, value: 'Prioritaet' }
}

define view entity ZC_PA_FINDING
  as projection on ZI_PA_FINDING
{
      @UI.facet: [{ id: 'Finding', purpose: #STANDARD,
                    type: #IDENTIFICATION_REFERENCE, label: 'Details', position: 10 }]
  key FindingId,
      @UI.selectionField: [{ position: 10 }]
      @UI.lineItem:       [{ position: 10, label: 'Priorität' }]
      Prioritaet,
      @UI.selectionField: [{ position: 20 }]
      @UI.lineItem:       [{ position: 20, label: 'Score' }]
      Score,
      @UI.lineItem:       [{ position: 30, label: 'Kategorie' }]
      Kategorie,
      @UI.selectionField: [{ position: 30 }]
      @UI.lineItem:       [{ position: 40, label: 'Programm' }]
      Programm,
      @UI.lineItem:       [{ position: 50, label: 'Tabelle/CDS' }]
      Tabname,
      @UI.lineItem:       [{ position: 60, label: 'Laufzeit (Sek)' }]
      LaufzeitSek,
      @UI.lineItem:       [{ position: 70, label: 'Ausführungen' }]
      AnzahlExec,
      @UI.lineItem:       [{ position: 80, label: 'Custom Code' }]
      IsCustomCode,
      @UI.lineItem:       [{ position: 90, label: 'Maßnahme' }]
      EmpfMassnahme,
      PrioritaetSort,
      SessionId,
      _Session
}
```

### 8.7 Behavior Definition (RAP – Read-Only zunächst)

```abap
managed implementation in class zbp_c_pa_finding unique;
strict ( 2 );

define behavior for ZC_PA_FINDING
{
  use etag master ErstelltAm;

  draft table zpa_finding_draft;

  field ( readonly ) FindingId, ErstelltAm, Score, PrioritaetSort;

  action ( features : instance ) markAsResolved result [1] $self;
  action ( features : instance ) updatePriority parameter ZA_PA_UPDATE_PRIO
                                                result [1] $self;

  mapping for zpa_finding corresponding
  {
    FindingId        = finding_id;
    SessionId        = session_id;
    FindingType      = finding_type;
    Prioritaet       = prioritaet;
    Score            = score;
    EmpfMassnahme    = empf_massnahme;
  }
}
```

### 8.8 Ausnahme-Klassen

```abap
CLASS zcx_pa_parse_error DEFINITION
  PUBLIC INHERITING FROM cx_static_check FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CONSTANTS:
      invalid_xml   TYPE sotr_conc VALUE '...',
      unknown_format TYPE sotr_conc VALUE '...'.
    DATA mv_info TYPE string.
ENDCLASS.

CLASS zcx_pa_import_error DEFINITION
  PUBLIC INHERITING FROM cx_static_check FINAL CREATE PUBLIC.
ENDCLASS.

CLASS zcx_pa_analyse_error DEFINITION
  PUBLIC INHERITING FROM cx_static_check FINAL CREATE PUBLIC.
ENDCLASS.
```

---

## 9. Implementierungsplan

### Phase 1 – ABAP-Report (Grundfunktion) – ca. 15 Arbeitstage

| Sprint | Aufgabe | Aufwand |
|---|---|---|
| 1 | Dictionary-Objekte (Tabellen, Domänen, Typen) anlegen | 3 AT |
| 1 | ZCL_PA_PARSER_ST05_XML implementieren und testen | 3 AT |
| 2 | Pattern-Detektoren AP-01 bis AP-06 | 4 AT |
| 2 | Scorer + Recommender | 2 AT |
| 3 | ALV-Output mit Zusammenfassung | 2 AT |
| 3 | Hauptreport + Transaktion + Tests | 1 AT |

### Phase 2 – Erweiterung & RAP-Service – ca. 20 Arbeitstage

| Sprint | Aufgabe | Aufwand |
|---|---|---|
| 4 | Pattern-Detektoren AP-07 bis AP-12 | 3 AT |
| 4 | ST12-Parser | 3 AT |
| 5 | CDS Interface + Consumption Views | 3 AT |
| 5 | RAP Behavior + OData-Service aktivieren | 3 AT |
| 6 | Fiori-App (Fiori Elements, kein Custom UI nötig) | 4 AT |
| 6 | Historisierung + Trending | 4 AT |

### Phase 3 – BTP / Erweiterungen – nach Bedarf

| Aufgabe | Aufwand |
|---|---|
| BTP SAP Analytics Cloud Connector | 5 AT |
| ATC-Integration | 3 AT |
| KI-Maßnahmenempfehlung (Gemini/Claude via BTP) | 8 AT |

---

## 10. Namenskonventionen & Paketstruktur

### Paketstruktur

```
ZPERF_ANALYSER                    " Hauptpaket
  ├── ZPERF_ANALYSER_DICT         " Dictionary-Objekte
  ├── ZPERF_ANALYSER_CORE         " Kernklassen (Importer, Analyser, Scorer)
  ├── ZPERF_ANALYSER_PARSER       " Parser-Klassen
  ├── ZPERF_ANALYSER_DETECTOR     " Detektor-Klassen
  ├── ZPERF_ANALYSER_OUTPUT       " Ausgabe-Klassen (ALV, Service)
  └── ZPERF_ANALYSER_RAP          " RAP-Entitäten (Phase 2)
```

### Namenskonventionen

| Objekt-Typ | Präfix | Beispiel |
|---|---|---|
| Transparente Tabellen | ZPA_ | ZPA_FINDING |
| Klassen | ZCL_PA_ | ZCL_PA_ANALYSER |
| Interfaces | ZIF_PA_ | ZIF_PA_DETECTOR |
| CDS Interface Views | ZI_PA_ | ZI_PA_FINDING |
| CDS Consumption Views | ZC_PA_ | ZC_PA_FINDING |
| Behavior Definitions | ZBP_C_PA_ | ZBP_C_PA_FINDING |
| Reports | ZRPA_ | ZRPA_PERF_ANALYSE |
| Transaktionen | ZTX_PA_ | ZTX_PA_ANALYSE |
| Ausnahmen | ZCX_PA_ | ZCX_PA_PARSE_ERROR |
| Domänen | ZPA_ | ZPA_PRIORITAET |
| Transportaufträge | Separater Transport je Phase | — |

---

## Anhang A – Finding-Typ-Katalog (Initialbefüllung ZPA_FINDING_TYPE)

| finding_type | beschreibung | kategorie | basis_score |
|---|---|---|---|
| SELECT_LOOP | SELECT-Statement in ABAP-Schleife | ABAP_LOGIK | 80 |
| FULL_SCAN | Full Table Scan ohne Index | DB_ACCESS | 75 |
| NO_WHERE | SELECT ohne WHERE-Bedingung | DB_ACCESS | 85 |
| HIGH_RUNTIME | Einzelstatement mit hoher Laufzeit | DB_ACCESS | 70 |
| EXPENSIVE_JOIN | Teurer Multi-Table-JOIN | DB_ACCESS | 65 |
| CDS_EXPENSIVE | Teurer CDS-View-Zugriff | CDS_ODATA | 70 |
| LOW_SELECTIVITY | Hohe Datenmenge, geringe Nutzung | ABAP_LOGIK | 60 |
| DUPLICATE_SELECT | Identisches SQL mehrfach ausgeführt | ABAP_LOGIK | 55 |
| ODATA_HIGH_RUNTIME | OData/Gateway-Aufruf hohe Laufzeit | CDS_ODATA | 75 |
| RFC_HIGH_RUNTIME | RFC/BAPI-Aufruf hohe Laufzeit | RFC_BAPI | 70 |
| TIME_SPLIT_ANOMALY | Auffälliges DB/ABAP-Zeitverhältnis | ARCHITEKTUR | 40 |
| CLUSTER_ACCESS | Zugriff auf Cluster/Pool-Tabelle | ARCHITEKTUR | 50 |

---

## Anhang B – Schwellwert-Konfiguration (ZPA_SCORE_CONFIG)

| parameter | wert | einheit | beschreibung |
|---|---|---|---|
| LOOP_MIN_EXEC | 5 | Anzahl | Minimum Ausführungen für Loop-Erkennung |
| FULLSCAN_MIN_RECS | 10000 | Datensätze | Minimum Records für Full-Scan-Warnung |
| HIGH_RT_KRITISCH | 10000000 | µs | Schwelle für KRITISCH (10 Sek) |
| HIGH_RT_HOCH | 2000000 | µs | Schwelle für HOCH (2 Sek) |
| HIGH_RT_MITTEL | 500000 | µs | Schwelle für MITTEL (0,5 Sek) |
| SELECTIVITY_MIN | 0.05 | Ratio | Minimum-Selektivität vor Warnung |
| DUPLICATE_MIN | 3 | Anzahl | Minimum gleiche SQLs für Duplikat-Warnung |
| ODATA_RT_HOCH | 2000000 | µs | OData-Schwelle HOCH |
| RFC_RT_HOCH | 1000000 | µs | RFC-Schwelle HOCH |
| SCORE_W_RUNTIME | 0.35 | Gewicht | Score-Gewicht Laufzeit |
| SCORE_W_FREQ | 0.25 | Gewicht | Score-Gewicht Häufigkeit |
| SCORE_W_DATAVOL | 0.20 | Gewicht | Score-Gewicht Datenmenge |
| SCORE_W_PATTERN | 0.15 | Gewicht | Score-Gewicht Pattern-Typ |
| SCORE_W_CUSTOM | 0.05 | Gewicht | Score-Gewicht Custom-Code-Bonus |
