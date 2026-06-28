"--------------------------------------------------------------------
" ZCL_PA_DET_SELECT_LOOP – Detektor: SELECT in ABAP-Schleife
"
" Erkennungslogik:
"   Primär: PTC_VALUEID-Sätze (data_source = 'PTC_VALUEID') –
"           SAP liefert wertidentische SQLs bereits fertig gezählt.
"           anzahl_exec > Schwellwert → SELECT-in-Loop-Verdacht.
"
"   Sekundär: PTC_MAIN-Sätze mit gleichem sql_hash mehrfach vorhanden
"             (Fallback wenn kein VALUEID-Eintrag existiert).
"--------------------------------------------------------------------
CLASS zcl_pa_det_select_loop DEFINITION
  PUBLIC FINAL CREATE PUBLIC
  INTERFACES zif_pa_detector.

  PUBLIC SECTION.
    METHODS constructor.

  PRIVATE SECTION.
    DATA mv_min_exec  TYPE abap.int4.   " Schwellwert Ausführungen

    METHODS load_threshold.
    METHODS build_finding
      IMPORTING
        iv_session_id  TYPE sysuuid_x16
        is_item        TYPE zpa_trace_item
      RETURNING
        VALUE(rs_finding) TYPE zpa_finding.
    METHODS detect_via_main_records
      IMPORTING
        it_items       TYPE zif_pa_detector=>tt_items
        iv_session_id  TYPE sysuuid_x16
      RETURNING
        VALUE(rt_findings) TYPE zif_pa_detector=>tt_findings.
ENDCLASS.

