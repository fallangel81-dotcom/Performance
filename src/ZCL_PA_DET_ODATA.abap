"--------------------------------------------------------------------
" ZCL_PA_DET_ODATA – Detektor: Langsame OData- und RFC-Zugriffe
"
" Erkennt zwei Kategorien:
"   ODATA_SLOW: SQL-Statements, die aus OData-Serviceprogrammen
"               stammen (/IWFND/, /IWBEP/, SEGW-generierte Klassen)
"               und die Laufzeitschwelle überschreiten.
"
"   RFC_SLOW:   SQL-Statements aus RFC-Funktionsbausteinen (erkennbar
"               an SAPLSM, RFC* oder Funktionsgruppen mit /1BCDWB/)
"               sowie direkte RFC/HTTP-Kontexte via WP_TYPE.
"
" Datengrundlage: PTC_MAIN-Sätze (Einzelstatements)
" Konfiguration:  ZPA_CONFIG – ODATA_MIN_RT (µs), RFC_MIN_RT (µs)
"--------------------------------------------------------------------
CLASS zcl_pa_det_odata DEFINITION
  PUBLIC FINAL CREATE PUBLIC
  INTERFACES zif_pa_detector.

  PUBLIC SECTION.
    METHODS constructor.

  PRIVATE SECTION.
    DATA mv_min_odata_rt TYPE abap.int8.
    DATA mv_min_rfc_rt   TYPE abap.int8.

    METHODS load_thresholds.

    METHODS is_odata_program
      IMPORTING
        iv_program     TYPE ptc_program_name
      RETURNING
        VALUE(rv_flag) TYPE abap_bool.

    METHODS is_rfc_context
      IMPORTING
        is_item        TYPE zpa_trace_item
      RETURNING
        VALUE(rv_flag) TYPE abap_bool.

    METHODS build_finding
      IMPORTING
        iv_session_id  TYPE sysuuid_x16
        is_item        TYPE zpa_trace_item
        iv_subtype     TYPE c             " 'O'=OData 'R'=RFC
      RETURNING
        VALUE(rs_finding) TYPE zpa_finding.
ENDCLASS.

