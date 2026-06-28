*&---------------------------------------------------------------------*
*& Report ZRPA_PERF_ANALYSE
*& ST05 Performance Analyser – Hauptreport
*&---------------------------------------------------------------------*
REPORT zrpa_perf_analyse.

"--------------------------------------------------------------------
" Typen für Selektionsbild
"--------------------------------------------------------------------
TYPES: BEGIN OF ty_ptc_dir_sel,
         guid          TYPE ptc_directory_entry_guid,
         owner         TYPE ptc_directory_entry_owner,
         start_date    TYPE ptc_start_date,
         start_time    TYPE ptc_start_time,
         description   TYPE ptc_directory_entry_descript,
         instance_name TYPE ptc_instance_name,
       END OF ty_ptc_dir_sel.

"--------------------------------------------------------------------
" Selektionsbild
"--------------------------------------------------------------------
SELECTION-SCREEN BEGIN OF BLOCK b_mode WITH FRAME TITLE TEXT-b01.
  PARAMETERS:
    p_new  RADIOBUTTON GROUP grp DEFAULT 'X' USER-COMMAND ugrp,
    p_show RADIOBUTTON GROUP grp.
SELECTION-SCREEN END OF BLOCK b_mode.

" --- Block: Neuer Import aus PTC_DIRECTORY ---
SELECTION-SCREEN BEGIN OF BLOCK b_ptc WITH FRAME TITLE TEXT-b02.
  SELECT-OPTIONS:
    so_date  FOR sy-datum          DEFAULT sy-datum OBLIGATORY,
    so_owner FOR sy-uname.
  PARAMETERS:
    p_name   TYPE abap.char(80),
    p_modul  TYPE abap.char(20),
    p_env    TYPE abap.char(5)     DEFAULT 'PRD'.
SELECTION-SCREEN END OF BLOCK b_ptc.

" --- Block: Vorhandene Session anzeigen ---
SELECTION-SCREEN BEGIN OF BLOCK b_sess WITH FRAME TITLE TEXT-b03.
  PARAMETERS:
    p_sessid TYPE sysuuid_x16.
SELECTION-SCREEN END OF BLOCK b_sess.

" --- Ausgabe ---
SELECTION-SCREEN BEGIN OF BLOCK b_out WITH FRAME TITLE TEXT-b04.
  PARAMETERS:
    p_alv    RADIOBUTTON GROUP out DEFAULT 'X',
    p_excel  RADIOBUTTON GROUP out,
    p_summ   RADIOBUTTON GROUP out.
  SELECT-OPTIONS:
    so_prio  FOR (cl_abap_typedescr=>describe_by_name( 'ZPA_FINDING' )->absolute_name)
             NO INTERVALS,
    so_kat   FOR (cl_abap_typedescr=>describe_by_name( 'ZPA_FINDING' )->absolute_name)
             NO INTERVALS.
SELECTION-SCREEN END OF BLOCK b_out.

"--------------------------------------------------------------------
" Screen-Steuerung: Blöcke ein-/ausblenden je nach Modus
"--------------------------------------------------------------------
AT SELECTION-SCREEN OUTPUT.
  LOOP AT SCREEN.
    CASE screen-group1.
      WHEN 'PTC'.  " Felder im Import-Block
        screen-active = COND #( WHEN p_new = 'X' THEN 1 ELSE 0 ).
      WHEN 'SES'.  " Felder im Session-Block
        screen-active = COND #( WHEN p_show = 'X' THEN 1 ELSE 0 ).
    ENDCASE.
    MODIFY SCREEN.
  ENDLOOP.

AT SELECTION-SCREEN ON p_sessid.
  IF p_show = 'X' AND p_sessid IS INITIAL.
    MESSAGE 'Bitte eine Session-ID angeben.' TYPE 'E'.
  ENDIF.

"--------------------------------------------------------------------
" Hauptprogramm
"--------------------------------------------------------------------
START-OF-SELECTION.

  CASE abap_true.

    WHEN p_new.
      " --- Neuer Import und Analyse ---
      perform_import_and_analyse( ).

    WHEN p_show.
      " --- Vorhandene Session anzeigen ---
      perform_display_session( ).

  ENDCASE.