CLASS zcl_pa_det_select_loop IMPLEMENTATION.

  METHOD constructor.
    load_threshold( ).
  ENDMETHOD.

  METHOD zif_pa_detector~get_type.
    rv_type = 'SELECT_LOOP'.
  ENDMETHOD.

  METHOD load_threshold.
    SELECT SINGLE wert_num FROM zpa_config
      WHERE mandt     = @sy-mandt
        AND parameter = 'LOOP_MIN_EXEC'
      INTO @DATA(lv_val).
    mv_min_exec = COND #( WHEN sy-subrc = 0 AND lv_val > 0
                          THEN CONV #( lv_val )
                          ELSE 5 ).
  ENDMETHOD.

  METHOD zif_pa_detector~detect.

    " --- Primär: PTC_VALUEID (wertidentische SQLs, fertig von SAP aggregiert) ---
    LOOP AT it_items INTO DATA(ls_item)
      WHERE data_source = 'PTC_VALUEID'
        AND stmt_type   = 'SUMM_IDENT'
        AND anzahl_exec >= mv_min_exec.

      APPEND build_finding( iv_session_id = iv_session_id
                            is_item       = ls_item ) TO rt_findings.
    ENDLOOP.

    " --- Sekundär: PTC_MAIN – gleicher Hash mehrfach (Fallback) ---
    IF rt_findings IS INITIAL.
      APPEND LINES OF detect_via_main_records(
        it_items      = it_items
        iv_session_id = iv_session_id ) TO rt_findings.
    ENDIF.
  ENDMETHOD.


  METHOD build_finding.
    TRY.
        rs_finding-finding_id   = cl_system_uuid=>create_uuid_x16_static( ).
      CATCH cx_uuid_error.
        rs_finding-finding_id   = '0000000000000000'.
    ENDTRY.

    rs_finding-session_id     = iv_session_id.
    rs_finding-item_seq       = is_item-item_seq.
    rs_finding-finding_type   = 'SELECT_LOOP'.
    rs_finding-kategorie      = 'ABAP_LOGIK'.
    rs_finding-programm       = is_item-program_name.
    rs_finding-tabname        = is_item-tabname.
    rs_finding-sql_hash       = is_item-sql_hash.
    rs_finding-laufzeit_us    = is_item-laufzeit_us.
    rs_finding-anzahl_exec    = is_item-anzahl_exec.
    rs_finding-datenmenge     = is_item-records_fetched.
    rs_finding-is_custom_code = is_item-is_custom_code.

    " SQL-Kurzform: erste 200 Zeichen
    rs_finding-sql_kurzform   = substring( val = is_item-sql_text
                                           len = MIN( strlen( is_item-sql_text ), 200 ) ).

    rs_finding-technische_ursache =
      |SELECT auf { is_item-tabname } wurde { is_item-anzahl_exec }x mit identischen Werten ausgeführt. | &&
      |Ø { is_item-avg_duration_us } µs / Aufruf. Gesamtlaufzeit: { is_item-laufzeit_us } µs.|.

    rs_finding-fachliche_einsch =
      |Das SQL-Statement wird wiederholt mit jeweils einem Einzelwert aufgerufen. | &&
      |Typisches Muster: LOOP AT lt_data ... SELECT ... WHERE key = ls_data-key. ENDLOOP.|.

    rs_finding-empf_massnahme =
      |SELECT ... FOR ALL ENTRIES IN lt_data verwenden oder | &&
      |JOIN auf die Quelltabelle aufbauen. Ergebnis in interner Tabelle puffern.|.
  ENDMETHOD.


  METHOD detect_via_main_records.
    " Gruppierung der Haupt-Sätze nach sql_hash
    TYPES: BEGIN OF ty_hash_group,
             sql_hash       TYPE abap.char(32),
             tabname        TYPE tabname,
             program_name   TYPE ptc_program_name,
             laufzeit_us    TYPE abap.int8,
             records_fetched TYPE abap.int4,
             is_custom_code TYPE abap_bool,
             item_seq       TYPE abap.int4,
             avg_duration_us TYPE abap.int8,
             sql_text       TYPE string,
             count          TYPE i,
           END OF ty_hash_group.

    DATA lt_grouped TYPE SORTED TABLE OF ty_hash_group
      WITH UNIQUE KEY sql_hash.

    LOOP AT it_items INTO DATA(ls_item)
      WHERE data_source = 'PTC_MAIN'
        AND stmt_type   = 'SELECT'
        AND sql_hash    IS NOT INITIAL.

      DATA(lv_hash) = ls_item-sql_hash.

      READ TABLE lt_grouped WITH KEY sql_hash = lv_hash
        ASSIGNING FIELD-SYMBOL(<grp>).

      IF sy-subrc = 0.
        <grp>-count          += 1.
        <grp>-laufzeit_us    += ls_item-laufzeit_us.
        <grp>-records_fetched += ls_item-records_fetched.
      ELSE.
        INSERT VALUE #(
          sql_hash        = lv_hash
          tabname         = ls_item-tabname
          program_name    = ls_item-program_name
          laufzeit_us     = ls_item-laufzeit_us
          records_fetched = ls_item-records_fetched
          is_custom_code  = ls_item-is_custom_code
          item_seq        = ls_item-item_seq
          sql_text        = ls_item-sql_text
          count           = 1 ) INTO TABLE lt_grouped.
      ENDIF.
    ENDLOOP.

    " Findings für Gruppen ab Schwellwert
    LOOP AT lt_grouped INTO DATA(ls_grp)
      WHERE count >= mv_min_exec.

      DATA ls_synthetic TYPE zpa_trace_item.
      ls_synthetic-item_seq       = ls_grp-item_seq.
      ls_synthetic-tabname        = ls_grp-tabname.
      ls_synthetic-program_name   = ls_grp-program_name.
      ls_synthetic-sql_hash       = ls_grp-sql_hash.
      ls_synthetic-sql_text       = ls_grp-sql_text.
      ls_synthetic-laufzeit_us    = ls_grp-laufzeit_us.
      ls_synthetic-anzahl_exec    = ls_grp-count.
      ls_synthetic-records_fetched = ls_grp-records_fetched.
      ls_synthetic-is_custom_code = ls_grp-is_custom_code.
      ls_synthetic-avg_duration_us = ls_grp-laufzeit_us / ls_grp-count.
      ls_synthetic-data_source    = 'PTC_MAIN'.

      APPEND build_finding( iv_session_id = iv_session_id
                            is_item       = ls_synthetic ) TO rt_findings.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
