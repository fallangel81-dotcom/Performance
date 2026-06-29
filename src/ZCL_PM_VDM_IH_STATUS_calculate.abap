  method if_sadl_exit_calc_element_read~calculate.
    "*------------------------------------------------------------------*
    "* Berechnet virtuelle Statusfelder (System_Status, UserStatus,
    "* SystemStatusIntern, UserStatusIntern) als konkatenierte Strings.
    "*
    "* Ablauf:
    "*   1. Entity-Typ aus gv_entity_req bestimmen
    "*   2. ObjectKeys der aktuellen Seite sammeln
    "*   3. get_status_concatenated: 2 DB-Roundtrips (sys + usr)
    "*   4. Ergebnis zeilenweise per Feldmapping zurückschreiben
    "*------------------------------------------------------------------*

    check it_requested_calc_elements is not initial.

    ct_calculated_data = corresponding #( it_original_data ).

    "*--- AC-Cockpit Auftragsübersicht /ETN/C_AC_ORDER_LIST ---*
    if gv_entity_req = gc_view_ac_order_list.

      if line_exists( it_requested_calc_elements[ table_line = 'USERSTATUS'         ] ) or
         line_exists( it_requested_calc_elements[ table_line = 'SYSTEM_STATUS'      ] ) or
         line_exists( it_requested_calc_elements[ table_line = 'USERSTATUSINTERN'   ] ) or
         line_exists( it_requested_calc_elements[ table_line = 'SYSTEMSTATUSINTERN' ] ).

        data lt_order_data type table of /etn/c_ac_order_list with key orderid.
        lt_order_data = corresponding #( it_original_data ).

        data(lt_objnr_order) = value tt_objnr(
          for <ls_o> in lt_order_data ( conv j_objnr( <ls_o>-objectkey ) ) ).
        sort lt_objnr_order by objectkey.
        delete adjacent duplicates from lt_objnr_order comparing objectkey.

        me->get_status_concatenated(
          exporting
            iv_objtype           = gc_objecttype-order
            iv_system_status_req = abap_true
            iv_user_status_req   = abap_true
            it_objnr             = lt_objnr_order
          receiving
            rt_status_concat_sorted = data(lt_status_order) ).

        loop at lt_status_order assigning field-symbol(<ls_calc_order>).
          assign lt_order_data[ objectkey = <ls_calc_order>-objectkey ] to field-symbol(<ls_order>).
          check sy-subrc = 0.
          <ls_order> = corresponding #( base ( <ls_order> ) <ls_calc_order>
                         mapping system_status = systemstatus ).
        endloop.

        ct_calculated_data = corresponding #( lt_order_data ).

      endif.
    endif.

    "*--- AC-Cockpit Objektliste /ETN/C_OBJECTLIST_EXTENDED ---*
    if gv_entity_req = gc_view_ac_object_list.

      if line_exists( it_requested_calc_elements[ table_line = 'NOTIFSYSSTATUS'    ] ) or
         line_exists( it_requested_calc_elements[ table_line = 'NOTIFUSERSTATUS'   ] ) or
         line_exists( it_requested_calc_elements[ table_line = 'NOTIFUSERSTATUSTXT'] ).

        data lt_objectlist_org type table of /etn/c_objectlist_extended.
        lt_objectlist_org = corresponding #( it_original_data ).

        data(lt_objnr_obj) = value tt_objnr(
          for <ls_obj> in lt_objectlist_org
          where ( notif_no is not initial )
          ( conv j_objnr( <ls_obj>-notifobjectkey ) ) ).
        sort lt_objnr_obj by objectkey.
        delete adjacent duplicates from lt_objnr_obj comparing objectkey.
        delete lt_objnr_obj from 123.

        if lt_objnr_obj is not initial.
          me->get_status_concatenated(
            exporting
              iv_objtype           = gc_objecttype-notification
              iv_system_status_req = abap_true
              iv_user_status_req   = abap_true
              it_objnr             = lt_objnr_obj
            receiving
              rt_status_concat_sorted = data(lt_status_obj) ).

          loop at lt_status_obj assigning field-symbol(<ls_calc_obj>).
            assign lt_objectlist_org[ objectkey = <ls_calc_obj>-objectkey ]
              to field-symbol(<ls_objectlist>).
            check sy-subrc = 0.
            <ls_objectlist> = corresponding #( base ( <ls_objectlist> ) <ls_calc_obj>
                               mapping notifsysstatus     = systemstatus
                                       notifuserstatus    = userstatusintern
                                       notifuserstatustxt = userstatus ).
          endloop.
        endif.

        ct_calculated_data = corresponding #( lt_objectlist_org ).

      endif.
    endif.

    "*--- MC-Cockpit Meldungsliste /ETN/C_NOTIF_DET_SRCH ---*
    if gv_entity_req = gc_view_mc_notif_list.

      if line_exists( it_requested_calc_elements[ table_line = 'USRSTATUS'         ] ) or
         line_exists( it_requested_calc_elements[ table_line = 'SYSSTATUS'         ] ) or
         line_exists( it_requested_calc_elements[ table_line = 'USERSTATUSINTERN'  ] ) or
         line_exists( it_requested_calc_elements[ table_line = 'SYSTEMSTATUSINTERN'] ).

        data lt_notif_list_org type table of /etn/c_notif_det_srch.
        lt_notif_list_org = corresponding #( it_original_data ).

        data(lt_objnr_notif) = value tt_objnr(
          for <ls_n> in lt_notif_list_org ( conv j_objnr( <ls_n>-objectkey ) ) ).
        sort lt_objnr_notif by objectkey.
        delete adjacent duplicates from lt_objnr_notif comparing objectkey.
        delete lt_objnr_notif from 123.

        me->get_status_concatenated(
          exporting
            iv_objtype           = gc_objecttype-notification
            iv_system_status_req = abap_true
            iv_user_status_req   = abap_true
            it_objnr             = lt_objnr_notif
          receiving
            rt_status_concat_sorted = data(lt_status_notif) ).

        loop at lt_status_notif assigning field-symbol(<ls_calc_notif>).
          assign lt_notif_list_org[ objectkey = <ls_calc_notif>-objectkey ]
            to field-symbol(<ls_notif>).
          check sy-subrc = 0.
          <ls_notif> = corresponding #( base ( <ls_notif> ) <ls_calc_notif>
                         mapping usrstatus = userstatus
                                 sysstatus = systemstatus ).
        endloop.

        ct_calculated_data = corresponding #( lt_notif_list_org ).  "← außerhalb des loops (bug fix)

      endif.
    endif.

  endmethod.