"--------------------------------------------------------------------
" Formulare
"--------------------------------------------------------------------
FORM perform_import_and_analyse.

  " 1. Passende Traces aus PTC_DIRECTORY ermitteln
  DATA lt_ptc_dir TYPE STANDARD TABLE OF ptc_directory.

  SELECT FROM ptc_directory
    FIELDS *
    WHERE mandt      = @sy-mandt
      AND type       = 'ST05'
      AND start_date IN @so_date
      AND ( owner    IN @so_owner OR @so_owner[] IS INITIAL )
    ORDER BY start_date DESCENDING, start_time DESCENDING
    INTO TABLE @lt_ptc_dir
    UP TO 100 ROWS.

  IF lt_ptc_dir IS INITIAL.
    MESSAGE 'Keine gesicherten ST05-Traces im gewählten Zeitraum gefunden.' TYPE 'S'
            DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  " 2. Session-ID erzeugen
  DATA lv_session_id TYPE sysuuid_x16.
  TRY.
      lv_session_id = cl_system_uuid=>create_uuid_x16_static( ).
    CATCH cx_uuid_error INTO DATA(lx_uuid).
      MESSAGE lx_uuid TYPE 'E'.
      RETURN.
  ENDTRY.

  " 3. Session-Header anlegen
  DATA ls_session TYPE zpa_trace_session.
  ls_session-mandt        = sy-mandt.
  ls_session-session_id   = lv_session_id.
  ls_session-session_name = COND #(
    WHEN p_name IS NOT INITIAL THEN p_name
    ELSE |ST05-Analyse { sy-datum } { sy-uzeit }| ).
  ls_session-trace_source  = 'PTC'.
  ls_session-system_id     = sy-sysid.
  ls_session-umgebung      = p_env.
  ls_session-modul         = p_modul.
  ls_session-trace_date_from = so_date-low.
  ls_session-trace_date_to   = so_date-high.
  ls_session-erfasst_am    = sy-datum.
  ls_session-erfasst_um    = sy-uzeit.
  ls_session-erfasst_von   = sy-uname.
  ls_session-session_status = 'N'.

  " Erste PTC-Metadaten übernehmen (falls nur ein Trace)
  IF lines( lt_ptc_dir ) = 1.
    ls_session-ptc_guid     = lt_ptc_dir[ 1 ]-guid.
    ls_session-ptc_owner    = lt_ptc_dir[ 1 ]-owner.
    ls_session-ptc_instance = lt_ptc_dir[ 1 ]-instance_name.
  ENDIF.

  INSERT zpa_trace_session FROM ls_session.

  " 4. Fortschrittsanzeige
  DATA lv_total TYPE i.
  lv_total = lines( lt_ptc_dir ).

  " 5. Je PTC-Eintrag: Trace-Items importieren
  DATA lt_all_items TYPE STANDARD TABLE OF zpa_trace_item.
  DATA lv_counter   TYPE i VALUE 0.

  LOOP AT lt_ptc_dir INTO DATA(ls_dir).
    lv_counter += 1.
    cl_progress_indicator=>progress_indicate(
      i_text               = |Importiere Trace { lv_counter } von { lv_total }: { ls_dir-description }|
      i_processed          = lv_counter
      i_total              = lv_total
      i_output_immediately = abap_true ).

    " Inhalt aus PTC_DIRECTORY.CONTENT entpacken
    DATA lt_main     TYPE st05_main_record_table.
    DATA lt_value_id TYPE st05_identical_record_table.
    DATA lt_struct_id TYPE st05_identical_record_table.
    DATA lt_tbl_acc  TYPE st05_table_access_record_table.
    DATA lt_callstk  TYPE st05_kernel_call_stack.

    TRY.
        IMPORT
          main_record_table         = lt_main
          value_id_record_table     = lt_value_id
          structure_id_record_table = lt_struct_id
          table_access_record_table = lt_tbl_acc
          kernel_call_stack         = lt_callstk
        FROM DATA BUFFER ls_dir-content.

      CATCH cx_root INTO DATA(lx_import).
        MESSAGE |Trace { ls_dir-description }: Import fehlgeschlagen – { lx_import->get_text( ) }|
                TYPE 'W'.
        CONTINUE.
    ENDTRY.

    " Trace-Items erzeugen und speichern
    DATA lo_src TYPE REF TO zcl_pa_src_ptc.
    lo_src = NEW zcl_pa_src_ptc( ).

    DATA(lt_items) = lo_src->map_raw_to_items(
      it_main       = lt_main
      it_value_id   = lt_value_id
      it_struct_id  = lt_struct_id
      it_tbl_access = lt_tbl_acc
      iv_session_id = lv_session_id
      is_dir_entry  = ls_dir ).

    " Laufzahlen je Item setzen und persistieren
    DATA lv_seq TYPE i VALUE 1.
    LOOP AT lt_items ASSIGNING FIELD-SYMBOL(<item>).
      <item>-mandt    = sy-mandt.
      <item>-item_seq = lv_seq.
      lv_seq += 1.
    ENDLOOP.

    INSERT zpa_trace_item FROM TABLE lt_items.
    APPEND LINES OF lt_items TO lt_all_items.
  ENDLOOP.

  " 6. Session-Aggregat aktualisieren
  ls_session-anzahl_statements = lines( lt_all_items ).
  ls_session-session_status    = 'A'.
  MODIFY zpa_trace_session FROM ls_session.

  " 7. Analyse-Engine starten
  DATA lo_analyser TYPE REF TO zcl_pa_analyser.
  lo_analyser = NEW zcl_pa_analyser( ).

  cl_progress_indicator=>progress_indicate(
    i_text               = 'Analysiere Trace-Daten...'
    i_output_immediately = abap_true ).

  DATA(lt_findings) = lo_analyser->analyse(
    iv_session_id = lv_session_id
    it_items      = lt_all_items ).

  " 8. Findings persistieren
  LOOP AT lt_findings ASSIGNING FIELD-SYMBOL(<finding>).
    <finding>-mandt       = sy-mandt.
    <finding>-erstellt_am = sy-datum.
    <finding>-erstellt_um = sy-uzeit.
    <finding>-erstellt_von = sy-uname.
    <finding>-status      = 'O'.
  ENDLOOP.

  INSERT zpa_finding FROM TABLE lt_findings.

  " Session abschließen
  ls_session-anzahl_findings = lines( lt_findings ).
  ls_session-session_status  = 'F'.
  MODIFY zpa_trace_session FROM ls_session.

  " 9. Ausgabe
  perform_display(
    EXPORTING
      iv_session_id = lv_session_id
      it_findings   = lt_findings
      is_session    = ls_session ).

