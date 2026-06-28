"--------------------------------------------------------------------
" ZCL_PA_OUTPUT_ALV – ALV-Ausgabe der Performance-Findings
"
" Aufbau:
"   1. Management-Summary (WRITE-Block als Kopf)
"   2. ALV-Grid mit Ampelfarben je Priorität
"   3. Doppelklick → Detail-Popup (SQL + Maßnahme vollständig)
"--------------------------------------------------------------------
CLASS zcl_pa_output_alv DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS display
      IMPORTING
        it_findings TYPE zif_pa_detector=>tt_findings
        is_session  TYPE zpa_trace_session.

  PRIVATE SECTION.
    " ALV-Ausgabetabelle (Findings + Farb- und Icon-Felder)
    TYPES: BEGIN OF ty_alv_row,
             " Ampel / Farbe
             traffic_light  TYPE c LENGTH 1,   " 1=Rot 2=Gelb 3=Grün
             row_color      TYPE lvc_s_scol,
             " Klassifikation
             prioritaet     TYPE zpa_prioritaet,
             score          TYPE abap.int1,
             kategorie      TYPE zpa_kategorie,
             finding_type   TYPE zpa_finding_type,
             " Fundstelle
             programm       TYPE ptc_program_name,
             tabname        TYPE tabname,
             " Kennzahlen
             laufzeit_sek   TYPE p LENGTH 8 DECIMALS 3,
             anzahl_exec    TYPE abap.int4,
             datenmenge     TYPE abap.int4,
             " Bewertung
             optim_hebel    TYPE zpa_opt_hebel,
             is_custom_code TYPE abap_bool,
             " Kurzinfo
             empf_kurz      TYPE abap.char(80),
             " Navigation
             finding_id     TYPE sysuuid_x16,
             sql_kurzform   TYPE abap.char(200),
           END OF ty_alv_row.

    TYPES tt_alv TYPE STANDARD TABLE OF ty_alv_row WITH DEFAULT KEY.

    DATA mt_alv      TYPE tt_alv.
    DATA mt_findings TYPE zif_pa_detector=>tt_findings.

    METHODS write_summary
      IMPORTING
        it_findings TYPE zif_pa_detector=>tt_findings
        is_session  TYPE zpa_trace_session.

    METHODS prepare_alv_data
      IMPORTING
        it_findings    TYPE zif_pa_detector=>tt_findings
      RETURNING
        VALUE(rt_rows) TYPE tt_alv.

    METHODS get_row_color
      IMPORTING
        iv_prioritaet  TYPE zpa_prioritaet
      RETURNING
        VALUE(rv_color) TYPE lvc_s_scol.

    METHODS get_traffic_light
      IMPORTING
        iv_prioritaet  TYPE zpa_prioritaet
      RETURNING
        VALUE(rv_light) TYPE c LENGTH 1.

    METHODS build_fieldcat
      RETURNING VALUE(rt_fcat) TYPE lvc_t_fcat.

    METHODS build_layout
      RETURNING VALUE(rs_layout) TYPE lvc_s_layo.

    METHODS on_double_click
      FOR EVENT double_click OF cl_gui_alv_grid
      IMPORTING e_row e_column sender.

    METHODS show_detail_popup
      IMPORTING is_row TYPE ty_alv_row.

ENDCLASS.

