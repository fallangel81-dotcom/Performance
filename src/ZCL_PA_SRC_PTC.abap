"--------------------------------------------------------------------
" ZCL_PA_SRC_PTC
" Connector: Gesicherte ST05-Traces aus PTC_DIRECTORY lesen
"
" Ablauf:
"   1. PTC_DIRECTORY nach Selektionskriterien abfragen
"   2. Je Eintrag: Filter präzise auf Owner/Instanz/Zeit setzen
"   3. CL_PTC_M=>GET_MODEL + IMPORT_TRACE( source='DB' )
"   4. Ergebnis auf ZPA_TRACE_ITEM mappen
"
" Voraussetzung: Trace wurde in ST05 mit "Sichern" gespeichert
"               (nicht "Exportieren")
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

    " source-Parameter von IMPORT_TRACE (CHAR2)
    " 'DB' = aus PTC_DIRECTORY (gesicherter Trace)
    " 'FE' = Front-End-Datei (manueller Upload – anderer Connector)
    CONSTANTS c_source_db TYPE char2 VALUE 'DB'.

    METHODS load_directory
      IMPORTING
        is_criteria   TYPE zpa_fetch_criteria
      RETURNING
        VALUE(rt_dir) TYPE STANDARD TABLE OF ptc_directory.

    METHODS build_filter
      IMPORTING
        is_dir        TYPE ptc_directory
      RETURNING
        VALUE(ro_filter) TYPE REF TO cl_st05_trace_filter_c.

    METHODS fetch_trace_records
      IMPORTING
        is_dir_entry   TYPE ptc_directory
      RETURNING
        VALUE(rt_main) TYPE st05_main_record_table
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
        iv_object      TYPE st05_objects
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
    DATA(lt_dir) = load_directory( is_criteria ).
    CHECK lt_dir IS NOT INITIAL.

    LOOP AT lt_dir INTO DATA(ls_dir).
      TRY.
          APPEND LINES OF map_to_trace_items(
            it_main       = fetch_trace_records( ls_dir )
            iv_session_id = is_criteria-session_id
            is_dir_entry  = ls_dir ) TO rt_items.

        CATCH zcx_pa_import_error INTO DATA(lx).
          MESSAGE lx TYPE 'W'.
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.


  METHOD load_directory.
    " TYPE-Wert mit SE16 auf einem System mit gesicherten Traces prüfen:
    " SELECT DISTINCT type FROM ptc_directory → zeigt reale Werte
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


  METHOD build_filter.
    " CL_ST05_TRACE_FILTER_C kapselt alle Filterbedingungen.
    " Wir setzen den Filter so eng wie möglich auf genau einen
    " PTC_DIRECTORY-Eintrag, damit IMPORT_TRACE exakt diesen lädt.
    "
    " Offene Klärung: genaue SET_*-Methoden von CL_ST05_TRACE_FILTER_C
    " prüfen (SE24) – typische SAP-Muster:
    "   SET_USER_RANGE / SET_TRACE_PERIOD / SET_INSTANCE
    " Alternativ: direkte Attribut-Zuweisung falls kein SET_* vorhanden

    CREATE OBJECT ro_filter.

    " Zeitraum: genau der Startzeitpunkt des gesicherten Trace
    " (Endzeit = Startzeit + kleines Delta, falls nötig)
    ro_filter->set_trace_period(
      i_date_from     = is_dir-start_date
      i_time_from     = is_dir-start_time
      i_date_to       = is_dir-start_date
      i_time_to       = is_dir-start_time
      i_instance_name = is_dir-instance_name ).

    " Benutzer: Ersteller des gesicherten Trace
    ro_filter->set_user_range(
      i_username = is_dir-owner ).

    " Trace-Typ: SQL / RFC / BUF / HTTP etc.
    ro_filter->set_trace_types(
      i_trace_types = mv_trace_type ).
  ENDMETHOD.


  METHOD fetch_trace_records.
    " 1. Modell via generischer Factory der Basisklasse erzeugen
    DATA lo_ptc   TYPE REF TO cl_ptc_m.
    DATA lo_model TYPE REF TO cl_st05_trace_display_m.

    lo_ptc = cl_ptc_m=>get_model(
      model_class_name = 'CL_ST05_TRACE_DISPLAY_M' ).

    TRY.
        lo_model ?= lo_ptc.
      CATCH cx_sy_move_cast_error INTO DATA(lx_cast).
        RAISE EXCEPTION TYPE zcx_pa_import_error
          EXPORTING previous = lx_cast
                    mv_info  = 'Downcast CL_PTC_M → CL_ST05_TRACE_DISPLAY_M fehlgeschlagen'.
    ENDTRY.

    TRY.
        " 2. Filter präzise auf diesen PTC_DIRECTORY-Eintrag setzen
        lo_model->set_filter( build_filter( is_dir_entry ) ).

        " 3. Record-Prozessoren vorbereiten (interne SAP-Verarbeitung)
        lo_model->set_record_processors( ).

        " 4. Trace aus PTC_DIRECTORY laden
        "    record_number_table leer = alle Sätze
        "    source = 'DB'            = aus Datenbank (PTC_DIRECTORY.CONTENT)
        DATA lt_rec_nr TYPE ptc_record_numbers.  " leer → alle Sätze

        rt_main = lo_model->import_trace(
          source              = c_source_db
          record_number_table = lt_rec_nr
          trace_type          = mv_trace_type ).

        lo_model->free_model( ).

      CATCH cx_root INTO DATA(lx).
        lo_model->free_model( ).
        RAISE EXCEPTION TYPE zcx_pa_import_error
          EXPORTING
            previous = lx
            mv_info  = |Owner: { is_dir_entry-owner } | &&
                       |{ is_dir_entry-start_date } { is_dir_entry-start_time }|.
    ENDTRY.
  ENDMETHOD.


  METHOD map_to_trace_items.
    DATA lv_seq TYPE zpa_item_seq VALUE 1.

    LOOP AT it_main INTO DATA(ls_rec).

      " Nur den angefragten Trace-Typ verarbeiten
      CHECK ls_rec-trace_type = mv_trace_type.

      DATA ls_item TYPE zpa_trace_item.

      " --- Identifikation ---
      ls_item-session_id   = iv_session_id.
      ls_item-item_seq     = lv_seq.

      " --- Laufzeit (alle drei HANA-Dimensionen) ---
      ls_item-laufzeit_us        = ls_rec-duration.
      ls_item-hana_proc_time_us  = ls_rec-hana_processing_time.
      ls_item-hana_cpu_time_us   = ls_rec-hana_cpu_time.
      ls_item-hana_max_memory_kb = ls_rec-hana_max_memory.

      " --- SQL-Statement ---
      " STATEMENT_WITH_NAMES: feldbasiert, kein Datenwert → sicher speichern
      " STATEMENT_WITH_VALUES: für Duplikat-Erkennung (Werte vergleichen)
      ls_item-sql_text  = ls_rec-statement_with_names.
      ls_item-sql_hash  = ls_rec-hana_statement_hash.  " von HANA geliefert

      " --- Tabelle / Objekte ---
      " OBJECT ist STRING; bei JOINs mehrere Tabellen (z.B. "BKPF,BSEG")
      ls_item-tabname     = derive_tabname( ls_rec-object ).
      ls_item-objects_raw = ls_rec-object.   " Volltext für JOIN-Erkennung

      " --- Operation ---
      ls_item-stmt_type   = ls_rec-operation.   " SELECT / OPEN CURSOR / INSERT ...

      " --- Datenmenge ---
      ls_item-records_fetched = ls_rec-number_of_rows.
      ls_item-array_size      = ls_rec-array_size.

      " --- Kontext ---
      ls_item-program_name = ls_rec-program.
      ls_item-transaction  = ls_rec-transaction.
      ls_item-user_name    = ls_rec-user_name.
      ls_item-wp_id        = ls_rec-wp_id.
      ls_item-wp_type      = ls_rec-wp_type.
      ls_item-return_code  = ls_rec-return_code.

      " End-to-End-Kontext (Passport, für systemübergreifende Analyse)
      ls_item-epp_root_id = ls_rec-epp_root_id.

      " --- Metadaten aus PTC_DIRECTORY ---
      ls_item-trace_date  = is_dir_entry-start_date.
      ls_item-trace_time  = is_dir_entry-start_time.
      ls_item-instance_nm = ls_rec-instance_name.

      " --- Abgeleitete Felder für Analyse-Engine ---
      ls_item-has_where      = check_has_where( ls_rec-statement_with_names ).
      ls_item-is_custom_code = xsdbool(
        ls_rec-program(1) = 'Z' OR ls_rec-program(1) = 'Y' ).

      APPEND ls_item TO rt_items.
      lv_seq += 1.
    ENDLOOP.
  ENDMETHOD.


  METHOD derive_tabname.
    " OBJECT: "BKPF" → einfacher Zugriff
    "         "BKPF,BSEG" → JOIN, erste Tabelle als Primär
    "         "BKPF JOIN BSEG ON ..." → seltener
    DATA(lv_obj) = CONV string( iv_object ).
    CONDENSE lv_obj.

    " Erstes Token vor Komma oder Leerzeichen
    DATA lv_first TYPE string.
    lv_first = substring_before( val = lv_obj sub = ',' ).
    IF lv_first IS INITIAL.
      lv_first = substring_before( val = lv_obj sub = ' ' ).
    ENDIF.
    IF lv_first IS INITIAL.
      lv_first = lv_obj.
    ENDIF.

    rv_tab = CONV tabname( to_upper( lv_first ) ).
  ENDMETHOD.


  METHOD check_has_where.
    DATA(lv_upper) = to_upper( CONV string( iv_statement ) ).
    rv_flag = xsdbool(
      lv_upper CS ' WHERE '  OR
      lv_upper CP '*' && cl_abap_char_utilities=>newline && 'WHERE *' ).
  ENDMETHOD.

ENDCLASS.
