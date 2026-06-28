"--------------------------------------------------------------------
" ZCL_PA_ANALYSER – Orchestrierung aller Pattern-Detektoren
"
" Neue Detektoren einfach in CONSTRUCTOR registrieren –
" kein Eingriff in den restlichen Code nötig.
"--------------------------------------------------------------------
CLASS zcl_pa_analyser DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS constructor.

    METHODS analyse
      IMPORTING
        iv_session_id  TYPE sysuuid_x16
        it_items       TYPE zif_pa_detector=>tt_items
      RETURNING
        VALUE(rt_findings) TYPE zif_pa_detector=>tt_findings.

  PRIVATE SECTION.
    DATA mt_detectors TYPE STANDARD TABLE OF REF TO zif_pa_detector
                      WITH DEFAULT KEY.
    DATA mo_scorer    TYPE REF TO zcl_pa_scorer.

    METHODS register_detectors.
    METHODS deduplicate
      CHANGING ct_findings TYPE zif_pa_detector=>tt_findings.
ENDCLASS.

CLASS zcl_pa_analyser IMPLEMENTATION.

  METHOD constructor.
    mo_scorer = NEW zcl_pa_scorer( ).
    register_detectors( ).
  ENDMETHOD.


  METHOD register_detectors.
    " Reihenfolge bestimmt die Verarbeitungsreihenfolge.
    " Neue Detektoren hier einfach ergänzen:
    APPEND NEW zcl_pa_det_select_loop( ) TO mt_detectors.
    APPEND NEW zcl_pa_det_full_scan( )   TO mt_detectors.
    " APPEND NEW zcl_pa_det_high_runtime( ) TO mt_detectors.  " Phase 2
    " APPEND NEW zcl_pa_det_duplicate( )    TO mt_detectors.  " Phase 2
    " APPEND NEW zcl_pa_det_odata( )        TO mt_detectors.  " Phase 2
  ENDMETHOD.


  METHOD analyse.
    IF it_items IS INITIAL. RETURN. ENDIF.

    DATA lv_det_count TYPE i VALUE 0.
    DATA lv_total     TYPE i.
    lv_total = lines( mt_detectors ).

    " Jeden Detektor ausführen
    LOOP AT mt_detectors INTO DATA(lo_det).
      lv_det_count += 1.

      cl_progress_indicator=>progress_indicate(
        i_text               = |Detektor { lv_det_count }/{ lv_total }: { lo_det->get_type( ) }|
        i_processed          = lv_det_count
        i_total              = lv_total
        i_output_immediately = abap_true ).

      TRY.
          DATA(lt_new) = lo_det->detect(
            it_items      = it_items
            iv_session_id = iv_session_id ).

          APPEND LINES OF lt_new TO rt_findings.

        CATCH cx_root INTO DATA(lx).
          " Einzelnen fehlerhaften Detektor überspringen
          MESSAGE |Detektor { lo_det->get_type( ) } fehlgeschlagen: { lx->get_text( ) }|
                  TYPE 'W'.
      ENDTRY.
    ENDLOOP.

    " Score und Priorität für jedes Finding berechnen
    LOOP AT rt_findings ASSIGNING FIELD-SYMBOL(<finding>).
      mo_scorer->score_finding( CHANGING cs_finding = <finding> ).
    ENDLOOP.

    " Duplikate entfernen, nach Score sortieren
    deduplicate( CHANGING ct_findings = rt_findings ).
    SORT rt_findings BY score DESCENDING prioritaet.
  ENDMETHOD.


  METHOD deduplicate.
    " Gleiches Finding (gleicher Typ + gleicher sql_hash) nur einmal behalten.
    " Falls kein Hash: gleicher Typ + Programm + Tabelle.
    SORT ct_findings BY finding_type sql_hash programm tabname score DESCENDING.

    DATA lv_prev_key TYPE string.
    DATA lt_result   TYPE zif_pa_detector=>tt_findings.

    LOOP AT ct_findings ASSIGNING FIELD-SYMBOL(<f>).
      DATA(lv_key) = COND string(
        WHEN <f>-sql_hash IS NOT INITIAL
        THEN |{ <f>-finding_type }|{ <f>-sql_hash }|
        ELSE |{ <f>-finding_type }|{ <f>-programm }|{ <f>-tabname }| ).

      IF lv_key <> lv_prev_key.
        APPEND <f> TO lt_result.
        lv_prev_key = lv_key.
      ENDIF.
    ENDLOOP.

    ct_findings = lt_result.
  ENDMETHOD.

ENDCLASS.