CLASS zcl_pa_output_alv IMPLEMENTATION.

  METHOD display.
    mt_findings = it_findings.

    " 1. Zusammenfassung als WRITE-Kopf
    write_summary( it_findings = it_findings
                   is_session  = is_session ).

    " 2. ALV-Daten aufbereiten
    DATA(lt_rows) = prepare_alv_data( it_findings ).

    IF lt_rows IS INITIAL.
      WRITE: / 'Keine Findings für die gewählten Filterkriterien gefunden.'.
      RETURN.
    ENDIF.

    " 3. ALV in Fullscreen-Container anzeigen
    DATA lo_container TYPE REF TO cl_gui_custom_container.
    DATA lo_grid      TYPE REF TO cl_gui_alv_grid.

    " Fullscreen-Modus: cl_gui_container=>screen0 als Parent
    CREATE OBJECT lo_grid
      EXPORTING
        i_parent = cl_gui_container=>screen0.

    " Event-Handler registrieren
    SET HANDLER me->on_double_click FOR lo_grid.

    lo_grid->set_table_for_first_display(
      EXPORTING
        is_layout       = build_layout( )
        i_save          = 'A'
        i_default       = 'X'
      CHANGING
        it_outtab       = lt_rows
        it_fieldcatalog = build_fieldcat( ) ).

    mt_alv = lt_rows.

    " Schleife für Benutzerinteraktion
    CALL SCREEN 100.
  ENDMETHOD.


  METHOD write_summary.
    " Statistiken
    DATA lv_krit TYPE i.
    DATA lv_hoch TYPE i.
    DATA lv_mitt TYPE i.
    DATA lv_nied TYPE i.
    DATA lv_hinw TYPE i.
    DATA lv_custom TYPE i.

    LOOP AT it_findings INTO DATA(ls_f).
      CASE ls_f-prioritaet.
        WHEN 'KRITISCH'. lv_krit += 1.
        WHEN 'HOCH'.     lv_hoch += 1.
        WHEN 'MITTEL'.   lv_mitt += 1.
        WHEN 'NIEDRIG'.  lv_nied += 1.
        WHEN 'HINWEIS'.  lv_hinw += 1.
      ENDCASE.
      IF ls_f-is_custom_code = abap_true. lv_custom += 1. ENDIF.
    ENDLOOP.

    WRITE: /1 '════════════════════════════════════════════════════════════════'.
    WRITE: /1  'ST05 PERFORMANCE ANALYSE'.
    WRITE: /1 |Session : { is_session-session_name }|.
    WRITE: /1 |System  : { is_session-system_id } { is_session-umgebung } | &&
              |{ is_session-modul }|.
    WRITE: /1 |Erfasst : { is_session-erfasst_am DATE = USER } | &&
              |{ is_session-erfasst_um TIME = USER } | &&
              |von { is_session-erfasst_von }|.
    WRITE: /1 '────────────────────────────────────────────────────────────────'.
    WRITE: /1 |KRITISCH: { lv_krit WIDTH = 4 }| COLOR COL_NEGATIVE.
    WRITE:    |  HOCH: { lv_hoch WIDTH = 4 }|   COLOR COL_TOTAL.
    WRITE:    |  MITTEL: { lv_mitt WIDTH = 4 }|  COLOR COL_KEY.
    WRITE:    |  NIEDRIG: { lv_nied WIDTH = 4 }| COLOR COL_POSITIVE.
    WRITE:    |  HINWEIS: { lv_hinw WIDTH = 4 }|.
    WRITE: /1 |Gesamt: { lines( it_findings ) } Findings | &&
              |– davon Custom Code: { lv_custom }|.
    WRITE: /1 '════════════════════════════════════════════════════════════════'.
    SKIP.
  ENDMETHOD.


  METHOD prepare_alv_data.
    LOOP AT it_findings INTO DATA(ls_f).
      DATA ls_row TYPE ty_alv_row.

      ls_row-finding_id    = ls_f-finding_id.
      ls_row-prioritaet    = ls_f-prioritaet.
      ls_row-score         = ls_f-score.
      ls_row-kategorie     = ls_f-kategorie.
      ls_row-finding_type  = ls_f-finding_type.
      ls_row-programm      = ls_f-programm.
      ls_row-tabname       = ls_f-tabname.
      ls_row-laufzeit_sek  = ls_f-laufzeit_us / 1000000.
      ls_row-anzahl_exec   = ls_f-anzahl_exec.
      ls_row-datenmenge    = ls_f-datenmenge.
      ls_row-optim_hebel   = ls_f-optim_hebel.
      ls_row-is_custom_code = ls_f-is_custom_code.
      ls_row-sql_kurzform  = ls_f-sql_kurzform.

      " Maßnahme kürzen für Tabellenzeile
      ls_row-empf_kurz = substring( val = ls_f-empf_massnahme
                                    len = MIN( strlen( ls_f-empf_massnahme ), 80 ) ).

      " Ampel und Zeilenfarbe
      ls_row-traffic_light = get_traffic_light( ls_f-prioritaet ).
      ls_row-row_color     = get_row_color( ls_f-prioritaet ).

      APPEND ls_row TO rt_rows.
    ENDLOOP.
  ENDMETHOD.


  METHOD get_traffic_light.
    rv_light = SWITCH #( iv_prioritaet
      WHEN 'KRITISCH' THEN '1'   " Rot
      WHEN 'HOCH'     THEN '2'   " Gelb
      WHEN 'MITTEL'   THEN '2'   " Gelb
      ELSE                 '3' ).  " Grün
  ENDMETHOD.


  METHOD get_row_color.
    rv_color-fname = 'ROW_COLOR'.
    rv_color-color-col = SWITCH #( iv_prioritaet
      WHEN 'KRITISCH' THEN '6'   " Rot (COL_NEGATIVE)
      WHEN 'HOCH'     THEN '3'   " Gelb (COL_TOTAL)
      WHEN 'MITTEL'   THEN '5'   " Blau (COL_KEY)
      WHEN 'NIEDRIG'  THEN '5'
      ELSE                 '1' ).
    rv_color-color-int = '0'.
    rv_color-color-inv = '0'.
  ENDMETHOD.


  METHOD build_fieldcat.
    DATA ls_fc TYPE lvc_s_fcat.

    " Ampel
    CLEAR ls_fc.
    ls_fc-fieldname = 'TRAFFIC_LIGHT'.
    ls_fc-coltext   = 'Ampel'.
    ls_fc-outputlen = 5.
    ls_fc-datatype  = 'CHAR'.
    ls_fc-icon      = abap_true.
    APPEND ls_fc TO rt_fcat.

    " Priorität
    CLEAR ls_fc.
    ls_fc-fieldname = 'PRIORITAET'.
    ls_fc-coltext   = 'Priorität'.
    ls_fc-outputlen = 10.
    APPEND ls_fc TO rt_fcat.

    " Score
    CLEAR ls_fc.
    ls_fc-fieldname = 'SCORE'.
    ls_fc-coltext   = 'Score'.
    ls_fc-outputlen = 6.
    APPEND ls_fc TO rt_fcat.

    " Kategorie
    CLEAR ls_fc.
    ls_fc-fieldname = 'KATEGORIE'.
    ls_fc-coltext   = 'Kategorie'.
    ls_fc-outputlen = 15.
    APPEND ls_fc TO rt_fcat.

    " Finding-Typ
    CLEAR ls_fc.
    ls_fc-fieldname = 'FINDING_TYPE'.
    ls_fc-coltext   = 'Typ'.
    ls_fc-outputlen = 15.
    APPEND ls_fc TO rt_fcat.

    " Programm
    CLEAR ls_fc.
    ls_fc-fieldname = 'PROGRAMM'.
    ls_fc-coltext   = 'Programm'.
    ls_fc-outputlen = 25.
    APPEND ls_fc TO rt_fcat.

    " Tabelle
    CLEAR ls_fc.
    ls_fc-fieldname = 'TABNAME'.
    ls_fc-coltext   = 'Tabelle/CDS'.
    ls_fc-outputlen = 20.
    APPEND ls_fc TO rt_fcat.

    " Laufzeit
    CLEAR ls_fc.
    ls_fc-fieldname = 'LAUFZEIT_SEK'.
    ls_fc-coltext   = 'Laufzeit (Sek)'.
    ls_fc-outputlen = 14.
    ls_fc-decimals  = '3'.
    APPEND ls_fc TO rt_fcat.

    " Ausführungen
    CLEAR ls_fc.
    ls_fc-fieldname = 'ANZAHL_EXEC'.
    ls_fc-coltext   = 'Ausführungen'.
    ls_fc-outputlen = 12.
    APPEND ls_fc TO rt_fcat.

    " Datenmenge
    CLEAR ls_fc.
    ls_fc-fieldname = 'DATENMENGE'.
    ls_fc-coltext   = 'Datensätze'.
    ls_fc-outputlen = 12.
    APPEND ls_fc TO rt_fcat.

    " Optimierungshebel
    CLEAR ls_fc.
    ls_fc-fieldname = 'OPTIM_HEBEL'.
    ls_fc-coltext   = 'Hebel'.
    ls_fc-outputlen = 8.
    APPEND ls_fc TO rt_fcat.

    " Custom Code
    CLEAR ls_fc.
    ls_fc-fieldname = 'IS_CUSTOM_CODE'.
    ls_fc-coltext   = 'Custom'.
    ls_fc-outputlen = 7.
    ls_fc-checkbox  = abap_true.
    APPEND ls_fc TO rt_fcat.

    " Maßnahme
    CLEAR ls_fc.
    ls_fc-fieldname = 'EMPF_KURZ'.
    ls_fc-coltext   = 'Empfohlene Maßnahme'.
    ls_fc-outputlen = 50.
    APPEND ls_fc TO rt_fcat.

    " Finding-ID (technisch, ausgeblendet für Drill-Down)
    CLEAR ls_fc.
    ls_fc-fieldname = 'FINDING_ID'.
    ls_fc-tech      = abap_true.
    ls_fc-no_out    = abap_true.
    APPEND ls_fc TO rt_fcat.
  ENDMETHOD.


  METHOD build_layout.
    rs_layout-zebra        = abap_true.      " Zebra-Streifen
    rs_layout-cwidth_opt   = abap_true.      " Spaltenbreite optimieren
    rs_layout-info_fname   = 'ROW_COLOR'.    " Zeilenfarbe
    rs_layout-excp_fname   = 'TRAFFIC_LIGHT'. " Ampel-Spalte
    rs_layout-excp_led     = abap_true.
    rs_layout-grid_title   = 'ST05 Performance Findings – Doppelklick für Details'.
    rs_layout-col_opt      = abap_true.
  ENDMETHOD.


  METHOD on_double_click.
    READ TABLE mt_alv INDEX e_row-index INTO DATA(ls_row).
    IF sy-subrc = 0.
      show_detail_popup( ls_row ).
    ENDIF.
  ENDMETHOD.


  METHOD show_detail_popup.
    " Vollständige Details aus ZPA_FINDING lesen
    DATA ls_finding TYPE zpa_finding.

    SELECT SINGLE FROM zpa_finding
      FIELDS *
      WHERE mandt      = @sy-mandt
        AND finding_id = @is_row-finding_id
      INTO @ls_finding.

    IF sy-subrc <> 0. RETURN. ENDIF.

    " Popup mit vollständiger Information aufbauen
    DATA lt_lines TYPE STANDARD TABLE OF tline WITH DEFAULT KEY.
    DATA ls_line  TYPE tline.

    DEFINE append_line.
      ls_line-tdformat = &1.
      ls_line-tdline   = &2.
      APPEND ls_line TO lt_lines.
    END-OF-DEFINITION.

    append_line '/' '════════════════════════════════════════════════'.
    append_line 'B' |{ ls_finding-finding_type } – { ls_finding-prioritaet } (Score { ls_finding-score })|.
    append_line '/' '════════════════════════════════════════════════'.
    append_line ' ' ' '.
    append_line 'U' 'Fundstelle'.
    append_line ' ' |  Programm  : { ls_finding-programm }|.
    append_line ' ' |  Tabelle   : { ls_finding-tabname }|.
    append_line ' ' |  Laufzeit  : { ls_finding-laufzeit_us / 1000000 } Sek|.
    append_line ' ' |  Ausführungen: { ls_finding-anzahl_exec }|.
    append_line ' ' |  Datensätze: { ls_finding-datenmenge }|.
    append_line ' ' |  Custom    : { COND #( WHEN ls_finding-is_custom_code = abap_true THEN 'Ja' ELSE 'Nein' ) }|.
    append_line ' ' ' '.
    append_line 'U' 'SQL-Statement'.
    append_line ' ' ls_finding-sql_kurzform.
    append_line ' ' ' '.
    append_line 'U' 'Technische Ursache'.
    append_line ' ' ls_finding-technische_ursache.
    append_line ' ' ' '.
    append_line 'U' 'Fachliche Einschätzung'.
    append_line ' ' ls_finding-fachliche_einsch.
    append_line ' ' ' '.
    append_line 'U' 'Empfohlene Maßnahme'.
    append_line '*' ls_finding-empf_massnahme.
    append_line ' ' ' '.
    append_line ' ' |Optimierungshebel: { ls_finding-optim_hebel }|.

    CALL FUNCTION 'RSPO_R_TEXTBOX'
      EXPORTING
        title        = |Detail: { ls_finding-finding_type }|
        head_line    = |{ ls_finding-prioritaet } – { ls_finding-programm } / { ls_finding-tabname }|
      TABLES
        text_lines   = lt_lines.
  ENDMETHOD.

ENDCLASS.
