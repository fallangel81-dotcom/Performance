"--------------------------------------------------------------------
" ZCL_PA_DET_DUPLICATE – Detektor: Identische SQLs / Pufferpotenzial
"
" Verwendet PTC_STRUCTID-Sätze (structure_id_record_table):
"   structure_identical > 0: gleiche SQL-Struktur, verschiedene Werte
"                            → FOR ALL ENTRIES oder JOIN möglich
"   value_identical > 0:     exakt gleicher SQL + Werte
"                            → Ergebnis pufferbar (Klassen-Attribut)
"--------------------------------------------------------------------
CLASS zcl_pa_det_duplicate DEFINITION
  PUBLIC FINAL CREATE PUBLIC
  INTERFACES zif_pa_detector.

  PUBLIC SECTION.
    METHODS constructor.

  PRIVATE SECTION.
    DATA mv_min_exec TYPE abap.int4.

    METHODS load_threshold.
    METHODS build_finding
      IMPORTING
        iv_session_id  TYPE sysuuid_x16
        is_item        TYPE zpa_trace_item
        iv_subtype     TYPE c             " 'V'=Value 'S'=Structure
      RETURNING
        VALUE(rs_finding) TYPE zpa_finding.
ENDCLASS.

CLASS zcl_pa_det_duplicate IMPLEMENTATION.

  METHOD constructor.
    load_threshold( ).
  ENDMETHOD.

  METHOD zif_pa_detector~get_type.
    rv_type = 'DUPLICATE_SQL'.
  ENDMETHOD.

  METHOD load_threshold.
    SELECT SINGLE wert_num FROM zpa_config
      WHERE mandt = @sy-mandt AND parameter = 'DUPLICATE_MIN'
      INTO @DATA(lv_val).
    mv_min_exec = COND #( WHEN sy-subrc = 0 AND lv_val > 0
                          THEN CONV #( lv_val ) ELSE 3 ).
  ENDMETHOD.

  METHOD zif_pa_detector~detect.
    " --- Wertidentische SQLs: exakt gleicher SQL + Werte ---
    " Quelle: PTC_VALUEID – nur Sätze mit value_identical-Charakter
    LOOP AT it_items INTO DATA(ls_item)
      WHERE data_source = 'PTC_VALUEID'
        AND anzahl_exec >= mv_min_exec.

      APPEND build_finding(
        iv_session_id = iv_session_id
        is_item       = ls_item
        iv_subtype    = 'V' ) TO rt_findings.
    ENDLOOP.

    " --- Strukturidentische SQLs: gleicher SQL, andere Werte ---
    " Quelle: PTC_STRUCTID – Hinweis auf fehlende Bündelung
    LOOP AT it_items INTO DATA(ls_item)
      WHERE data_source = 'PTC_STRUCTID'
        AND anzahl_exec >= mv_min_exec.

      " Nur wenn NICHT schon als SELECT_LOOP erkannt (Überschneidung vermeiden)
      " SELECT_LOOP hat anzahl_exec >= 5 mit wertidentischen Werten
      " Hier: strukturidentisch aber verschiedene Werte → andere Maßnahme
      APPEND build_finding(
        iv_session_id = iv_session_id
        is_item       = ls_item
        iv_subtype    = 'S' ) TO rt_findings.
    ENDLOOP.

    " Duplikate entfernen
    SORT rt_findings BY sql_hash finding_type.
    DELETE ADJACENT DUPLICATES FROM rt_findings COMPARING sql_hash finding_type.
  ENDMETHOD.


  METHOD build_finding.
    TRY.
        rs_finding-finding_id = cl_system_uuid=>create_uuid_x16_static( ).
      CATCH cx_uuid_error.
        rs_finding-finding_id = '0000000000000000'.
    ENDTRY.

    rs_finding-session_id     = iv_session_id.
    rs_finding-item_seq       = is_item-item_seq.
    rs_finding-finding_type   = 'DUPLICATE_SQL'.
    rs_finding-kategorie      = 'ABAP_LOGIK'.
    rs_finding-programm       = is_item-program_name.
    rs_finding-tabname        = is_item-tabname.
    rs_finding-sql_hash       = is_item-sql_hash.
    rs_finding-laufzeit_us    = is_item-laufzeit_us.
    rs_finding-anzahl_exec    = is_item-anzahl_exec.
    rs_finding-datenmenge     = is_item-records_fetched.
    rs_finding-is_custom_code = is_item-is_custom_code.
    rs_finding-sql_kurzform   = substring( val = is_item-sql_text
                                           len = MIN( strlen( is_item-sql_text ), 200 ) ).

    CASE iv_subtype.
      WHEN 'V'.  " Wertidentisch – Ergebnis puffern
        rs_finding-technische_ursache =
          |Exakt gleicher SQL auf { is_item-tabname } mit identischen Werten wurde | &&
          |{ is_item-anzahl_exec }x ausgeführt. Gesamtlaufzeit: { is_item-laufzeit_us / 1000000 } Sek.|.
        rs_finding-fachliche_einsch =
          |Das identische Ergebnis wird mehrfach von der Datenbank gelesen. | &&
          |Typische Ursache: Methode ohne Ergebnispufferung wird mehrfach aufgerufen.|.
        rs_finding-empf_massnahme =
          |Ergebnis in Klassen-Attribut (statisch) oder interner Tabelle puffern. | &&
          |Muster: IF mo_cached IS INITIAL. SELECT ... mo_cached = lt_result. ENDIF.|.

      WHEN 'S'.  " Strukturidentisch – Bündelung prüfen
        rs_finding-technische_ursache =
          |Strukturell gleicher SQL auf { is_item-tabname } mit verschiedenen Werten | &&
          |wurde { is_item-anzahl_exec }x ausgeführt. Hinweis auf fehlende Bündelung.|.
        rs_finding-fachliche_einsch =
          |Gleiche SQL-Struktur mit unterschiedlichen Schlüsselwerten deutet auf | &&
          |eine Schleife hin, die einzelne Sätze sequenziell liest.|.
        rs_finding-empf_massnahme =
          |SELECT ... FOR ALL ENTRIES IN lt_keys oder JOIN verwenden | &&
          |um alle benötigten Sätze in einem Datenbankaufruf zu lesen.|.
    ENDCASE.
  ENDMETHOD.

ENDCLASS.
