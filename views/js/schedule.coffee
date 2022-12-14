define (require,exports,module) ->
  # Requirng schedule_item in multiple scripts cause minified file larger
  # since both scripts contains whole content of schedule_item.js.
  # TODO: do not require schedule_item here and load it dynamically.
  $si = require("schedule_item")
  $ed = require("event_detail")
  $co = require("comment")

  ScheduleRouter = Backbone.Router.extend
    routes:
      "cal/:year-:mon": "cal",
      "ev_done(/:page)" : "ev_done",
      "": "start"
    initialize: ->
      _.bindAll(@,"start")
    start: ->
      dt = new Date()
      mon = dt.getMonth() + 1
      year = dt.getFullYear()
      @navigate("cal/#{year}-#{mon}", {trigger: true, replace: true})
    ev_done: (page) ->
      window.schedule_view.$el.hide()
      if window.schedule_event_done_view?
        window.schedule_event_done_view.remove()
      window.schedule_event_done_view = new ScheduleEventDoneView(page:page)

    cal: (year,mon) ->
      if window.schedule_event_done_view?
        window.schedule_event_done_view.remove()
      window.schedule_view.$el.show()
      window.schedule_view.refresh(year,mon)

  ScheduleEventDoneModel = Backbone.Model.extend
    url: "api/schedule/ev_done"
  ScheduleEventDoneView = Backbone.View.extend
    template: _.template_braces($("#templ-schedule-event-done").html())
    events:
      "click .detail" : "reveal_detail"
      "click .comment" : "reveal_comment"
      "click .page" : "goto_page"
    goto_page: (ev)->
      page = $(ev.currentTarget).data("page")
      window.schedule_router.navigate("ev_done/#{page}", trigger: true)
    reveal_detail: (ev)->
      id = $(ev.currentTarget).closest("[data-event-id]").data("event-id")
      $ed.reveal_detail("#container-event-detail",id)
    reveal_comment: (ev)->
      id = $(ev.currentTarget).closest("[data-event-id]").data("event-id")
      $co.reveal_comment("event","#container-event-comment",id,null,$ed.additional_data(id))
    initialize: ->
      @model = new ScheduleEventDoneModel()
      @listenTo(@model,"sync",@render)
      @model.fetch(data:{page:@options.page})
    render: ->
      @$el.html(@template(data:@model.toJSON()))
      @$el.appendTo("#schedule-event-done")

  ScheduleCollection = Backbone.Collection.extend
    model: $si.ScheduleModel
    refresh: (year,mon) ->
      @url = "api/schedule/cal/#{year}-#{mon}"
    parse: (data) ->
      @year = data.year
      @mon = data.mon
      @before_day = data.before_day
      bef = if data.before_day > 0
              for i in [1..data.before_day]
                {current: false}
            else
                []
      cur = for i in [1..data.month_day]
              {current: true
              year: @year
              mon: @mon
              day: i
              info: data.day_infos[i.toString()]
              event: data.events[i.toString()]
              item: data.items[i.toString()]}
      aft = if data.after_day > 0
              for i in [1..data.after_day]
                {current: false}
            else
               []
      bef.concat(cur.concat(aft))

  ScheduleView = Backbone.View.extend
    el: "#schedule"
    events:
      "click #edit-info-done":"do_edit_info_done"
      "click #prev-month": -> @inc_month(-1)
      "click #next-month": -> @inc_month(1)
      "click .toggle-edit-info": "do_toggle_edit_info"
      "click .show-done-events": -> window.schedule_router.navigate("ev_done", trigger: true)
      "click .start-multi-edit": "multi_edit_1"
      "click #multi-edit-apply": "multi_edit_apply"
      "click #multi-edit-cancel": "multi_edit_done"
    multi_edit_apply: ->
      id = @multi_edit_item.data("schedule-id")
      that = this
      $.post("api/schedule/copy/#{id}",{list:@schedule_item_new}).done(-> that.multi_edit_done())

    multi_edit_done: ->
      @multi_edit_mode = 0
      @schedule_item_new = []
      @undelegate_multi_edit_events()
      @collection.fetch()

    # ??????????????????????????????
    multi_edit_common: ->
      # subviews???click????????????????????????????????????
      for v in @subviews
        v.undelegateEvents()
      @$el.find(".container-btn").hide()
      @$el.find(".event-item").hide()
      @$el.find(".container-multi-edit").html($("#templ-multi-edit").html())

    # ???????????????????????????????????????????????????
    undelegate_multi_edit_events: ->
      for stage,v of @multi_edit_events
        for k,func of v
          delete @events[k]
      @delegateEvents()
    # ??????????????????????????????
    multi_edit_events:
      "stage_1":
        "click .schedule-item": (ev)->
          @multi_edit_item = $(ev.currentTarget).clone()
          @multi_edit_item.addClass("schedule-item-new success")
          @$el.find(".schedule-item").removeClass("now-copying")
          @multi_edit_2()
      "stage_2":
        "click .info-item": (ev)->
          ev.stopPropagation()
          obj = $(ev.currentTarget)
          dt = obj.data('date')
          return if _.contains(@schedule_item_new,dt)
          obj.append(@multi_edit_item.clone())
          @schedule_item_new.push(dt)
        "click .schedule-item-new": (ev)->
          ev.stopPropagation()
          obj = $(ev.currentTarget)
          dt = obj.parents('.info-item').data('date')
          obj.remove()
          @schedule_item_new =
            _.reject(@schedule_item_new,(x)->x==dt)

    multi_edit_1: ->
      @multi_edit_mode = 1
      @schedule_item_new = []
      @multi_edit_common()
      @$el.find(".schedule-item").addClass("now-copying")
      @events = _.extend(@events,@multi_edit_events.stage_1)
      # @events ???????????????????????? @delegateEvents() ?????????
      @delegateEvents()

    multi_edit_2: ->
      @multi_edit_mode = 2
      @multi_edit_common()
      @undelegate_multi_edit_events()
      for x in @schedule_item_new
        dt = new Date(x)
        if dt.getFullYear() == @collection.year and dt.getMonth() + 1 == @collection.mon
          $(".info-item[data-date='#{x}']").append(@multi_edit_item.clone())

      @events = _.extend(@events,@multi_edit_events.stage_2)
      @delegateEvents()

    refresh: (year,mon) ->
      @collection.refresh(year,mon)
      @collection.fetch()

    inc_month: (dx) ->
      m = @collection.mon
      y = @collection.year
      x = y * 12 + ( m - 1 ) + dx
      mm = (x % 12) + 1
      yy = Math.floor(x / 12)
      window.schedule_router.navigate("cal/#{yy}-#{mm}", trigger: true)
    do_toggle_edit_info: ->
      @edit_info ^= true
      @render()
    template: _.template($("#templ-cal-header").html()+$("#templ-cal").html())
    template_edit: _.template($("#templ-cal-edit-header").html()+$("#templ-cal").html())

    initialize: ->
      @collection = new ScheduleCollection()
      @listenTo(@collection,"sync",@render)
    do_edit_info_done: ->
      have_to_update = {}
      for v in @subviews
        val= v.$el.find(".info").val()
        names_new = if !!val then val.split("\n") else []
        minfo = v.model.get("info")
        names_old = if minfo then minfo.names else []
        holiday_old = if minfo then !! minfo.is_holiday else false
        holiday_new = v.$el.find(".holiday").is(":checked")

        if "#{names_new}" != "#{names_old}" or holiday_old != holiday_new
          [year,mon,day] = (v.model.get(x) for x in ["year","mon","day"])
          have_to_update["#{year}-#{mon}-#{day}"] = {
            names: names_new
            holiday: holiday_new
          }
      if not _.isEmpty(have_to_update)
        @save_holiday(have_to_update)
      else
        @do_toggle_edit_info()

    save_holiday: (have_to_update)->
      res = Backbone.sync('update',this,
        method:'post',
        url:'api/schedule/update_holiday',
        contentType:'application/json',
        data:JSON.stringify(have_to_update))
      that = this
      res.done( ->
        that.collection.fetch().done(-> that.do_toggle_edit_info())
      )

    render: ->
      templ = if @edit_info then @template_edit else @template
      @$el.html(templ(
            year: @collection.year
            mon: @collection.mon
      ))
      @subviews = []
      if not window.is_small
        for x,i in _.weekday_ja()
          ac = if i == 0
                 "weekday-sunday"
               else if i == 6
                 "weekday-saturday"
               else
                 ""
          $("#cal-body").append($("<li>",{text:x,class:"weekday-name #{ac}"}))
      for m in @collection.models
        v = new $si.ScheduleItemView(model:m)
        if @edit_info
          v.render_edit_info()
        else
          v.render()
        if not window.is_small or m.get('current')
          $("#cal-body").append(v.$el)
        @subviews.push(v)
      switch @multi_edit_mode
        when 1 then @multi_edit_1()
        when 2 then @multi_edit_2()
  init: ->
    window.show_schedule_weekday = window.is_small
    window.schedule_router = new ScheduleRouter()
    window.schedule_view = new ScheduleView()
    $si.init()
    Backbone.history.start()
