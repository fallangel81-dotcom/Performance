"--------------------------------------------------------------------
" ZCL_PA_DET_FULL_SCAN – Detektor: Full Table Scan / kein WHERE
"
" Erkennungslogik:
"   FULL_SCAN:  records_fetched > Schwellwert UND has_where = false
"               ODER has_where = true aber Selektivität < 5%
"               (records_selected / records_fetched < 0.05 – soweit messbar)
"
"   NO_WHERE:   has_where = false UND records_fetched > Mindestmenge
"               → eigenständiges Finding (schwerer als FULL_SCAN)
"--------------------------------------------------------------------
CLASS zcl_pa_det_full_scan DEFINITION
  PUBLIC FINAL CREATE PUBLIC
  INTERFACES zif_pa_detector.

  PUBLIC SECTION.
    METHODS constructor.

  PRIVATE SECTION.
    DATA mv_min_rows    TYPE abap.int4.
    DATA mv_min_runtime TYPE abap.int8.

    " Bekannte Cluster-/Pool-Tabellen in S/4HANA (noch vorhanden)
    CONSTANTS: c_cluster_tables TYPE string
      VALUE 'BSEG|BSEG_ADD|PCL1|PCL2|STXL|INDX|EDI40|CDCLS'.

    METHODS load_thresholds.
    METHODS build_finding
      IMPORTING
        iv_session_id  TYPE sysuuid_x16
        is_item        TYPE zpa_trace_item
        iv_type        TYPE zpa_finding_type
      RETURNING
        VALUE(rs_finding) TYPE zpa_finding.
    METHODS is_cluster_table
      IMPORTING
        iv_tabname     TYPE tabname
      RETURNING
        VALUE(rv_flag) TYPE abap_bool.
ENDCLASS.

