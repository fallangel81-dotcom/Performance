"--------------------------------------------------------------------
" ZCL_PA_SRC_PTC
" Connector: Gesicherte ST05-Traces aus PTC_DIRECTORY lesen
"
" Voraussetzung: Trace wurde in ST05 mit "Sichern" (nicht Export)
"               gespeichert → Eintrag in PTC_DIRECTORY vorhanden
"
" Offene Klärung: Wie GUID an CL_ST05_TRACE_DISPLAY_M übergeben wird
"   → GET_MODEL-Parameter prüfen (vermutlich über CL_PTC_M-Basis)
"   → Alternativ: SET_WP_TABLE oder eigene SET_GUID-Methode
"--------------------------------------------------------------------
CLASS zcl_pa_src_ptc DEFINITION
  PUBLIC FINAL CREATE PUBLIC
  INTERFACES zif_pa_data_source.

  PUBLIC SECTION.
    METHODS constructor
      IMPORTING
        iv_trace_type TYPE st05_trace_type DEFAULT 'SQL'.

  PRIVATE SECTION.
    DATA mv_trace_type TYPE st05_trace_type.

    " Quelltypen für IMPORT_TRACE->source (CHAR2)
    " Werte anhand ST05-Quellcode verifizieren (LPTC_APIU01 / LST05_INTU11)
    CONSTANTS:
      c_source_db   TYPE char2 VALUE 'DB',
      c_source_file TYPE char2 VALUE 'FE'.

    METHODS load_directory
      IMPORTING
        is_criteria   TYPE zpa_fetch_criteria
      RETURNING
        VALUE(rt_dir) TYPE STANDARD TABLE OF ptc_directory.

    METHODS fetch_trace_records
      IMPORTING
        is_dir_entry      TYPE ptc_directory
      RETURNING
        VALUE(rt_main)    TYPE st05_main_record_table
      RAISING
        zcx_pa_import_error.

    METHODS map_to_trace_items
      IMPORTING
        it_main        TYPE st05_main_record_table
        iv_session_id  TYPE zpa_session_id
        is_dir_entry   TYPE ptc_directory
      RETURNING
        VALUE(rt_items) TYPE zpa_tt_trace_item.

    METHODS derive_tabname
      IMPORTING
        iv_object      TYPE st05_objects   " STRING, ggf. mehrere Tabellen (JOIN)
        iv_operation   TYPE st05_operation
      RETURNING
        VALUE(rv_tab)  TYPE tabname.

    METHODS check_has_where
      IMPORTING
        iv_statement   TYPE st05_statement
      RETURNING
        VALUE(rv_flag) TYPE zpa_boolean.
ENDCLASS.