CLASS zcl_pa_det_odata IMPLEMENTATION.

  METHOD constructor.
    load_thresholds( ).
  ENDMETHOD.

  METHOD zif_pa_detector~get_type.
    rv_type = 'ODATA_SLOW'.
  ENDMETHOD.

  METHOD load_thresholds.
    SELECT FROM zpa_config
      FIELDS parameter, wert_num
      WHERE mandt     = @sy-mandt
        AND parameter IN ( 'ODATA_MIN_RT', 'RFC_MIN_RT' )
      INTO TABLE @DATA(lt_cfg).

    " Standard: OData > 2 Sek., RFC > 5 Sek. als kritisch
    mv_min_odata_rt = VALUE #( lt_cfg[ parameter = 'ODATA_MIN_RT' ]-wert_num DEFAULT 2000000 ).
    mv_min_rfc_rt   = VALUE #( lt_cfg[ parameter = 'RFC_MIN_RT'   ]-wert_num DEFAULT 5000000 ).
  ENDMETHOD.


  METHOD is_odata_program.
    DATA(lv_prog) = to_upper( CONV string( iv_program ) ).

    " Gateway-Framework (SAP NetWeaver Gateway)
    IF lv_prog CS '/IWFND/' OR lv_prog CS '/IWBEP/'. rv_flag = abap_true. RETURN. ENDIF.

    " SEGW-generierte Klassen (Präfix CL_/ZCL_ + _MPC/_DPC/_EXT)
    IF lv_prog CS '_DPC' OR lv_prog CS '_DPC_EXT'. rv_flag = abap_true. RETURN. ENDIF.
    IF lv_prog CS '_MPC' OR lv_prog CS '_MPC_EXT'. rv_flag = abap_true. RETURN. ENDIF.

    " RAP-Business-Objekte (SADL-Framework ab S/4HANA 1709)
    IF lv_prog CS '/SAPSLL/' OR lv_prog CS 'CL_SADL'. rv_flag = abap_true. RETURN. ENDIF.

    " HTTP-Handler im ICM-Kontext
    IF lv_prog CS 'CL_HTTP' OR lv_prog CS '/HTTP/'. rv_flag = abap_true. RETURN. ENDIF.
  ENDMETHOD.


  METHOD is_rfc_context.
    " WP_TYPE = 'B' → Background (kein RFC, aber oft ähnliche Last)
    " WP_TYPE = 'U' → Update
    " RFC-Kontexte: WP_TYPE enthält 'R' oder Programm ist RFC-FuBa-Umgebung
    IF is_item-wp_type CA 'Rr'. rv_flag = abap_true. RETURN. ENDIF.

    DATA(lv_prog) = to_upper( CONV string( is_item-program_name ) ).

    " Klassische RFC-Funktionsgruppen
    IF lv_prog(4) = 'SAPL'. " SAPL<FuGr>
      IF lv_prog CS 'RFC' OR lv_prog CS 'ARFC' OR lv_prog CS 'SRFC'.
        rv_flag = abap_true. RETURN.
      ENDIF.
    ENDIF.

    " BAPI-Wrapper (typisch BWxxxxx)
    IF lv_prog(4) = 'BAPI'. rv_flag = abap_true. RETURN. ENDIF.

    " /1BCDWB/ – generierte Datenbankzugriffsobjekte, oft in RFC-Kontext
    IF lv_prog CS '/1BCDWB/'. rv_flag = abap_true. RETURN. ENDIF.
  ENDMETHOD.


  METHOD zif_pa_detector~detect.
    LOOP AT it_items INTO DATA(ls_item)
      WHERE data_source = 'PTC_MAIN'.

      IF is_odata_program( ls_item-program_name ) = abap_true
         AND ls_item-laufzeit_us >= mv_min_odata_rt.

        APPEND build_finding(
          iv_session_id = iv_session_id
          is_item       = ls_item
          iv_subtype    = 'O' ) TO rt_findings.

      ELSEIF is_rfc_context( ls_item ) = abap_true
         AND ls_item-laufzeit_us >= mv_min_rfc_rt.

        APPEND build_finding(
          iv_session_id = iv_session_id
          is_item       = ls_item
          iv_subtype    = 'R' ) TO rt_findings.
      ENDIF.
    ENDLOOP.

    " Bestes (längstes) Finding je SQL behalten
    SORT rt_findings BY sql_hash finding_type laufzeit_us DESCENDING.
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
    rs_finding-kategorie      = 'CDS_ODATA'.
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

    CASE iv_subtype.
      WHEN 'O'.  " OData / Gateway
        rs_finding-finding_type = 'ODATA_SLOW'.
        rs_finding-technische_ursache =
          |OData-Serviceprogramm { is_item-program_name } führte { is_item-stmt_type } | &&
          |auf { is_item-tabname } in { lv_sek } Sek. durch | &&
          |({ is_item-records_fetched } Datensätze).|.
        rs_finding-fachliche_einsch =
          |Langsame Datenbankoperation im OData-Kontext beeinträchtigt direkt die | &&
          |Fiori-App-Performance. Nutzer erleben Wartezeiten beim Öffnen von Listen | &&
          |oder bei Wertehilfen (F4-Hilfe).|.
        rs_finding-empf_massnahme =
          |1. CDS-View auf Annotationen prüfen (Puffering, AccessControl). | &&
          |2. $select, $filter, $top im OData-Client prüfen – werden alle Felder/Zeilen | &&
          |   tatsächlich benötigt? | &&
          |3. SADL-Caching oder Gateway-Caching prüfen. | &&
          |4. HANA Plan Visualizer für den konkreten SQL aufrufen.|.

      WHEN 'R'.  " RFC / BAPI
        rs_finding-finding_type = 'RFC_SLOW'.
        rs_finding-kategorie    = 'RFC_BAPI'.
        rs_finding-technische_ursache =
          |RFC/BAPI-Kontext ({ is_item-program_name }): { is_item-stmt_type } auf | &&
          |{ is_item-tabname } dauerte { lv_sek } Sek. | &&
          |WP-Typ: { is_item-wp_type }.|.
        rs_finding-fachliche_einsch =
          |Langsame Datenbankoperation in RFC/BAPI-Kontext kann Quell-Systeme oder | &&
          |Schnittstellenpartner blockieren (synchrone RFCs mit Timeout-Risiko). | &&
          |Bei Batch-Input oder IDocs: erhöhte Verarbeitungszeiten im Hintergrund.|.
        rs_finding-empf_massnahme =
          |1. SQL-Statement auf Vollständigkeit der WHERE-Klausel prüfen. | &&
          |2. Tabellenpuffer nutzen sofern fachlich korrekt. | &&
          |3. Bei häufigem Aufruf: Ergebnis im BAPI/RFC selbst puffern. | &&
          |4. Massendaten in RFC via TABLES-Parameter bündeln statt Einzelaufrufe.|.
    ENDCASE.
  ENDMETHOD.

ENDCLASS.