CLASS zcl_pa_det_full_scan IMPLEMENTATION.

  METHOD constructor.
    load_thresholds( ).
  ENDMETHOD.

  METHOD zif_pa_detector~get_type.
    rv_type = 'FULL_SCAN'.
  ENDMETHOD.

  METHOD load_thresholds.
    SELECT FROM zpa_config
      FIELDS parameter, wert_num
      WHERE mandt     = @sy-mandt
        AND parameter IN ( 'FULLSCAN_MIN_ROWS', 'RT_NIEDRIG' )
      INTO TABLE @DATA(lt_cfg).

    mv_min_rows    = CONV #( VALUE #( lt_cfg[ parameter = 'FULLSCAN_MIN_ROWS' ]-wert_num DEFAULT 10000 ) ).
    mv_min_runtime = VALUE #( lt_cfg[ parameter = 'RT_NIEDRIG' ]-wert_num DEFAULT 100000 ).
  ENDMETHOD.

  METHOD zif_pa_detector~detect.
    " Nur Haupt-Sätze auswerten (Einzelstatements)
    LOOP AT it_items INTO DATA(ls_item)
      WHERE data_source = 'PTC_MAIN'
        AND stmt_type   = 'SELECT'.

      " --- NO_WHERE: SELECT ohne jede WHERE-Bedingung ---
      IF ls_item-has_where = abap_false
        AND ls_item-records_fetched > 100.

        APPEND build_finding(
          iv_session_id = iv_session_id
          is_item       = ls_item
          iv_type       = 'NO_WHERE' ) TO rt_findings.
        CONTINUE.
      ENDIF.

      " --- FULL_SCAN: viele Rows gelesen, ggf. WHERE vorhanden aber ineffektiv ---
      IF ls_item-records_fetched >= mv_min_rows
        AND ls_item-laufzeit_us >= mv_min_runtime.

        APPEND build_finding(
          iv_session_id = iv_session_id
          is_item       = ls_item
          iv_type       = 'FULL_SCAN' ) TO rt_findings.
        CONTINUE.
      ENDIF.

      " --- CLUSTER_ACCESS: Zugriff auf Cluster-/Pool-Tabelle ---
      IF is_cluster_table( ls_item-tabname ) = abap_true
        AND ls_item-laufzeit_us >= mv_min_runtime.

        APPEND build_finding(
          iv_session_id = iv_session_id
          is_item       = ls_item
          iv_type       = 'CLUSTER_ACCESS' ) TO rt_findings.
      ENDIF.

    ENDLOOP.

    " Duplikate vermeiden: je sql_hash nur das schwerste Finding behalten
    SORT rt_findings BY sql_hash finding_type.
    DELETE ADJACENT DUPLICATES FROM rt_findings
      COMPARING sql_hash finding_type.
  ENDMETHOD.


  METHOD build_finding.
    TRY.
        rs_finding-finding_id = cl_system_uuid=>create_uuid_x16_static( ).
      CATCH cx_uuid_error.
        rs_finding-finding_id = '0000000000000000'.
    ENDTRY.

    rs_finding-session_id     = iv_session_id.
    rs_finding-item_seq       = is_item-item_seq.
    rs_finding-finding_type   = iv_type.
    rs_finding-kategorie      = SWITCH #( iv_type
      WHEN 'NO_WHERE'      THEN 'DB_ACCESS'
      WHEN 'FULL_SCAN'     THEN 'DB_ACCESS'
      WHEN 'CLUSTER_ACCESS' THEN 'ARCHITEKTUR'
      ELSE 'DB_ACCESS' ).
    rs_finding-programm       = is_item-program_name.
    rs_finding-tabname        = is_item-tabname.
    rs_finding-sql_hash       = is_item-sql_hash.
    rs_finding-laufzeit_us    = is_item-laufzeit_us.
    rs_finding-anzahl_exec    = MAX( is_item-anzahl_exec, 1 ).
    rs_finding-datenmenge     = is_item-records_fetched.
    rs_finding-is_custom_code = is_item-is_custom_code.
    rs_finding-sql_kurzform   = substring( val = is_item-sql_text
                                           len = MIN( strlen( is_item-sql_text ), 200 ) ).

    CASE iv_type.
      WHEN 'NO_WHERE'.
        rs_finding-technische_ursache =
          |SELECT auf { is_item-tabname } ohne WHERE-Bedingung. | &&
          |{ is_item-records_fetched } Datensätze gelesen.|.
        rs_finding-fachliche_einsch =
          |Ein SELECT ohne WHERE-Einschränkung liest die gesamte Tabelle. | &&
          |In S/4HANA sind große Tabellen (BKPF, MATDOC, ...) mehrere Millionen Zeilen groß.|.
        rs_finding-empf_massnahme =
          |WHERE-Bedingung ergänzen. Mindestens MANDT und führende Schlüsselfelder | &&
          |(z.B. BUKRS, GJAHR) einschränken. Prüfen ob SELECT überhaupt notwendig.|.

      WHEN 'FULL_SCAN'.
        rs_finding-technische_ursache =
          |{ is_item-records_fetched } Datensätze aus { is_item-tabname } gelesen | &&
          |bei einer Laufzeit von { is_item-laufzeit_us } µs. | &&
          |WHERE-Bedingung vorhanden aber kein geeigneter Index aktiv.|.
        rs_finding-fachliche_einsch =
          |Die Datenbankabfrage liest erheblich mehr Daten als vermutlich benötigt. | &&
          |Häufige Ursache: führende Indexfelder fehlen in der WHERE-Bedingung.|.
        rs_finding-empf_massnahme =
          |1. Indexnutzung in SE11/DBACOCKPIT prüfen (HANA Plan Visualizer). | &&
          |2. WHERE-Bedingung um Indexfelder erweitern. | &&
          |3. Bei häufigem Zugriff: sekundären Datenbankindex anlegen.|.

      WHEN 'CLUSTER_ACCESS'.
        rs_finding-technische_ursache =
          |Zugriff auf Cluster-/Pool-Tabelle { is_item-tabname }. | &&
          |In S/4HANA sind diese Tabellen weitgehend transparent – Zugriffsmuster prüfen.|.
        rs_finding-fachliche_einsch =
          |Cluster-Tabellen wie BSEG haben ein ungünstiges Zugriffsverhalten | &&
          |für selektive Abfragen. In S/4HANA sollte BSEG_ADD oder ein CDS-View genutzt werden.|.
        rs_finding-empf_massnahme =
          |Zugriff auf { is_item-tabname } durch CDS-View oder | &&
          |Universal Journal (ACDOCA) ersetzen wo möglich.|.
    ENDCASE.
  ENDMETHOD.


  METHOD is_cluster_table.
    rv_flag = xsdbool( c_cluster_tables CS to_upper( iv_tabname ) ).
  ENDMETHOD.

ENDCLASS.
