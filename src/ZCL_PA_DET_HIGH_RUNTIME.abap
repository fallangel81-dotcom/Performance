"--------------------------------------------------------------------
" ZCL_PA_DET_HIGH_RUNTIME – Detektor: Hohe Einzellaufzeit
"
" Erkennt SQL-Statements, deren Einzellaufzeit die konfigurierten
" Schwellwerte (KRITISCH/HOCH/MITTEL) überschreitet.
" Arbeitet auf PTC_MAIN-Sätzen (Einzelstatements).
"--------------------------------------------------------------------
CLASS zcl_pa_det_high_runtime DEFINITION
  PUBLIC FINAL CREATE PUBLIC
  INTERFACES zif_pa_detector.

  PUBLIC SECTION.
    METHODS constructor.

  PRIVATE SECTION.
    DATA mv_threshold_kritisch TYPE abap.int8.
    DATA mv_threshold_hoch     TYPE abap.int8.
    DATA mv_threshold_mittel   TYPE abap.int8.

    METHODS load_thresholds.
    METHODS build_finding
      IMPORTING
        iv_session_id  TYPE sysuuid_x16
        is_item        TYPE zpa_trace_item
      RETURNING
        VALUE(rs_finding) TYPE zpa_finding.
ENDCLASS.

CLASS zcl_pa_det_high_runtime IMPLEMENTATION.

  METHOD constructor.
    load_thresholds( ).
  ENDMETHOD.

  METHOD zif_pa_detector~get_type.
    rv_type = 'HIGH_RUNTIME'.
  ENDMETHOD.

  METHOD load_thresholds.
    SELECT FROM zpa_config
      FIELDS parameter, wert_num
      WHERE mandt     = @sy-mandt
        AND parameter IN ( 'RT_KRITISCH', 'RT_HOCH', 'RT_MITTEL' )
      INTO TABLE @DATA(lt_cfg).

    mv_threshold_kritisch = VALUE #( lt_cfg[ parameter = 'RT_KRITISCH' ]-wert_num DEFAULT 10000000 ).
    mv_threshold_hoch     = VALUE #( lt_cfg[ parameter = 'RT_HOCH'     ]-wert_num DEFAULT  2000000 ).
    mv_threshold_mittel   = VALUE #( lt_cfg[ parameter = 'RT_MITTEL'   ]-wert_num DEFAULT   500000 ).
  ENDMETHOD.

  METHOD zif_pa_detector~detect.
    LOOP AT it_items INTO DATA(ls_item)
      WHERE data_source = 'PTC_MAIN'
        AND laufzeit_us >= mv_threshold_mittel.

      " Nur Datenbankoperationen – keine Aggregats-Sätze
      CHECK ls_item-stmt_type CA 'SELECT OPEN_CURSOR INSERT UPDATE DELETE'.

      APPEND build_finding( iv_session_id = iv_session_id
                            is_item       = ls_item ) TO rt_findings.
    ENDLOOP.

    " Je Statement nur das schwerste Finding (höchste Laufzeit)
    SORT rt_findings BY sql_hash laufzeit_us DESCENDING.
    DELETE ADJACENT DUPLICATES FROM rt_findings COMPARING sql_hash.
  ENDMETHOD.

  METHOD build_finding.
    TRY.
        rs_finding-finding_id = cl_system_uuid=>create_uuid_x16_static( ).
      CATCH cx_uuid_error.
        rs_finding-finding_id = '0000000000000000'.
    ENDTRY.

    rs_finding-session_id     = iv_session_id.
    rs_finding-item_seq       = is_item-item_seq.
    rs_finding-finding_type   = 'HIGH_RUNTIME'.
    rs_finding-kategorie      = 'DB_ACCESS'.
    rs_finding-programm       = is_item-program_name.
    rs_finding-tabname        = is_item-tabname.
    rs_finding-sql_hash       = is_item-sql_hash.
    rs_finding-laufzeit_us    = is_item-laufzeit_us.
    rs_finding-anzahl_exec    = MAX( is_item-anzahl_exec, 1 ).
    rs_finding-datenmenge     = is_item-records_fetched.
    rs_finding-is_custom_code = is_item-is_custom_code.
    rs_finding-sql_kurzform   = substring( val = is_item-sql_text
                                           len = MIN( strlen( is_item-sql_text ), 200 ) ).

    DATA(lv_sek) = is_item-laufzeit_us / 1000000.

    rs_finding-technische_ursache =
      |{ is_item-stmt_type } auf { is_item-tabname } dauerte { lv_sek } Sekunden. | &&
      |{ is_item-records_fetched } Datensätze gelesen. | &&
      COND #( WHEN is_item-hana_proc_time_us > 0
              THEN |HANA-Verarbeitungszeit: { is_item-hana_proc_time_us / 1000000 } Sek.|
              ELSE `` ).

    rs_finding-fachliche_einsch =
      COND #(
        WHEN is_item-laufzeit_us >= mv_threshold_kritisch
        THEN |Kritisch lange Datenbankoperation. Bei Verwendung in Dialogen führt | &&
             |dies zu Timeouts und massiven Benutzerbeeinträchtigungen.|
        WHEN is_item-laufzeit_us >= mv_threshold_hoch
        THEN |Signifikant lange Datenbankoperation. Spürbare Wartezeit für Endanwender. | &&
             |Prüfen ob Optimierungspotenzial durch Index oder SQL-Umstrukturierung besteht.|
        ELSE |Merkliche Datenbankoperation. Im Kontext häufig aufgerufener | &&
             |Transaktionen optimierungswürdig.| ).

    rs_finding-empf_massnahme =
      |1. HANA Plan Visualizer (DBACOCKPIT) für dieses Statement aufrufen. | &&
      |2. Fehlenden Index identifizieren. | &&
      |3. WHERE-Bedingung auf Vollständigkeit prüfen. | &&
      |4. Bei CDS-View: Annotationen und Assoziationen auf Effizienz prüfen.|.
  ENDMETHOD.

ENDCLASS.
