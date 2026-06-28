"--------------------------------------------------------------------
" ZCL_PA_SCORER – Score berechnen und Priorität ableiten
"--------------------------------------------------------------------
CLASS zcl_pa_scorer DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS score_finding
      CHANGING cs_finding TYPE zpa_finding.

  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_weights,
        runtime   TYPE p LENGTH 5 DECIMALS 2,
        frequency TYPE p LENGTH 5 DECIMALS 2,
        datavolume TYPE p LENGTH 5 DECIMALS 2,
        pattern   TYPE p LENGTH 5 DECIMALS 2,
        custom    TYPE p LENGTH 5 DECIMALS 2,
      END OF ty_weights.

    DATA ms_weights TYPE ty_weights.
    DATA ms_thresholds TYPE zpa_finding_type.

    METHODS load_config.
    METHODS get_basis_score
      IMPORTING iv_type        TYPE zpa_finding_type
      RETURNING VALUE(rv_score) TYPE i.
    METHODS calc_runtime_score
      IMPORTING iv_laufzeit_us  TYPE abap.int8
      RETURNING VALUE(rv_score)  TYPE i.
    METHODS calc_frequency_score
      IMPORTING iv_exec_count  TYPE abap.int4
      RETURNING VALUE(rv_score) TYPE i.
    METHODS calc_datavolume_score
      IMPORTING iv_records     TYPE abap.int4
      RETURNING VALUE(rv_score) TYPE i.
    METHODS derive_priority
      IMPORTING iv_score          TYPE i
      RETURNING VALUE(rv_priority) TYPE zpa_prioritaet.
    METHODS derive_hebel
      IMPORTING iv_type           TYPE zpa_finding_type
                iv_exec_count     TYPE abap.int4
      RETURNING VALUE(rv_hebel)    TYPE zpa_opt_hebel.

ENDCLASS.

CLASS zcl_pa_scorer IMPLEMENTATION.

  METHOD score_finding.
    load_config( ).

    DATA(lv_basis)     = get_basis_score( cs_finding-finding_type ).
    DATA(lv_runtime)   = calc_runtime_score( cs_finding-laufzeit_us ).
    DATA(lv_frequency) = calc_frequency_score( cs_finding-anzahl_exec ).
    DATA(lv_datavolume) = calc_datavolume_score( cs_finding-datenmenge ).

    " Gewichteter Gesamt-Score
    DATA(lv_score_dec) =
        ms_weights-runtime    * lv_runtime
      + ms_weights-frequency  * lv_frequency
      + ms_weights-datavolume * lv_datavolume
      + ms_weights-pattern    * lv_basis
      + COND #( WHEN cs_finding-is_custom_code = abap_true
                THEN ms_weights-custom * 10
                ELSE 0 ).

    cs_finding-score     = CONV #( MIN( lv_score_dec, 100 ) ).
    cs_finding-prioritaet = derive_priority( cs_finding-score ).
    cs_finding-optim_hebel = derive_hebel(
      iv_type       = cs_finding-finding_type
      iv_exec_count = cs_finding-anzahl_exec ).
  ENDMETHOD.


  METHOD load_config.
    " Gewichte aus ZPA_CONFIG lesen, Defaults falls nicht gepflegt
    SELECT FROM zpa_config
      FIELDS parameter, wert_dec
      WHERE mandt     = @sy-mandt
        AND parameter IN ( 'SCORE_W_RUNTIME', 'SCORE_W_FREQUENCY',
                           'SCORE_W_DATAVOLUME', 'SCORE_W_PATTERN',
                           'SCORE_W_CUSTOM' )
      INTO TABLE @DATA(lt_cfg).

    ms_weights-runtime    = VALUE #( lt_cfg[ parameter = 'SCORE_W_RUNTIME'    ]-wert_dec DEFAULT '0.35' ).
    ms_weights-frequency  = VALUE #( lt_cfg[ parameter = 'SCORE_W_FREQUENCY'  ]-wert_dec DEFAULT '0.25' ).
    ms_weights-datavolume = VALUE #( lt_cfg[ parameter = 'SCORE_W_DATAVOLUME' ]-wert_dec DEFAULT '0.20' ).
    ms_weights-pattern    = VALUE #( lt_cfg[ parameter = 'SCORE_W_PATTERN'    ]-wert_dec DEFAULT '0.15' ).
    ms_weights-custom     = VALUE #( lt_cfg[ parameter = 'SCORE_W_CUSTOM'     ]-wert_dec DEFAULT '0.05' ).
  ENDMETHOD.


  METHOD get_basis_score.
    SELECT SINGLE basis_score FROM zpa_finding_type
      WHERE mandt        = @sy-mandt
        AND finding_type = @iv_type
        AND aktiv        = @abap_true
      INTO @rv_score.
    IF sy-subrc <> 0. rv_score = 50. ENDIF.
  ENDMETHOD.


  METHOD calc_runtime_score.
    " Logarithmische Skala: 100ms=25, 500ms=40, 2s=60, 10s=80, 60s=100
    IF iv_laufzeit_us <= 0. rv_score = 0. RETURN. ENDIF.
    DATA(lv_sek) = iv_laufzeit_us / 1000000.
    rv_score = CONV #( MIN( 20 * log10( CONV decfloat34( lv_sek + 1 ) ) * 30, 100 ) ).
  ENDMETHOD.


  METHOD calc_frequency_score.
    " 1x=0, 5x=20, 10x=40, 50x=70, 100x=90, 500x+=100
    IF iv_exec_count <= 1. rv_score = 0. RETURN. ENDIF.
    rv_score = CONV #( MIN( log10( CONV decfloat34( iv_exec_count ) ) * 45, 100 ) ).
  ENDMETHOD.


  METHOD calc_datavolume_score.
    " 100 Rows=10, 1.000=25, 10.000=50, 100.000=75, 1.000.000+=100
    IF iv_records <= 0. rv_score = 0. RETURN. ENDIF.
    rv_score = CONV #( MIN( log10( CONV decfloat34( iv_records ) ) * 20, 100 ) ).
  ENDMETHOD.


  METHOD derive_priority.
    rv_priority = SWITCH #( iv_score
      WHEN 0 THEN 'HINWEIS'
      ELSE COND #(
        WHEN iv_score >= 90 THEN 'KRITISCH'
        WHEN iv_score >= 70 THEN 'HOCH'
        WHEN iv_score >= 50 THEN 'MITTEL'
        WHEN iv_score >= 20 THEN 'NIEDRIG'
        ELSE                     'HINWEIS' ) ).
  ENDMETHOD.


  METHOD derive_hebel.
    " SELECT-in-Loop und Duplikate: FOR ALL ENTRIES bringt Faktor 10-100x
    rv_hebel = SWITCH #( iv_type
      WHEN 'SELECT_LOOP'  THEN 'HOCH'
      WHEN 'DUPLICATE_SQL' THEN 'HOCH'
      WHEN 'NO_WHERE'     THEN 'HOCH'
      WHEN 'FULL_SCAN'    THEN COND #(
        WHEN iv_exec_count > 10 THEN 'HOCH' ELSE 'MITTEL' )
      WHEN 'HIGH_RUNTIME'  THEN 'MITTEL'
      WHEN 'CDS_EXPENSIVE' THEN 'MITTEL'
      ELSE 'NIEDRIG' ).
  ENDMETHOD.

ENDCLASS.
