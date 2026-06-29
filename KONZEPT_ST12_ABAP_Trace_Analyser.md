# ST12 ABAP Trace Analyser – Fachlich-Technisches Konzept
## SAP S/4HANA On-Premise 2023 SP4 | Version 1.0 | Juni 2026

---

## Inhaltsverzeichnis

1. [Zielbild](#1-zielbild)
2. [Abgrenzung ST05 vs. ST12](#2-abgrenzung-st05-vs-st12)
3. [Architektur](#3-architektur)
4. [Datenmodell](#4-datenmodell)
5. [Auswertungslogik & ABAP-Performance-Indikatoren](#5-auswertungslogik--abap-performance-indikatoren)
6. [Scoring- und Klassifikationsmodell](#6-scoring--und-klassifikationsmodell)
7. [UI-Konzept (Fiori)](#7-ui-konzept-fiori)
8. [Erweiterbarkeit & Integration mit ST05 Analyser](#8-erweiterbarkeit--integration-mit-st05-analyser)
9. [Implementierungsplan](#9-implementierungsplan)
10. [Namenskonventionen & Paketstruktur](#10-namenskonventionen--paketstruktur)

---

## 1. Zielbild

### 1.1 Problemstellung

ST12 (ABAP Trace / Runtime Analysis) ist das zentrale SAP-Werkzeug zur Analyse von ABAP-Laufzeiten auf Methoden- und Zeilenebene. Die manuelle Auswertung ist jedoch:

- **Visuell überwältigend** – tausende Einträge im Call-Baum ohne Priorisierung
- **Nicht vergleichbar** – kein historischer Kontext zwischen Releases oder nach Optimierungen
- **Isoliert vom SQL-Kontext** – kein direkter Bezug zu ST05-Befunden derselben Session
- **Nicht managementfähig** – reine Entwicklerwerkzeug-Optik, keine Zusammenfassung
- **Flüchtig** – Trace-Ergebnisse werden nicht persistiert, Erkenntnisse gehen verloren

### 1.2 Lösungsziel

Ein **ST12 ABAP Trace Analyser** (Kurzname: **Z_ABAP_TRACE**), der:

1. ST12-Exportdaten (XML) importiert und strukturiert in der bestehenden ZPA-Infrastruktur speichert
2. Automatisch ABAP-seitige Performance-Anti-Pattern erkennt und klassifiziert
3. Eine **interaktive Fiori-Oberfläche** mit Call-Tree, Hotspot-Ansicht und Flamegraph bietet
4. **Kombinierte Sicht** mit ST05-Befunden derselben Transaktion ermöglicht
5. **Historische Vergleiche** unterstützt (vor/nach Optimierung, vor/nach Release-Upgrade)

### 1.3 Variantenentscheidung

| Kriterium | Variante A: ABAP Report + ALV | Variante B: Fiori-First (RAP/OData) |
|---|---|---|
| Visualisierung Call-Tree | Eingeschränkt (ALV-Tree) | Optimal (Fiori Tree/Chart) |
| Flamegraph-Darstellung | Nicht möglich | Möglich via Custom Control |
| Time-to-Market | Schnell (Wochen) | Mittel (Monate) |
| Historisierung | Manuell | Integriert |
| Zielgruppe | Nur Entwickler | Entwickler + Management |
| Integration ST05 | Separate Reports | Einheitliches Dashboard |

**Empfehlung: Fiori-First**

Im Gegensatz zum ST05 Analyser (der mit einem ABAP-Report startete) bietet sich für ST12 direkt der Fiori-Ansatz an, da die Call-Baum-Visualisierung in ALV strukturell schwierig ist. Die bestehende ZPA-Infrastruktur (Tabellen, Scorer, Findings-Modell) wird vollständig wiederverwendet.

---

## 2. Abgrenzung ST05 vs. ST12

| Dimension | ST05 (SQL Trace) | ST12 (ABAP Trace) |
|---|---|---|
| **Fokus** | Datenbankzugriffe | ABAP-Programmablauf |
| **Granularität** | Pro SQL-Statement | Pro Methode / Funktionsbaustein / Zeile |
| **Hauptmetrik** | Laufzeit (µs) + Records | Net-Zeit, Gross-Zeit, Hit-Count |
| **Strukturprinzip** | Flache Liste von Statements | Hierarchischer Aufrufbaum |
| **Typische Probleme** | Full Scan, SELECT-in-Loop | Teure Methoden, tiefe Rekursion, String-Ops |
| **Ausgabe-Anforderung** | Priorisierte Mängelliste | Interaktiver Call-Tree + Hotspots |
| **Kombinierbarkeit** | Ergänzt ST12 (ABAP-Seite) | Ergänzt ST05 (DB-Seite) |

**Kombinierter Nutzen:**
Dieselbe Transaktion wird mit beiden Werkzeugen aufgezeichnet. Der Analyser zeigt dann:
- ST05-Befunde: Wo wird ineffizient auf die DB zugegriffen?
- ST12-Befunde: Welche ABAP-Methoden verursachen den Overhead?
- Verknüpfung: Aus welcher Methode (ST12) kommen die teuren SQL-Statements (ST05)?

---

## 3. Architektur

### 3.1 Gesamtarchitektur

```
┌─────────────────────────────────────────────────────────────────────┐
│                Z_ABAP_TRACE – Gesamtarchitektur                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  DATENQUELLEN              IMPORT/PARSE           PERSISTENZ        │
│  ─────────────             ────────────           ─────────         │
│  ST12 XML-Export    ──►    ST12-Parser     ──►    ZPA_TRACE_SESSION │
│  (Existing Session) ──►    (Wiederverw.)   ──►    ZPA_CALL_NODE    │
│                                                   ZPA_CALL_EDGE    │
│                                                   ZPA_FINDINGS     │
│                                                                     │
│  ANALYSE-ENGINE             SCORING                AUSGABE          │
│  ──────────────             ───────                ───────          │
│  ZCL_AT_ANAL_HOT    ──►    Scorer/Prio    ──►    Fiori-App        │
│  ZCL_AT_ANAL_DEPTH  ──►    Klassifier    ──►    Call-Tree-UI      │
│  ZCL_AT_ANAL_LOOP   ──►    Recommender   ──►    Flamegraph-UI     │
│  ZCL_AT_ANAL_STRING ──►    Aggregator    ──►    Hotspot-Liste     │
│  ZCL_AT_ANAL_ITAB   ──►                  ──►    OData-Service     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 3.2 Komponentenübersicht

```
ZCL_AT_IMPORTER               – Orchestrierung des ST12-Imports
  └── ZCL_PA_PARSER_ST12       – ST12 XML-Parser (neu)

ZCL_AT_ANALYSER               – Orchestrierung der ABAP-Analyse
  ├── ZCL_AT_ANAL_HOT          – Hotspot-Erkennung (hohe Netto-Laufzeit)
  ├── ZCL_AT_ANAL_DEPTH        – Tiefe Call-Hierarchie / Rekursion
  ├── ZCL_AT_ANAL_LOOP         – ABAP-Loop-Overhead-Erkennung
  ├── ZCL_AT_ANAL_STRING       – String-Operationen-Analyse
  ├── ZCL_AT_ANAL_ITAB         – Interne-Tabellen-Analyse
  └── ZCL_AT_ANAL_COMBINED     – Kombinierte ST05+ST12-Analyse

ZCL_AT_SCORER                 – Scoring (erweitert ZCL_PA_SCORER)
ZCL_AT_RECOMMENDER            – ABAP-spezifische Maßnahmen-Engine

ZI_AT_CALL_NODE               – CDS Interface View Call-Knoten
ZI_AT_HOTSPOT                 – CDS Interface View Hotspots
ZC_AT_CALL_NODE               – CDS Consumption View (RAP)
ZC_AT_HOTSPOT                 – CDS Consumption View (RAP)
ZC_AT_SESSION_OVERVIEW        – CDS Consumption View Übersicht
```

### 3.3 Technologie-Stack

| Schicht | Technologie | SAP-Objekt |
|---|---|---|
| Persistenz | Transparente ABAP-Dictionary-Tabellen | ZPA_* + ZAT_* Tabellen |
| Business Logic | ABAP OO, Interfaces | ZCL_AT_*, ZIF_AT_* |
| Import | ABAP XML-Transformation (iXML) | ZCL_PA_PARSER_ST12 |
| Ausgabe | RAP (ABAP RESTful Application Programming) | ZI_AT_*, ZC_AT_* |
| Fiori-UI | Fiori Elements + Custom Section (Flamegraph) | SAP UI5 / Fiori |
| OData | V4 via RAP | Automatisch generiert |

---

## 4. Datenmodell

### 4.1 Neue Persistenztabellen (Ergänzung zu ZPA_*)

#### ZAT_CALL_NODE – Knoten des ABAP-Aufrufbaums

```abap
@EndUserText.label : 'AT: ABAP Call-Tree Knoten'
define table zat_call_node {
  key session_id      : zpa_session_id;     " Bezug zur ZPA_TRACE_SESSION
  key node_id         : zat_node_id;        " Eindeutige Knoten-ID (laufend)
  parent_node_id      : zat_node_id;        " Übergeordneter Knoten (0 = Root)
  call_depth          : i;                  " Tiefe im Aufrufbaum (Root = 0)
  call_type           : zat_call_type;      " METHOD / FUNCTION / FORM / PROG / EVENT
  object_type         : zat_obj_type;       " CLASS / FUGR / PROG / REPORT
  object_name         : zat_obj_name;       " Klasse, Funktionsgruppe, Programm
  method_name         : zat_method_name;    " Methode, Funktionsbaustein, FORM
  include_name        : include;            " Include (bei Programmen)
  line_from           : i;                  " Erste Zeile im Include
  line_to             : i;                  " Letzte Zeile im Include
  hit_count           : zat_hit_count;      " Anzahl Aufrufe dieses Knotens
  gross_time_us       : zpa_laufzeit_us;    " Brutto-Zeit inkl. Unteraufrufe (µs)
  net_time_us         : zpa_laufzeit_us;    " Netto-Zeit exkl. Unteraufrufe (µs)
  db_time_us          : zpa_laufzeit_us;    " Datenbankzeit in diesem Knoten (µs)
  is_custom_code      : zpa_boolean;        " Z* / Y* Namensraum
  is_recursive        : zpa_boolean;        " Tritt auch als Vorfahre auf
  program_name        : progname;           " ABAP-Programm
}
```

#### ZAT_LINE_PROFILE – Zeilengenaues Profil (optional, bei Statement-Level-Trace)

```abap
@EndUserText.label : 'AT: Zeilenprofil (Statement Level)'
define table zat_line_profile {
  key session_id      : zpa_session_id;
  key node_id         : zat_node_id;
  key line_number     : i;
  hit_count           : zat_hit_count;
  time_us             : zpa_laufzeit_us;    " Zeit dieser Zeile
  stmt_type           : zat_stmt_type;      " ASSIGN / LOOP / READ TABLE / etc.
}
```

#### ZAT_SESSION_SUMMARY – Aggregierte Kennzahlen je Session

```abap
@EndUserText.label : 'AT: Session-Zusammenfassung'
define table zat_session_summary {
  key session_id          : zpa_session_id;
  total_nodes             : zat_hit_count;   " Gesamtzahl Knoten im Baum
  max_call_depth          : i;               " Maximale Aufruftiefe
  top_net_node_id         : zat_node_id;     " Knoten mit höchster Netto-Zeit
  abap_net_time_us        : zpa_laufzeit_us; " Gesamte ABAP-Netto-Zeit
  db_time_us              : zpa_laufzeit_us; " Gesamte DB-Zeit (aus ST12)
  custom_code_ratio       : p length 5 decimals 2; " Anteil Custom-Code an Laufzeit
  top_object_name         : zat_obj_name;    " Objekt mit höchster Netto-Zeit
  top_method_name         : zat_method_name;
  recursive_calls_found   : zpa_boolean;
  findings_count          : zpa_anzahl;
}
```

### 4.2 ST12-XML-Struktur (vereinfacht)

Das ST12-Exportformat enthält folgende Hauptbereiche:

```xml
<ABAPTRACE>
  <HEADER>
    <SYSTEM>S4H_PRD</SYSTEM>
    <USER>MUSTERMANN</USER>
    <STARTTIME>20260609120000</STARTTIME>
    <PROGRAM>SAPMM60B</PROGRAM>
    <TRANSACTION>MIRO</TRANSACTION>
    <TOTALTIME>45320000</TOTALTIME>     <!-- µs -->
  </HEADER>
  <CALLTREE>
    <NODE id="1" parent="0" depth="0">
      <TYPE>PROG</TYPE>
      <OBJECT>SAPMM60B</OBJECT>
      <METHOD>START-OF-SELECTION</METHOD>
      <HITS>1</HITS>
      <GROSS>45320000</GROSS>           <!-- µs -->
      <NET>1240000</NET>               <!-- µs -->
      <DBTIME>38100000</DBTIME>        <!-- µs -->
    </NODE>
    <NODE id="2" parent="1" depth="1">
      <TYPE>METHOD</TYPE>
      <OBJECT>CL_MRM_MIRO_GEN</OBJECT>
      <METHOD>PROCESS</METHOD>
      <HITS>1</HITS>
      <GROSS>44080000</GROSS>
      <NET>890000</NET>
      <DBTIME>37900000</DBTIME>
    </NODE>
    <!-- ... tausende weitere Knoten ... -->
  </CALLTREE>
  <LINEPROFILE>   <!-- nur bei Statement Level Trace -->
    <ENTRY node="42" line="178" hits="847" time="12340000"/>
    <!-- ... -->
  </LINEPROFILE>
</ABAPTRACE>
```

---

## 5. Auswertungslogik & ABAP-Performance-Indikatoren

### 5.1 Anti-Pattern-Katalog

#### AP-A01: Hotspot – Hohe Netto-Laufzeit (HOT_METHOD)

```
Erkennungskriterium:
  - net_time_us > Schwellwert (Default: 500.000 µs = 0,5 Sek)
  - net_time_us / session.abap_net_time_us > 0.05  (> 5% der Gesamtzeit)

Score-Formel:
  ratio  = net_time_us / session.abap_net_time_us
  score  = MIN( LOG10( net_time_us / 10000 ) * 20 + ratio * 200, 100 )

Empfehlung:
  "Methode intern profilen: Interne Tabellen-Operationen, String-Verkettungen
   und synchrone RFC-Aufrufe sind typische Ursachen hoher Netto-Laufzeit."
```

#### AP-A02: Häufig aufgerufene Hilfsmethode (HIGH_HIT_COUNT)

```
Erkennungskriterium:
  - hit_count > 10.000
  - net_time_us pro Aufruf > 100 µs  (also net_time_us / hit_count > 100)

Score-Formel:
  call_overhead = hit_count * ( net_time_us / hit_count )
  score = MIN( LOG10( call_overhead / 100000 ) * 30, 100 )

Empfehlung:
  "Ergebnis der Methode cachen (Instanzattribut, statische Variable).
   Bei reiner Hilfsmethode: Inlining prüfen oder Ergebnis weitergeben."
```

#### AP-A03: Tiefe Call-Hierarchie (DEEP_CALL_STACK)

```
Erkennungskriterium:
  - call_depth > 30
  - UND net_time_us dieses Pfads > 1.000.000 µs

Score: 50 + MIN( (call_depth - 30) * 2, 30 )

Empfehlung:
  "Tiefe Aufrufketten erhöhen den ABAP-Stack-Overhead und erschweren Debugging.
   Flachere Architektur oder Aggregation von Zwischenaufrufen prüfen."
```

#### AP-A04: Rekursion erkannt (RECURSION)

```
Erkennungskriterium:
  - is_recursive = true
  - hit_count > 100  (nicht triviale Rekursion)

Score: 70 (strukturelles Problem, unabhängig von Laufzeit)

Empfehlung:
  "Rekursion in ABAP führt zu Stack-Problemen bei großen Datenmengen.
   Iterative Implementierung mit explizitem Stack prüfen."
```

#### AP-A05: ABAP-Loop mit hoher Netto-Zeit (ABAP_LOOP_OVERHEAD)

```
Erkennungskriterium (aus Line Profile, falls vorhanden):
  - stmt_type = 'LOOP' ODER 'DO' ODER 'WHILE'
  - hit_count * time_us_pro_iteration > 2.000.000 µs gesamt
  - Kein SQL-Anteil in diesem Knoten (db_time_us < 0.1 * gross_time_us)
    → rein ABAP-seitiger Loop-Overhead

Score-Formel:
  score = MIN( LOG10( hit_count * avg_iter_time / 1000 ) * 25, 100 )

Empfehlung:
  "ABAP-Loop-Body analysieren: String-Operationen, interne Tabellen-Zugriffe
   (READ TABLE ohne Schlüssel, SORT in Loop) und Feldleisten-Nutzung prüfen."
```

#### AP-A06: String-Operationen Overhead (STRING_OPS)

```
Erkennungskriterium (aus Line Profile):
  - stmt_type IN ( 'CONCATENATE', 'SPLIT', 'REPLACE', 'REGEX' )
  - time_us dieser Zeile > 100.000 µs
  - hit_count > 1.000

Empfehlung:
  "String-Tabellen (TYPE string_table) und String-Buffer (CL_ABAP_CONV_OUT_CE)
   statt direkter Konkatenation in Schleifen nutzen.
   Reguläre Ausdrücke nur bei Bedarf – Alternativen: SEARCH, CO, CS."
```

#### AP-A07: Interne Tabellen – teurer Zugriff (ITAB_EXPENSIVE)

```
Erkennungskriterium (aus Line Profile):
  - stmt_type IN ( 'READ TABLE', 'SORT', 'DELETE' ) mit TABLE-Zusatz
  - hit_count > 500
  - time_us > 50.000 µs pro Aufruf (= time_us / hit_count)

Spezialfall SORT:
  - Jedes SORT in einem Loop ist automatisch KRITISCH (unabhängig von Laufzeit)

Empfehlung:
  READ TABLE: Sorted Table + BINARY SEARCH oder Hashed Table einsetzen.
  SORT:       Einmalig vor dem Loop sortieren.
  DELETE:     WHERE-Bedingung statt Schleife mit DELETE TABLE INDEX."
```

#### AP-A08: Custom-Code dominiert Laufzeit (CUSTOM_DOMINATES)

```
Erkennungskriterium (auf Session-Ebene):
  - custom_code_ratio > 0.70  (mehr als 70% der Netto-Zeit in Z*/Y*-Code)

Score: 60 (Indikator für Optimierungspotenzial)

Empfehlung:
  "Eigenentwicklungen dominieren die Laufzeit. Hotspot-Liste auf Z*/Y*-Objekte
   filtern und priorisiert angehen."
```

#### AP-A09: SAP-Standard mit hoher Netto-Zeit (STD_HOTSPOT)

```
Erkennungskriterium:
  - is_custom_code = false
  - net_time_us > 2.000.000 µs

Score: 40

Empfehlung:
  "SAP-Standard-Hotspots können auf falsche Parametrisierung (Selektionsoptionen,
   Customizing) oder fehlende Indizes auf Customizing-Tabellen hinweisen.
   OSS-Hinweise und HANA-spezifische Optimierungen (Code Pushdown) prüfen."
```

#### AP-A10: Verhältnis Gross/Net-Zeit auffällig (GROSS_NET_RATIO)

```
Erkennungskriterium:
  - gross_time_us > 5.000.000 µs
  - net_time_us / gross_time_us < 0.05  (weniger als 5% Eigenzeit)
  - call_depth < 5  (hohes Objekt im Baum)

Bedeutung: Das Objekt selbst ist nicht das Problem – es ruft etwas Teures auf.
Score: 30 (Navigationshinweis, kein echtes Problem)

Empfehlung:
  "Dieses Objekt ist ein 'Durchlauferhitzer'. Das eigentliche Problem liegt
   in einem der Unteraufrufe. Call-Tree für diesen Knoten aufklappen."
```

### 5.2 Erkennungsalgorithmus – Flussdiagramm

```
ST12-Daten importiert
        │
        ▼
┌────────────────────────┐
│ Call-Tree aufbauen     │  Knoten-Eltern-Beziehung aus node_id / parent_id
│ & Baumattribute        │  Rekursion markieren, Tiefe berechnen
│ aggregieren            │  custom_code_ratio auf Session-Ebene
└──────────┬─────────────┘
           │
           ▼
┌──────────────────────────────────────────────┐
│         Pattern-Detektoren                   │
│  (alle auf Knotenliste ausführbar)           │
│                                              │
│  AP-A01: HotMethod-Detector                  │
│  AP-A02: HighHitCount-Detector               │
│  AP-A03: DeepStack-Detector                  │
│  AP-A04: Recursion-Detector                  │
│  AP-A05: AbapLoop-Detector (Line Profile)    │
│  AP-A06: StringOps-Detector (Line Profile)   │
│  AP-A07: ITab-Detector (Line Profile)        │
│  AP-A08: CustomDominates-Detector (Session)  │
│  AP-A09: StdHotspot-Detector                 │
│  AP-A10: GrossNetRatio-Detector              │
└──────────┬───────────────────────────────────┘
           │
           ▼
┌──────────────────┐
│   Scorer         │  Score berechnen, Priorität ableiten (wie ZPA_SCORER)
└──────────┬───────┘
           │
           ▼
┌──────────────────┐
│   Recommender    │  ABAP-spezifische Maßnahmen-Texte
└──────────┬───────┘
           │
           ▼
┌──────────────────┐
│   Persistenz     │  ZPA_FINDING + ZAT_SESSION_SUMMARY befüllen
└──────────┬───────┘
           │
           ▼
┌──────────────────┐
│   Fiori-App      │  Call-Tree, Flamegraph, Hotspot-Liste, Findings
└──────────────────┘
```

---

## 6. Scoring- und Klassifikationsmodell

Das bestehende Scoring-Modell aus dem ST05 Analyser wird übernommen. Ergänzungen für ST12:

### 6.1 Prioritätsklassen (identisch zu ST05)

| Priorität | Score | Bedeutung | Handlungsbedarf |
|---|---|---|---|
| **KRITISCH** | 90–100 | Massive ABAP-Laufzeit, Rekursion, Architekturproblem | Sofort (< 1 Woche) |
| **HOCH** | 70–89 | Signifikanter Hotspot oder hoher Hit-Count-Overhead | Kurzfristig (< 1 Monat) |
| **MITTEL** | 50–69 | Spürbarer Overhead, strukturelles Problem | Mittelfristig (< Quartal) |
| **NIEDRIG** | 20–49 | Optimierungspotenzial | Nächste Entwicklungswelle |
| **HINWEIS** | 1–19 | Best-Practice-Abweichung | Backlog |

### 6.2 Neue Kategorien für ST12-Findings

| Kategorie | Beschreibung | Typische Patterns |
|---|---|---|
| **ABAP_HOTSPOT** | Methode mit hoher Netto-Zeit | HOT_METHOD, HIGH_HIT_COUNT |
| **ABAP_STRUKTUR** | Strukturelle ABAP-Probleme | DEEP_CALL_STACK, RECURSION |
| **ABAP_ITAB** | Interne Tabellen-Ineffizienz | ITAB_EXPENSIVE, SORT in Loop |
| **ABAP_STRING** | String-Verarbeitungs-Overhead | STRING_OPS |
| **ABAP_LOOP** | ABAP-Loop-Overhead | ABAP_LOOP_OVERHEAD |
| **CUSTOM_CODE** | Custom-Code-Dominanz | CUSTOM_DOMINATES |
| **STD_CODE** | SAP-Standard-Hotspot | STD_HOTSPOT |

### 6.3 Finding-Typ-Katalog (Initialbefüllung ZPA_FINDING_TYPE – Ergänzung)

| finding_type | beschreibung | kategorie | basis_score |
|---|---|---|---|
| HOT_METHOD | Methode mit hoher Netto-Laufzeit | ABAP_HOTSPOT | 75 |
| HIGH_HIT_COUNT | Hilfsmethode mit extrem hohem Aufruf-Overhead | ABAP_HOTSPOT | 70 |
| DEEP_CALL_STACK | Aufruftiefe > 30 auf kritischem Pfad | ABAP_STRUKTUR | 55 |
| RECURSION | Rekursiver Aufruf mit > 100 Iterationen | ABAP_STRUKTUR | 70 |
| ABAP_LOOP_OVERHEAD | ABAP-Loop mit hoher Eigenzeit | ABAP_LOOP | 65 |
| STRING_OPS | String-Operationen in heißem Pfad | ABAP_STRING | 60 |
| ITAB_EXPENSIVE | Teurer interner Tabellenzugriff | ABAP_ITAB | 65 |
| SORT_IN_LOOP | SORT-Anweisung innerhalb einer Schleife | ABAP_ITAB | 85 |
| CUSTOM_DOMINATES | Custom-Code > 70% der ABAP-Netto-Zeit | CUSTOM_CODE | 60 |
| STD_HOTSPOT | SAP-Standard-Methode als Hotspot | STD_CODE | 40 |
| GROSS_NET_HINT | Hinweis: Gross/Net-Verhältnis auffällig | ABAP_STRUKTUR | 25 |

---

## 7. UI-Konzept (Fiori)

Da die Call-Baum-Visualisierung das zentrale Element der ST12-Analyse ist, wird von Anfang an auf Fiori als primäre Ausgabe gesetzt. Die App besteht aus drei Hauptbereichen.

### 7.1 Startseite – Session-Übersicht (List Report)

```
┌────────────────────────────────────────────────────────────────────────────┐
│  ABAP Trace Analyser                                          [+ Importieren]│
├────────────────────────────────────────────────────────────────────────────┤
│  Filter: [ Modul ▾ ] [ System ▾ ] [ Zeitraum ▾ ] [ Priorität ▾ ]   [Suchen]│
├──────────────────┬──────────────┬──────────────┬──────────┬────────────────┤
│ Session          │ Transaktion  │ Datum        │ Findings │ Gesamtlaufzeit │
├──────────────────┼──────────────┼──────────────┼──────────┼────────────────┤
│ MIRO-Buchung-QAS │ MIRO         │ 09.06.2026   │ ● 3 ◑ 8  │ 45,3 Sek       │
│ ME21N-Anlage-PRD │ ME21N        │ 07.06.2026   │ ◑ 5 ○ 12 │ 12,7 Sek       │
│ MR8M-Storno-DEV  │ MR8M         │ 05.06.2026   │ ● 1 ◑ 2  │  8,1 Sek       │
└──────────────────┴──────────────┴──────────────┴──────────┴────────────────┘

Legende: ● KRITISCH/HOCH  ◑ MITTEL  ○ NIEDRIG/HINWEIS
```

### 7.2 Session-Detailseite (Object Page) – 4 Tabs

#### Tab 1: Übersicht (KPI-Kacheln + Findings-Liste)

```
┌────────────────────────────────────────────────────────────────────────────┐
│ MIRO-Buchung-QAS  │ MIRO │ 09.06.2026 │ S4H_QAS               [ST05 öffnen]│
├──────────────┬──────────────────┬─────────────────┬────────────────────────┤
│  45,3 Sek    │   ABAP: 7,2 Sek │  DB: 38,1 Sek   │  Custom-Code: 67%      │
│  Gesamt      │   (16%)         │  (84%)           │  der ABAP-Zeit         │
├──────────────┴──────────────────┴─────────────────┴────────────────────────┤
│  [Übersicht]  [Call-Tree]  [Flamegraph]  [Findings]                         │
├────────────────────────────────────────────────────────────────────────────┤
│ KRITISCH / HOCH                                                             │
│                                                                             │
│ ● SORT_IN_LOOP     ZCL_MRM_PO_LINE_ITEMS~AGGREGATE   Zeile 247   Score: 91 │
│   ABAP-ITAB | 847 Aufrufe | 12,4 Sek gesamt                                │
│   → SORT einmalig vor dem LOOP verschieben                                  │
│                                                                             │
│ ● HOT_METHOD       ZRFBU100~VALIDATE_ITEMS                       Score: 83 │
│   ABAP-HOTSPOT | 1 Aufruf | 4,8 Sek Netto-Zeit                             │
│   → Methode intern profilen: READ TABLE ohne BINARY SEARCH gefunden         │
│                                                                             │
│ ◑ HIGH_HIT_COUNT   CL_ABAP_TYPEDESCR~DESCRIBE_BY_DATA            Score: 71 │
│   ABAP-HOTSPOT | 24.500 Aufrufe | Ø 210 µs = 5,1 Sek gesamt                │
│   → Ergebnis in FIELD-SYMBOL-Tabelle cachen                                 │
└────────────────────────────────────────────────────────────────────────────┘
```

#### Tab 2: Call-Tree (interaktiver Baum)

```
┌────────────────────────────────────────────────────────────────────────────┐
│ [Übersicht]  [Call-Tree]  [Flamegraph]  [Findings]                          │
├────────────────────────────────────────────────────────────────────────────┤
│  Filter: [ Custom-Code only ] [ Nur Findings ] [ Min. Gross-Zeit: 100ms ▾ ] │
│  Sortierung: [ nach Gross-Zeit ▾ ]                          [Alle ausklappen]│
├───────────────────────────────────────────────┬──────────┬──────┬──────────┤
│ Knoten                                        │ Gross    │ Net  │ Hits     │
├───────────────────────────────────────────────┼──────────┼──────┼──────────┤
│ ▼ SAPMM60B (START-OF-SELECTION)               │ 45,3 Sek │ 1,2s │ 1        │
│   ▼ CL_MRM_MIRO_GEN~PROCESS                  │ 44,1 Sek │ 0,9s │ 1        │
│     ▼ CL_MRM_MIRO_GEN~VALIDATE               │ 38,2 Sek │ 0,1s │ 1        │
│       ▼ ● ZRFBU100~VALIDATE_ITEMS            │ 18,9 Sek │ 4,8s │ 1        │
│           CL_MRM_PO_LINE_ITEMS~GET_ALL        │ 14,1 Sek │ 0,2s │ 1        │
│         ▼ ● CL_MRM_PO_LINE~AGGREGATE !!      │  9,3 Sek │ 2,1s │ 1        │
│               [SORT IN LOOP – Zeile 247]      │          │      │          │
│       ▼ CL_MRM_INVOICE_ITEM~PROCESS_ALL       │  5,1 Sek │ 0,0s │ 1        │
│           ◑ CL_ABAP_TYPEDESCR~DESCRIBE...    │  5,1 Sek │ 5,1s │ 24.500   │
│   ...                                         │          │      │          │
└───────────────────────────────────────────────┴──────────┴──────┴──────────┘

Legende: ● Finding KRITISCH/HOCH  ◑ Finding MITTEL  !! Statement-Level-Detail
```

**Interaktionsmuster:**
- Klick auf Knoten → Detailpanel rechts mit allen Metriken und zugehörigen Findings
- Doppelklick → Fokus auf diesen Knoten (Unterknoten füllen den Baum)
- "Finding"-Badge → direkter Sprung zum Finding-Detail
- Hover → Tooltip mit Gross/Net/DB-Zeit und Hit-Count

#### Tab 3: Flamegraph

```
┌────────────────────────────────────────────────────────────────────────────┐
│ [Übersicht]  [Call-Tree]  [Flamegraph]  [Findings]                          │
├────────────────────────────────────────────────────────────────────────────┤
│  Metrik: [ Gross-Zeit ▾ ]   Farbe: [ Custom/Standard ▾ ]   [Zoom zurück]   │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  █████████████████████████████████████████████████████████ SAPMM60B (45s) │
│  ████████████████████████████████████████████████████████ CL_MRM_MIRO_GEN │
│  ████████████████████████████████████  CL_MRM_MIRO_GEN~VALIDATE (38s)     │
│  ██████████████████  ZRFBU100~VALIDATE_ITEMS (18s) ████ ...                │
│  ████ CL_MRM~GET ██████████████ CL_MRM_PO_LINE~AGGREGATE (9s) ████ ...    │
│  ████████████ [SORT 247] (7s)  ████  ...                                   │
│                                                                             │
│  Farbe: ████ Custom-Code (Z*/Y*)   ████ SAP-Standard   ████ Finding        │
│                                                                             │
│  Klick auf Block → Zoom + Detailpanel                                       │
└────────────────────────────────────────────────────────────────────────────┘
```

Der Flamegraph ist eine SAP UI5 Custom Section innerhalb der Fiori Elements Object Page. Er wird als SVG-basierter Chart implementiert (UI5 Custom Control oder VizFrame-Workaround). Die Breite jedes Blocks entspricht der Gross-Zeit.

**Interaktionsmuster:**
- Klick auf Block → Zoom in den Teilbaum
- Breadcrumb-Navigation zurück zur Wurzel
- Hover → Tooltip mit Methode, Gross/Net-Zeit, Hits, Findings
- Farbkodierung: Custom-Code (orange), Standard (blau), Finding (rot/gelb)

#### Tab 4: Findings-Liste

```
┌────────────────────────────────────────────────────────────────────────────┐
│ [Übersicht]  [Call-Tree]  [Flamegraph]  [Findings]                          │
├────────────────────────────────────────────────────────────────────────────┤
│  Filter: [ Alle Prios ▾ ] [ Alle Kategorien ▾ ]   Anzahl: 14               │
├─────────┬──────┬──────────────┬──────────────────────────┬────────────────-┤
│ Priorität│Score│ Typ          │ Objekt / Methode          │ Maßnahme        │
├─────────┼──────┼──────────────┼──────────────────────────┼─────────────────┤
│ KRITISCH│  91 │ SORT_IN_LOOP │ CL_MRM_PO_LINE~AGGREGATE  │ SORT vor Loop   │
│ HOCH    │  83 │ HOT_METHOD   │ ZRFBU100~VALIDATE_ITEMS   │ Intern profilen │
│ MITTEL  │  71 │ HIGH_HIT_CNT │ CL_ABAP_TYPEDESCR~DESC... │ Ergebnis cachen │
│ ...     │     │              │                           │                 │
└─────────┴──────┴──────────────┴──────────────────────────┴─────────────────┘
```

### 7.3 Finding-Detailseite

Klick auf ein Finding öffnet eine Object Page mit:

```
┌────────────────────────────────────────────────────────────────────────────┐
│ SORT_IN_LOOP – CL_MRM_PO_LINE_ITEMS~AGGREGATE                   Score: 91 │
├──────────────────┬─────────────────────┬────────────────────────────────────┤
│ Priorität        │ Kategorie           │ Optimierungshebel                  │
│ KRITISCH         │ ABAP_ITAB           │ HOCH (> 80% Reduktion erwartet)    │
├──────────────────┴─────────────────────┴────────────────────────────────────┤
│ Technische Details                                                          │
│ Objekt:    CL_MRM_PO_LINE_ITEMS   Methode: AGGREGATE   Zeile: 247          │
│ Include:   CL_MRM_PO_LINE_ITEMS===CP                                        │
│ Hits:      847   Gross-Zeit: 9,3 Sek   Netto-Zeit: 2,1 Sek                 │
├─────────────────────────────────────────────────────────────────────────────┤
│ Technische Ursache                                                          │
│ SORT-Anweisung innerhalb einer LOOP-Schleife mit 847 Durchläufen.          │
│ Die Tabelle lt_items wird bei jedem Durchlauf neu sortiert (O(n log n)).   │
├─────────────────────────────────────────────────────────────────────────────┤
│ Empfohlene Maßnahme                                                         │
│ SORT lt_items BY bukrs belnr einmalig vor dem LOOP ausführen.              │
│ Alternativ: Sorted Table verwenden, wenn Reihenfolge fix ist.              │
├─────────────────────────────────────────────────────────────────────────────┤
│ Aufrufpfad                                                                  │
│ SAPMM60B > CL_MRM_MIRO_GEN~PROCESS > CL_MRM_MIRO_GEN~VALIDATE >          │
│ ZRFBU100~VALIDATE_ITEMS > CL_MRM_PO_LINE_ITEMS~AGGREGATE ← hier           │
├─────────────────────────────────────────────────────────────────────────────┤
│ Verlauf (Trend)                                                              │
│ [Chart: Score dieser Fundstelle über letzte 5 Sessions]                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 7.4 Kombiniertes ST05+ST12-Dashboard

Wenn für dieselbe Session sowohl ST05- als auch ST12-Daten vorhanden sind, erscheint auf der Übersichtsseite eine kombinierte Ansicht:

```
┌────────────────────────────────────────────────────────────────────────────┐
│ MIRO-Buchung-QAS – Kombinierte Analyse                                      │
├──────────────────────────┬─────────────────────────────────────────────────┤
│ ST12: ABAP-Befunde       │ ST05: SQL-Befunde                               │
│ 3 KRITISCH | 5 HOCH      │ 2 KRITISCH | 8 HOCH                             │
├──────────────────────────┴─────────────────────────────────────────────────┤
│ Top-Verbindung (aus welcher ABAP-Methode kommt der teuerste SQL?):          │
│ ZRFBU100~VALIDATE_ITEMS  →  SELECT * FROM BKPF (28,4 Sek, FULL_SCAN)      │
│ [ST12-Knoten öffnen]          [ST05-Finding öffnen]                         │
└────────────────────────────────────────────────────────────────────────────┘
```

Die Verknüpfung erfolgt über `program_name` + `include_name` als gemeinsamen Schlüssel zwischen ST12-Knoten (`ZAT_CALL_NODE`) und ST05-Findings (`ZPA_FINDING`).

### 7.5 Import-Dialog (Fiori-Overlay)

Der Import wird als modale Fiori-Dialog-Box realisiert (kein separates Selektionsbild):

```
┌──────────────────────────────────────────────────────────┐
│  Neuen Trace importieren                            [✕]  │
├──────────────────────────────────────────────────────────┤
│  Session-Name:   [MIRO-Buchung-QAS                    ]  │
│  System:         [S4H_QAS ▾]                             │
│  Modul:          [MM ▾]                                  │
│  Transaktion:    [MIRO                                ]  │
│  Umgebung:       [● QAS  ○ PRD  ○ DEV]                   │
│                                                          │
│  ST12-Datei:     [____________________________] [Upload] │
│  ST05-Datei:     [____________________________] [Upload] │
│                  (optional, für kombinierte Analyse)     │
│                                                          │
│  [Abbrechen]                              [Importieren]  │
└──────────────────────────────────────────────────────────┘
```

---

## 8. Erweiterbarkeit & Integration mit ST05 Analyser

### 8.1 Gemeinsame Infrastruktur (Wiederverwendung)

| Komponente | ST05 Analyser | ST12 Analyser | Gemeinsam |
|---|---|---|---|
| ZPA_TRACE_SESSION | Primäre Tabelle | Primäre Tabelle | ✓ |
| ZPA_FINDING | Findings-Persistenz | Findings-Persistenz | ✓ |
| ZPA_FINDING_TYPE | Katalog ST05-Pattern | Katalog ST12-Pattern | ✓ (erweitert) |
| ZCL_PA_SCORER | Scoring-Engine | Basis wiederverwendet | ✓ |
| ZCL_PA_RECOMMENDER | Maßnahmen-Texte | Erweitert | Teilweise |
| ZCL_PA_OUTPUT_ALV | ALV-Ausgabe | Nicht verwendet | ✗ |
| ZAT_CALL_NODE | – | Neu | ✗ |
| Fiori-App | Phase 2 geplant | Phase 1 (primär) | Eigene App |

### 8.2 Erweiterungspunkte

#### BAdI: ZAT_BADI_CUSTOM_DETECTOR

```abap
INTERFACE ZIF_AT_CUSTOM_DETECTOR.
  METHODS detect
    IMPORTING
      it_call_nodes TYPE zat_tt_call_node
      is_session    TYPE zpa_trace_session
    CHANGING
      ct_findings   TYPE zpa_tt_finding.
ENDINTERFACE.
```

#### Geplante Erweiterungen

| Erweiterung | Phase | Aufwand | Nutzen |
|---|---|---|---|
| ATC-Integration (Performance-Check in CI/CD) | 2 | M | Frühzeitige Erkennung |
| HANA Plan Visualizer Link aus Findings | 2 | S | Direkt zum SQL-Plan |
| Automatischer ST12-Trace-Trigger via RFC | 2 | M | Kein manueller Export |
| Historien-Trending (n Perioden) | 2 | S | Fortschritt messbar |
| KI-gestützte Maßnahmen (BTP + Claude API) | 3 | L | Automatische Code-Vorschläge |
| Eclipse ADT Plugin-Integration | 3 | L | Direkte Navigation in ABAP IDE |

---

## 9. Implementierungsplan

### Phase 1 – Fiori-App + Kernfunktion – ca. 20 Arbeitstage

| Sprint | Aufgabe | Aufwand |
|---|---|---|
| 1 | Dictionary-Objekte (ZAT_CALL_NODE, ZAT_LINE_PROFILE, ZAT_SESSION_SUMMARY) | 2 AT |
| 1 | ZCL_PA_PARSER_ST12 – ST12 XML-Parser | 4 AT |
| 2 | Pattern-Detektoren AP-A01 bis AP-A05 | 4 AT |
| 2 | Scorer + Recommender (ABAP-spezifische Texte) | 2 AT |
| 3 | CDS Views (ZI_AT_CALL_NODE, ZI_AT_HOTSPOT, ZC_AT_*) | 3 AT |
| 3 | RAP Behavior + OData V4 aktivieren | 2 AT |
| 4 | Fiori Elements App (List Report + Object Page, Tabs 1+4) | 3 AT |

### Phase 2 – Call-Tree + Flamegraph – ca. 15 Arbeitstage

| Sprint | Aufgabe | Aufwand |
|---|---|---|
| 5 | Call-Tree Tab (Fiori Elements Tree Table) | 4 AT |
| 5 | Flamegraph Custom UI5 Control | 6 AT |
| 6 | Detektoren AP-A06 bis AP-A10 (Line Profile) | 3 AT |
| 6 | Kombinierte ST05+ST12-Ansicht | 2 AT |

### Phase 3 – Erweiterungen – nach Bedarf

| Aufgabe | Aufwand |
|---|---|
| ATC-Integration | 3 AT |
| Historien-Trending | 3 AT |
| KI-Maßnahmen via BTP | 8 AT |

---

## 10. Namenskonventionen & Paketstruktur

### Paketstruktur

```
ZPERF_ANALYSER                     " Hauptpaket (gemeinsam mit ST05)
  ├── ZPERF_ANALYSER_DICT          " Dictionary (ZPA_* gemeinsam)
  ├── ZPERF_ANALYSER_CORE          " Kernklassen (gemeinsam)
  ├── ZPERF_ANALYSER_PARSER        " Parser (ZCL_PA_PARSER_ST12 hier)
  ├── ZPERF_ANALYSER_DETECTOR      " ST05-Detektoren
  ├── ZPERF_ANALYSER_OUTPUT        " ALV-Ausgabe (ST05)
  ├── ZABAP_TRACE                  " ST12-spezifisches Unterpaket
  │   ├── ZABAP_TRACE_DICT         " ZAT_* Tabellen
  │   ├── ZABAP_TRACE_DETECTOR     " ZCL_AT_ANAL_* Klassen
  │   └── ZABAP_TRACE_RAP          " CDS Views + Fiori-App
  └── ZPERF_ANALYSER_RAP           " Gemeinsame RAP-Objekte (Phase 2)
```

### Namenskonventionen ST12-spezifisch

| Objekt-Typ | Präfix | Beispiel |
|---|---|---|
| Transparente Tabellen (ST12-spezifisch) | ZAT_ | ZAT_CALL_NODE |
| Analyse-Klassen ST12 | ZCL_AT_ | ZCL_AT_ANAL_HOT |
| Importer ST12 | ZCL_AT_ | ZCL_AT_IMPORTER |
| CDS Interface Views ST12 | ZI_AT_ | ZI_AT_CALL_NODE |
| CDS Consumption Views ST12 | ZC_AT_ | ZC_AT_HOTSPOT |
| Behavior Definitions ST12 | ZBP_C_AT_ | ZBP_C_AT_CALL_NODE |

---

## Anhang A – ST12-XML-Feldmapping

| ST12-XML-Feld | ZAT_CALL_NODE-Feld | Bemerkung |
|---|---|---|
| NODE/@id | node_id | Laufende Nummer |
| NODE/@parent | parent_node_id | 0 bei Root |
| NODE/@depth | call_depth | Tiefe im Baum |
| NODE/TYPE | call_type | METHOD/FUNCTION/FORM/PROG |
| NODE/OBJECT | object_name | Klasse, Funktionsgruppe, Programm |
| NODE/METHOD | method_name | Methode, FB-Name, FORM-Name |
| NODE/HITS | hit_count | Anzahl Aufrufe |
| NODE/GROSS | gross_time_us | Brutto-Zeit µs |
| NODE/NET | net_time_us | Netto-Zeit µs |
| NODE/DBTIME | db_time_us | DB-Zeit µs (aus ST05-Integration) |
| LINEPROFILE/ENTRY/@line | zat_line_profile-line_number | Nur bei Statement-Level |
| LINEPROFILE/ENTRY/@hits | zat_line_profile-hit_count | |
| LINEPROFILE/ENTRY/@time | zat_line_profile-time_us | |

---

## Anhang B – Schwellwert-Konfiguration (Ergänzung ZPA_SCORE_CONFIG)

| parameter | wert | einheit | beschreibung |
|---|---|---|---|
| AT_HOT_NET_TIME | 500000 | µs | Schwelle HOT_METHOD (0,5 Sek) |
| AT_HOT_RATIO | 0.05 | Ratio | Min. Anteil an Gesamt-ABAP-Zeit |
| AT_HIGH_HIT | 10000 | Anzahl | Schwelle HIGH_HIT_COUNT |
| AT_HIT_NET_PER_CALL | 100 | µs | Min. Netto-Zeit pro Aufruf für HIGH_HIT |
| AT_DEEP_STACK | 30 | Level | Tiefe-Schwelle für DEEP_CALL_STACK |
| AT_RECURSION_MIN | 100 | Hits | Min. Hits für RECURSION-Erkennung |
| AT_LOOP_TOTAL | 2000000 | µs | Schwelle ABAP_LOOP_OVERHEAD gesamt |
| AT_STRING_TIME | 100000 | µs | Schwelle STRING_OPS-Zeile |
| AT_STRING_HITS | 1000 | Anzahl | Min. Hits für STRING_OPS |
| AT_ITAB_PER_CALL | 50000 | µs | Min. Zeit pro Aufruf ITAB_EXPENSIVE |
| AT_ITAB_HITS | 500 | Anzahl | Min. Hits für ITAB_EXPENSIVE |
| AT_CUSTOM_RATIO | 0.70 | Ratio | Schwelle CUSTOM_DOMINATES |
| AT_STD_HOT_NET | 2000000 | µs | Schwelle STD_HOTSPOT (2 Sek) |
