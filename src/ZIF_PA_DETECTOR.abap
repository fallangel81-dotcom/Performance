"--------------------------------------------------------------------
" ZIF_PA_DETECTOR – Interface für alle Pattern-Detektoren
"--------------------------------------------------------------------
INTERFACE zif_pa_detector PUBLIC.

  TYPES:
    tt_items    TYPE STANDARD TABLE OF zpa_trace_item WITH DEFAULT KEY,
    tt_findings TYPE STANDARD TABLE OF zpa_finding    WITH DEFAULT KEY.

  METHODS detect
    IMPORTING
      it_items       TYPE tt_items
      iv_session_id  TYPE sysuuid_x16
    RETURNING
      VALUE(rt_findings) TYPE tt_findings.

  METHODS get_type
    RETURNING
      VALUE(rv_type) TYPE zpa_finding_type.

ENDINTERFACE.
