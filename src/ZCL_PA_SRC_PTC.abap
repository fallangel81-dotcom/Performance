"--------------------------------------------------------------------
" ZCL_PA_SRC_PTC
" Connector: Gesicherte ST05-Traces aus PTC_DIRECTORY lesen
"
" Technische Grundlage (aus Analyse von CL_ST05_TRACE_FILTER_C):
"
"   PTC_DIRECTORY.CONTENT ist ein ABAP-Datencluster (EXPORT TO DATA
"   BUFFER COMPRESSION ON) mit exakt diesen Feldern:
"     filter_model_XML, detailed_record_table, main_record_table,
"     value_id_record_table, structure_id_record_table,
"     table_access_record_table, kernel_call_stack,
"     BUF/ENQ/RFC/HTTP/APC/AMC_record_table
"
"   Wir lesen diesen Cluster direkt (IMPORT FROM DATA BUFFER) –
"   das ist robuster als die Klassen-API und benötigt keine
"   Instanziierung von CL_ST05_TRACE_FILTER_M.
"
"   TYPE-Wert in PTC_DIRECTORY = 'ST05' (aus Save_Trace bestätigt).
"--------------------------------------------------------------------
CLASS zcl_pa_src_ptc DEFINITION
  PUBLIC FINAL CREATE PUBLIC
  INTERFACES zif_pa_data_source.

  PUBLIC SECTION.
    METHODS constructor
      IMPORTING
        iv_trace_type TYPE st05_trace_type DEFAULT 'SQL'.

    " Öffentliche Mapping-Methode – wird direkt vom Report aufgerufen
    METHODS map_raw_to_items
      IMPORTING
        it_main        TYPE st05_main_record_table
        it_value_id    TYPE st05_identical_record_table
        it_struct_id   TYPE st05_identical_record_table
        it_tbl_access  TYPE st05_table_access_record_table
        iv_session_id  TYPE sysuuid_x16
        is_dir_entry   TYPE ptc_directory
      RETURNING
        VALUE(rt_items) TYPE zif_pa_detector=>tt_items.

  PRIVATE SECTION.
    DATA mv_trace_type TYPE st05_trace_type.

    TYPES:
      BEGIN OF ty_ptc_content,
        main_records     TYPE st05_main_record_table,
        value_id         TYPE st05_identical_record_table,   " SELECT-in-Loop (wertidentisch)
        structure_id     TYPE st05_identical_record_table,   " Duplikate (strukturidentisch)
        table_access     TYPE st05_table_access_record_table," je Tabelle aggregiert
        kernel_callstack TYPE st05_kernel_call_stack,        " Aufrufhierarchie
      END OF ty_ptc_content.

    METHODS load_directory
      IMPORTING
        is_criteria   TYPE zpa_fetch_criteria
      RETURNING
        VALUE(rt_dir) TYPE STANDARD TABLE OF ptc_directory.

    METHODS read_content
      IMPORTING
        is_dir_entry     TYPE ptc_directory
      RETURNING
        VALUE(rs_content) TYPE ty_ptc_content
      RAISING
        zcx_pa_import_error.

    METHODS map_to_trace_items
      IMPORTING
        is_content     TYPE ty_ptc_content
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

  METHOD map_raw_to_items.
    " Delegiert an die interne Mapping-Methode
    DATA ls_content TYPE ty_ptc_content.
    ls_content-main_records     = it_main.
    ls_content-value_id         = it_value_id.
    ls_content-structure_id     = it_struct_id.
    ls_content-table_access     = it_tbl_access.

    rt_items = map_to_trace_items(
      is_content    = ls_content
      iv_session_id = iv_session_id
      is_dir_entry  = is_dir_entry ).
  ENDMETHOD.

  METHOD zif_pa_data_source~fetch.
    DATA(lt_dir) = load_directory( is_criteria ).
    CHECK lt_dir IS NOT INITIAL.

    LOOP AT lt_dir INTO DATA(ls_dir).
      TRY.
          APPEND LINES OF map_to_trace_items(
            is_content    = read_content( ls_dir )
            iv_session_id = is_criteria-session_id
            is_dir_entry  = ls_dir ) TO rt_items.

        CATCH zcx_pa_import_error INTO DATA(lx).
          MESSAGE lx TYPE 'W'.
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.


  METHOD load_directory.
    " TYPE = 'ST05' bestätigt durch Save_Trace-Quellcode
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


  METHOD read_content.
    " PTC_DIRECTORY.CONTENT direkt lesen (RAWSTRING, komprimiert)
    " Das Feld ist bei SELECT * bereits enthalten – bei großen Traces
    " besser gezielt per GUID selektieren
    DATA lv_content TYPE ptc_directory_entry_content.

    SELECT SINGLE content
      FROM ptc_directory
      WHERE mandt = @sy-mandt
        AND guid  = @is_dir_entry-guid
      INTO @lv_content.

    IF sy-subrc <> 0 OR lv_content IS INITIAL.
      RAISE EXCEPTION TYPE zcx_pa_import_error
        EXPORTING
          mv_info = |GUID { is_dir_entry-guid }: kein Inhalt in PTC_DIRECTORY|.
    ENDIF.

    " Datencluster entpacken – exakt die Feldnamen aus Save_Trace/Export_Trace
    " Nicht benötigte Felder (BUF/ENQ/APC/AMC/filter_model_XML) weglassen
    TRY.
        IMPORT
          main_record_table         = rs_content-main_records
          value_id_record_table     = rs_content-value_id
          structure_id_record_table = rs_content-structure_id
          table_access_record_table = rs_content-table_access
          kernel_call_stack         = rs_content-kernel_callstack
        FROM DATA BUFFER lv_content.

      CATCH cx_root INTO DATA(lx).
        RAISE EXCEPTION TYPE zcx_pa_import_error
          EXPORTING
            previous = lx
            mv_info  = |GUID { is_dir_entry-guid }: IMPORT FROM DATA BUFFER fehlgeschlagen|.
    ENDTRY.
  ENDMETHOD.


  METHOD map_to_trace_items.
    DATA lv_seq TYPE zpa_item_seq VALUE 1.

    "--------------------------------------------------------------------
    " Haupt-Trace-Sätze (main_records) – ein Satz je SQL-Statement
    "--------------------------------------------------------------------
    LOOP AT is_content-main_records INTO DATA(ls_rec).

      " Nur den angefragten Trace-Typ verarbeiten
      CHECK ls_rec-trace_type = mv_trace_type.

      DATA ls_item TYPE zpa_trace_item.

      " --- Identifikation ---
      ls_item-session_id   = iv_session_id.
      ls_item-item_seq     = lv_seq.
      ls_item-data_source  = 'PTC_MAIN'.

      " --- Laufzeit (alle HANA-Dimensionen) ---
      ls_item-laufzeit_us        = ls_rec-duration.
      ls_item-hana_proc_time_us  = ls_rec-hana_processing_time.
      ls_item-hana_cpu_time_us   = ls_rec-hana_cpu_time.
      ls_item-hana_max_memory_kb = ls_rec-hana_max_memory.

      " --- SQL ---
      " STATEMENT_WITH_NAMES: kein Datenwert, sicher persistierbar
      " STATEMENT_WITH_VALUES: für Duplikat-Erkennung via Wertevergleich
      ls_item-sql_text  = ls_rec-statement_with_names.
      ls_item-sql_hash  = ls_rec-hana_statement_hash.  " von HANA geliefert

      " --- Tabelle / Objekt ---
      ls_item-tabname     = derive_tabname( ls_rec-object ).
      ls_item-objects_raw = ls_rec-object.  " Volltext, bei JOIN mehrere Tabellen

      " --- Operation & Status ---
      ls_item-stmt_type  = ls_rec-operation.   " SELECT / OPEN CURSOR / INSERT ...
      ls_item-return_code = ls_rec-return_code.

      " --- Datenmenge ---
      ls_item-records_fetched = ls_rec-number_of_rows.
      ls_item-array_size      = ls_rec-array_size.

      " --- Kontext ---
      ls_item-program_name = ls_rec-program.
      ls_item-transaction  = ls_rec-transaction.
      ls_item-user_name    = ls_rec-user_name.
      ls_item-wp_id        = ls_rec-wp_id.
      ls_item-wp_type      = ls_rec-wp_type.
      ls_item-epp_root_id  = ls_rec-epp_root_id.

      " --- Zeitstempel ---
      ls_item-trace_date   = is_dir_entry-start_date.
      ls_item-trace_time   = is_dir_entry-start_time.
      ls_item-instance_nm  = ls_rec-instance_name.

      " --- Abgeleitete Felder ---
      ls_item-has_where      = check_has_where( ls_rec-statement_with_names ).
      ls_item-is_custom_code = xsdbool(
        ls_rec-program(1) = 'Z' OR ls_rec-program(1) = 'Y' ).

      APPEND ls_item TO rt_items.
      lv_seq += 1.
    ENDLOOP.

    "--------------------------------------------------------------------
    " Value-ID-Sätze (value_id) – gleicher SQL mit gleichen Werten
    " → direkt für AP-01 SELECT-in-Loop und AP-08 Duplikat-Erkennung
    " Wir erzeugen einen SUMMARY-Satz je Gruppe
    "--------------------------------------------------------------------
    "--------------------------------------------------------------------
    " Identische Trace-Sätze (value_id + structure_id) –
    " ST05_IDENTICAL_RECORD enthält beide Typen im selben Tabellentyp.
    " Unterscheidung über:
    "   value_identical     > 0  → exakt gleicher SQL + Werte (AP-01 Loop, AP-08 Duplikat)
    "   structure_identical > 0  → gleiche SQL-Struktur, andere Werte (strukturelle Patterns)
    " record_numbers verlinkt zurück auf die Einzel-Trace-Sätze.
    "--------------------------------------------------------------------
    LOOP AT is_content-value_id INTO DATA(ls_vid).
      CHECK ls_vid-number_of_executions > 1.

      CLEAR ls_item.
      ls_item-session_id      = iv_session_id.
      ls_item-item_seq        = lv_seq.
      ls_item-data_source     = COND #(
        WHEN ls_vid-value_identical > 0 THEN 'PTC_VALUEID'
        ELSE                                 'PTC_STRUCTID' ).
      ls_item-stmt_type       = 'SUMM_IDENT'.
      ls_item-sql_text        = ls_vid-statement_with_names.
      ls_item-sql_hash        = ls_vid-hana_statement_hash.
      ls_item-tabname         = derive_tabname( ls_vid-object ).
      ls_item-objects_raw     = ls_vid-object.

      " Laufzeit: Gesamtzeit = duration (Summe aller Ausführungen)
      ls_item-laufzeit_us     = ls_vid-duration.
      ls_item-anzahl_exec     = ls_vid-number_of_executions.
      ls_item-records_fetched = ls_vid-number_of_rows.

      " Durchschnittswerte – besonders aussagekräftig für Loop-Erkennung
      ls_item-avg_duration_us = ls_vid-duration_per_execution.
      ls_item-avg_rows        = ls_vid-rows_per_execution.

      " HANA-Dimensionen
      ls_item-hana_proc_time_us  = ls_vid-hana_processing_time.
      ls_item-hana_cpu_time_us   = ls_vid-hana_cpu_time.
      ls_item-hana_max_memory_kb = ls_vid-hana_max_memory.

      " Tabelleninfo (für Puffer- und Architektur-Analyse)
      ls_item-buffer_type    = ls_vid-buffer_type.
      ls_item-tabclass       = ls_vid-tabclass.

      ls_item-trace_date     = is_dir_entry-start_date.

      APPEND ls_item TO rt_items.
      lv_seq += 1.
    ENDLOOP.

    " Structure-ID-Sätze separat durchlaufen
    LOOP AT is_content-structure_id INTO DATA(ls_sid).
      CHECK ls_sid-number_of_executions > 1.

      CLEAR ls_item.
      ls_item-session_id      = iv_session_id.
      ls_item-item_seq        = lv_seq.
      ls_item-data_source     = 'PTC_STRUCTID'.
      ls_item-stmt_type       = 'SUMM_STRUCT'.
      ls_item-sql_text        = ls_sid-statement_with_names.
      ls_item-sql_hash        = ls_sid-hana_statement_hash.
      ls_item-tabname         = derive_tabname( ls_sid-object ).
      ls_item-laufzeit_us     = ls_sid-duration.
      ls_item-anzahl_exec     = ls_sid-number_of_executions.
      ls_item-records_fetched = ls_sid-number_of_rows.
      ls_item-avg_duration_us = ls_sid-duration_per_execution.
      ls_item-avg_rows        = ls_sid-rows_per_execution.
      ls_item-trace_date      = is_dir_entry-start_date.

      APPEND ls_item TO rt_items.
      lv_seq += 1.
    ENDLOOP.

    "--------------------------------------------------------------------
    " Table-Access-Sätze (table_access) – aggregiert je Tabelle
    " → für Top-Tabellen-Übersicht im Management-Report
    "--------------------------------------------------------------------
    LOOP AT is_content-table_access INTO DATA(ls_acc).
      CLEAR ls_item.
      ls_item-session_id      = iv_session_id.
      ls_item-item_seq        = lv_seq.
      ls_item-data_source     = 'PTC_TBLACCESS'.
      ls_item-stmt_type       = 'SUMM_TAB'.
      ls_item-tabname         = ls_acc-tname.
      ls_item-laufzeit_us     = ls_acc-duration.
      ls_item-anzahl_exec     = ls_acc-count.
      ls_item-records_fetched = ls_acc-records.
      ls_item-trace_date      = is_dir_entry-start_date.

      APPEND ls_item TO rt_items.
      lv_seq += 1.
    ENDLOOP.
  ENDMETHOD.


  METHOD derive_tabname.
    " OBJECT: "BKPF"          → einfacher Zugriff
    "         "BKPF,BSEG"     → JOIN, erste Tabelle als Primär
    DATA(lv_obj) = CONV string( iv_object ).
    CONDENSE lv_obj.

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
    rv_flag = xsdbool( lv_upper CS ' WHERE ' ).
  ENDMETHOD.

ENDCLASS.