CLASS zcl_pa_src_ptc IMPLEMENTATION.

  METHOD constructor.
    mv_trace_type = iv_trace_type.
  ENDMETHOD.


  METHOD zif_pa_data_source~get_source_type.
    rv_type = 'PTC'.
  ENDMETHOD.


  METHOD zif_pa_data_source~fetch.
    DATA lt_dir TYPE STANDARD TABLE OF ptc_directory.
    lt_dir = load_directory( is_criteria ).

    IF lt_dir IS INITIAL.
      RETURN.
    ENDIF.

    LOOP AT lt_dir INTO DATA(ls_dir).
      TRY.
          DATA(lt_main) = fetch_trace_records( ls_dir ).

          APPEND LINES OF map_to_trace_items(
            it_main       = lt_main
            iv_session_id = is_criteria-session_id
            is_dir_entry  = ls_dir ) TO rt_items.

        CATCH zcx_pa_import_error INTO DATA(lx).
          " Einzelnen fehlerhaften Trace überspringen
          MESSAGE lx TYPE 'W'.
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.


  METHOD load_directory.
    " TYPE-Wert für ST05 SQL-Traces in SE16/PTC_DIRECTORY ermitteln
    " Kandidaten: 'ST05', 'SQL', 'SQLT' – mit SE16 auf vorhandene Traces prüfen
    SELECT FROM ptc_directory
      FIELDS *
      WHERE mandt      =  sy-mandt
        AND type       =  'ST05'
        AND start_date >= @is_criteria-date_from
        AND start_date <= @is_criteria-date_to
        AND ( owner    =  @is_criteria-username
           OR @is_criteria-username IS INITIAL )
      ORDER BY start_date DESCENDING, start_time DESCENDING
      INTO TABLE @rt_dir
      UP TO 100 ROWS.
  ENDMETHOD.


  METHOD fetch_trace_records.
    DATA lo_model TYPE REF TO cl_st05_trace_display_m.

    " Modell erzeugen – GET_MODEL-Parameter mit SE24 prüfen:
    " Vermutlich: GET_MODEL( i_guid = is_dir_entry-guid
    "                        i_instance = is_dir_entry-instance_name )
    " Fallback falls parameterlos: GUID wird via SET_* gesetzt
    lo_model = cl_st05_trace_display_m=>get_model( ).

    TRY.
        " record_number_table leer = alle Sätze laden
        " Einzelne Sätze selektierbar via INT10-Nummern aus PTC_RECORD_NUMBER
        DATA lt_rec_nr TYPE ptc_record_numbers.  " leer → kompletter Trace
        rt_main = lo_model->import_trace(
          source               = c_source_db
          record_number_table  = lt_rec_nr
          trace_type           = mv_trace_type ).

        lo_model->free_model( ).

      CATCH cx_root INTO DATA(lx).
        lo_model->free_model( ).
        RAISE EXCEPTION TYPE zcx_pa_import_error
          EXPORTING
            previous = lx
            mv_info  = |GUID: { is_dir_entry-guid } – { lx->get_text( ) }|.
    ENDTRY.
  ENDMETHOD.


  METHOD map_to_trace_items.
    DATA lv_seq TYPE zpa_item_seq VALUE 1.

    LOOP AT it_main INTO DATA(ls_rec).

      " SQL-Trace-Sätze filtern (BUF, RFC etc. separat behandeln)
      CHECK ls_rec-trace_type = 'SQL ' OR ls_rec-trace_type = mv_trace_type.

      DATA ls_item TYPE zpa_trace_item.

      "-----------------------------------------------------------------
      " Identifikation
      "-----------------------------------------------------------------
      ls_item-session_id   = iv_session_id.
      ls_item-item_seq     = lv_seq.

      "-----------------------------------------------------------------
      " Laufzeit – alle drei HANA-Dimensionen sichern
      "-----------------------------------------------------------------
      ls_item-laufzeit_us        = ls_rec-duration.              " Gesamtlaufzeit µs
      ls_item-hana_proc_time_us  = ls_rec-hana_processing_time. " HANA-Verarbeitung µs
      ls_item-hana_cpu_time_us   = ls_rec-hana_cpu_time.        " HANA-CPU µs
      ls_item-hana_max_memory_kb = ls_rec-hana_max_memory.      " HANA Speicher kB

      "-----------------------------------------------------------------
      " SQL-Statement
      " STATEMENT_WITH_NAMES: SQL mit Feldnamen (kein Datenwert → sicher speichern)
      " STATEMENT_WITH_VALUES: SQL mit echten Werten (für Duplikat-Erkennung)
      "-----------------------------------------------------------------
      ls_item-sql_text     = ls_rec-statement_with_names.
      ls_item-sql_hash     = ls_rec-hana_statement_hash.  " Fertig von SAP/HANA geliefert!

      "-----------------------------------------------------------------
      " Tabelle / Objekt
      " OBJECT ist STRING, bei JOINs ggf. mehrere Tabellen kommasepariert
      "-----------------------------------------------------------------
      ls_item-tabname      = derive_tabname(
        iv_object    = ls_rec-object
        iv_operation = ls_rec-operation ).
      ls_item-objects_raw  = ls_rec-object.               " Volltext für JOIN-Analyse

      "-----------------------------------------------------------------
      " Operation und Rückkehrcode
      "-----------------------------------------------------------------
      ls_item-stmt_type    = ls_rec-operation.             " SELECT/INSERT/UPDATE/DELETE/OPEN CURSOR
      ls_item-return_code  = ls_rec-return_code.

      "-----------------------------------------------------------------
      " Datenmenge
      "-----------------------------------------------------------------
      ls_item-records_fetched = ls_rec-number_of_rows.
      ls_item-array_size      = ls_rec-array_size.

      "-----------------------------------------------------------------
      " Kontext: Programm, Transaktion, User
      "-----------------------------------------------------------------
      ls_item-program_name = ls_rec-program.
      ls_item-transaction  = ls_rec-transaction.
      ls_item-user_name    = ls_rec-user_name.
      ls_item-wp_id        = ls_rec-wp_id.
      ls_item-wp_type      = ls_rec-wp_type.

      " End-to-End-Kontext (für systemübergreifende Analyse, Phase 3)
      ls_item-epp_root_id  = ls_rec-epp_root_id.

      "-----------------------------------------------------------------
      " Zeitstempel aus Verzeichniseintrag (Trace-Start)
      "-----------------------------------------------------------------
      ls_item-trace_date   = is_dir_entry-start_date.
      ls_item-trace_time   = is_dir_entry-start_time.
      ls_item-instance_nm  = ls_rec-instance_name.

      "-----------------------------------------------------------------
      " Abgeleitete Felder für Analyse-Engine
      "-----------------------------------------------------------------
      ls_item-has_where    = check_has_where( ls_rec-statement_with_names ).

      " Custom Code: Z* / Y* Namensraum
      IF ls_rec-program(1) = 'Z' OR ls_rec-program(1) = 'Y'.
        ls_item-is_custom_code = abap_true.
      ENDIF.

      APPEND ls_item TO rt_items.
      lv_seq += 1.
    ENDLOOP.
  ENDMETHOD.


  METHOD derive_tabname.
    " OBJECT enthält bei einfachem SELECT: "BKPF"
    " Bei JOIN: "BKPF,BSEG" oder "BKPF JOIN BSEG ON ..."
    " Erste Tabelle als Haupttabelle, Rest in objects_raw für JOIN-Erkennung
    DATA lv_obj TYPE string.
    lv_obj = iv_object.
    CONDENSE lv_obj.

    " Komma oder Leerzeichen als Trennzeichen
    DATA(lv_first) = substring_before( val = lv_obj sub = ',' ).
    IF lv_first IS INITIAL.
      lv_first = substring_before( val = lv_obj sub = ' ' ).
    ENDIF.
    IF lv_first IS INITIAL.
      lv_first = lv_obj.
    ENDIF.

    rv_tab = CONV tabname( lv_first ).
  ENDMETHOD.


  METHOD check_has_where.
    DATA(lv_upper) = to_upper( iv_statement ).
    IF lv_upper CS ' WHERE ' OR lv_upper CS `\nWHERE `.
      rv_flag = abap_true.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
