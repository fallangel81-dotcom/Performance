  method get_status_concatenated.
    "*------------------------------------------------------------------*
    "* Liefert konkatenierte System- und Anwenderstatus je ObjectKey.
    "*
    "* Optimierung gegenüber Vorgänger:
    "*   Statt 3 DB-Roundtrips je Status-Typ (FOR ALL ENTRIES +
    "*   ITAB-JOIN + ITAB STRING_AGG) nur noch 1 Roundtrip:
    "*   - FOR ALL ENTRIES → Status-Codes holen
    "*   - Cache-Lookup + Sortierung komplett in ABAP
    "*   - STRING_AGG per ABAP GROUP BY LOOP (kein ##ITAB_DB_SELECT)
    "*   Ergebnis: 6 → 2 DB-Roundtrips pro Seitenaufruf
    "*------------------------------------------------------------------*

    data: lv_status_view      type string,
          lt_system_status    type tt_objnr_status,
          lt_user_status      type tt_objnr_status,
          lt_sys_work         type tt_status_sort,
          lt_usr_work         type tt_status_sort,
          lt_system_status_agg type tt_status_agg_sorted,
          lt_user_status_agg   type tt_status_agg_sorted.

    check it_objnr is not initial and iv_objtype is not initial.

    "*--- Systemstatus ---*
    if iv_system_status_req = abap_true.

      lv_status_view = me->resolve_cds_view( iv_objecttype    = iv_objtype
                                             iv_is_userstatus = abap_false ).

      select objectkey, status
        from (lv_status_view)
        for all entries in @it_objnr
        where objectkey = @it_objnr-objectkey
        into table @lt_system_status.

      if sy-subrc = 0.

        me->check_cache_loaded( iv_objecttype    = iv_objtype
                                iv_is_userstatus = abap_false ).

        "-- Cache-Lookup + Sortierfelder in ABAP befüllen (kein DB-Roundtrip) --"
        loop at lt_system_status assigning field-symbol(<ls_sys>).
          read table gt_cache assigning field-symbol(<ls_sc>)
            with key objecttype    = iv_objtype
                     is_userstatus = abap_false
                     status        = <ls_sys>-status.
          check sy-subrc = 0.
          insert value #( objectkey       = <ls_sys>-objectkey
                          status          = <ls_sys>-status
                          statusshortname = <ls_sc>-statusshortname
                          linepos         = <ls_sc>-linepos
                          startpos        = <ls_sc>-startpos ) into table lt_sys_work.
        endloop.

        sort lt_sys_work by objectkey linepos startpos statusshortname.

        "-- STRING_AGG per ABAP GROUP BY --"
        loop at lt_sys_work assigning field-symbol(<ls_sw>)
             group by ( objectkey = <ls_sw>-objectkey ) assigning field-symbol(<grp_sys>).

          data ls_sys_agg type ts_status_agg_sorted.
          clear ls_sys_agg.
          ls_sys_agg-objectkey = <grp_sys>-objectkey.

          loop at group <grp_sys> assigning field-symbol(<ls_si>).
            if ls_sys_agg-systemstatus        is not initial. ls_sys_agg-systemstatus        &&= ` `. endif.
            if ls_sys_agg-systemstatusintern  is not initial. ls_sys_agg-systemstatusintern  &&= ` `. endif.
            ls_sys_agg-systemstatus       &&= <ls_si>-statusshortname.
            ls_sys_agg-systemstatusintern &&= <ls_si>-status.
          endloop.

          insert ls_sys_agg into table lt_system_status_agg.
        endloop.

      endif.
    endif.

    "*--- Anwenderstatus ---*
    if iv_user_status_req = abap_true.

      lv_status_view = me->resolve_cds_view( iv_objecttype    = iv_objtype
                                             iv_is_userstatus = abap_true ).

      select objectkey, status, statusprofile
        from (lv_status_view)
        for all entries in @it_objnr
        where objectkey = @it_objnr-objectkey
        into corresponding fields of table @lt_user_status.

      if sy-subrc = 0.

        me->check_cache_loaded( iv_objecttype    = iv_objtype
                                iv_is_userstatus = abap_true ).

        "-- Cache-Lookup + Sortierfelder in ABAP befüllen (kein DB-Roundtrip) --"
        loop at lt_user_status assigning field-symbol(<ls_usr>).
          read table gt_cache assigning field-symbol(<ls_uc>)
            with key objecttype    = iv_objtype
                     is_userstatus = abap_true
                     status        = <ls_usr>-status
                     statusprofile = <ls_usr>-statusprofile.
          check sy-subrc = 0.
          insert value #( objectkey       = <ls_usr>-objectkey
                          status          = <ls_usr>-status
                          statusshortname = <ls_uc>-statusshortname
                          statusprofile   = <ls_usr>-statusprofile
                          statusorderno   = <ls_uc>-statusorderno
                          linepos         = <ls_uc>-linepos
                          startpos        = <ls_uc>-startpos ) into table lt_usr_work.
        endloop.

        "-- Anwenderstatus: absteigende Ordnungsnummer, dann Anzeigefelder --"
        sort lt_usr_work by objectkey statusorderno descending linepos startpos statusshortname.

        "-- STRING_AGG per ABAP GROUP BY --"
        loop at lt_usr_work assigning field-symbol(<ls_uw>)
             group by ( objectkey = <ls_uw>-objectkey ) assigning field-symbol(<grp_usr>).

          data ls_usr_agg type ts_status_agg_sorted.
          clear ls_usr_agg.
          ls_usr_agg-objectkey = <grp_usr>-objectkey.

          loop at group <grp_usr> assigning field-symbol(<ls_ui>).
            if ls_usr_agg-userstatus       is not initial. ls_usr_agg-userstatus       &&= ` `. endif.
            if ls_usr_agg-userstatusintern is not initial. ls_usr_agg-userstatusintern &&= ` `. endif.
            ls_usr_agg-userstatus       &&= <ls_ui>-statusshortname.
            ls_usr_agg-userstatusintern &&= <ls_ui>-status.
          endloop.

          insert ls_usr_agg into table lt_user_status_agg.
        endloop.

      endif.
    endif.

    "*--- Ergebnis zusammenführen ---*
    rt_status_concat_sorted = value #(
      for <ls_objnr> in it_objnr
      let sys  = value ts_status_agg_sorted( lt_system_status_agg[ objectkey = <ls_objnr>-objectkey ] optional )
          user = value ts_status_agg_sorted( lt_user_status_agg[   objectkey = <ls_objnr>-objectkey ] optional )
       in ( objectkey          = <ls_objnr>-objectkey
            systemstatus       = sys-systemstatus
            systemstatusintern = sys-systemstatusintern
            userstatus         = user-userstatus
            userstatusintern   = user-userstatusintern ) ).

  endmethod.