ENDFORM.


FORM perform_display_session.
  " Vorhandene Session laden und anzeigen
  DATA ls_session TYPE zpa_trace_session.

  SELECT SINGLE FROM zpa_trace_session
    FIELDS *
    WHERE mandt      = @sy-mandt
      AND session_id = @p_sessid
    INTO @ls_session.

  IF sy-subrc <> 0.
    MESSAGE 'Session nicht gefunden.' TYPE 'E'.
    RETURN.
  ENDIF.

  DATA lt_findings TYPE STANDARD TABLE OF zpa_finding.

  SELECT FROM zpa_finding
    FIELDS *
    WHERE mandt      = @sy-mandt
      AND session_id = @p_sessid
      AND ( prioritaet IN @so_prio OR @so_prio[] IS INITIAL )
      AND ( kategorie  IN @so_kat  OR @so_kat[]  IS INITIAL )
    ORDER BY score DESCENDING
    INTO TABLE @lt_findings.

  perform_display(
    EXPORTING
      iv_session_id = p_sessid
      it_findings   = lt_findings
      is_session    = ls_session ).

ENDFORM.


FORM perform_display
  USING
    iv_session_id TYPE sysuuid_x16
    it_findings   TYPE STANDARD TABLE
    is_session    TYPE zpa_trace_session.

  CASE abap_true.

    WHEN p_alv.
      DATA lo_alv TYPE REF TO zcl_pa_output_alv.
      lo_alv = NEW zcl_pa_output_alv( ).
      lo_alv->display(
        it_findings = it_findings
        is_session  = is_session ).

    WHEN p_summ.
      " Zusammenfassung als einfache Liste
      perform_summary(
        USING it_findings
              is_session ).

    WHEN p_excel.
      " Excel-Export (Phase 2)
      MESSAGE 'Excel-Export folgt in Phase 2.' TYPE 'I'.

  ENDCASE.

ENDFORM.


FORM perform_summary
  USING
    it_findings TYPE STANDARD TABLE
    is_session  TYPE zpa_trace_session.

  " Einfache Zusammenfassung auf der Konsole
  WRITE: / '═══════════════════════════════════════════════════════════'.
  WRITE: / 'PERFORMANCE ANALYSE – ZUSAMMENFASSUNG'.
  WRITE: / |Session:  { is_session-session_name }|.
  WRITE: / |System:   { is_session-system_id } | { is_session-umgebung }|.
  WRITE: / |Datum:    { is_session-erfasst_am DATE = USER }|.
  WRITE: / '═══════════════════════════════════════════════════════════'.

  " Zählen je Priorität
  DATA lv_krit TYPE i.
  DATA lv_hoch TYPE i.
  DATA lv_mitt TYPE i.
  DATA lv_nied TYPE i.
  DATA lv_hinw TYPE i.

  LOOP AT it_findings INTO DATA(ls_f).
    CASE ls_f-prioritaet.
      WHEN 'KRITISCH'. lv_krit += 1.
      WHEN 'HOCH'.     lv_hoch += 1.
      WHEN 'MITTEL'.   lv_mitt += 1.
      WHEN 'NIEDRIG'.  lv_nied += 1.
      WHEN 'HINWEIS'.  lv_hinw += 1.
    ENDCASE.
  ENDLOOP.

  WRITE: / |KRITISCH: { lv_krit }  HOCH: { lv_hoch }  MITTEL: { lv_mitt }  NIEDRIG: { lv_nied }  HINWEIS: { lv_hinw }|.
  WRITE: / '───────────────────────────────────────────────────────────'.

  " Top 10 Findings
  DATA lv_rank TYPE i VALUE 1.
  LOOP AT it_findings INTO ls_f.
    CHECK lv_rank <= 10.
    WRITE: / |{ lv_rank }. [{ ls_f-prioritaet }] Score { ls_f-score } – { ls_f-finding_type }|.
    WRITE: / |   Programm: { ls_f-programm }  Tabelle: { ls_f-tabname }|.
    WRITE: / |   { ls_f-empf_massnahme }|.
    WRITE: /.
    lv_rank += 1.
  ENDLOOP.

ENDFORM.

"--------------------------------------------------------------------
" Textelemente (in SE38 pflegen)
"--------------------------------------------------------------------
* TEXT-b01 = 'Modus'
* TEXT-b02 = 'Import: ST05-Traces aus Datenbank (PTC_DIRECTORY)'
* TEXT-b03 = 'Vorhandene Analyse anzeigen'
* TEXT-b04 = 'Ausgabe'
