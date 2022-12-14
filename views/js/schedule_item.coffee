define (require, exports, module) ->
  $ed = require("event_detail")
  $co = require("comment")
  locals = {}
  _.mixin
    show_name_public: (data)->
      s = _.escape(data.name)
      if data.public
        s
      else
        "(#{s})"

    show_schedule_emphasis: (data)->
      return "" unless data.emphasis
      d = _.pick(data,data.emphasis)
      r = ""
      if d.place
        r += "@ <span class='place'>#{_.escape(d.place)}</span>"
      if d.start_at or d.end_at
        r += " &isin; <span class='hourmin'>#{d.start_at ? ''}</span> &sim; <span class='hourmin'>#{d.end_at ? ''}</span>"
      r

    show_item_detail: (data,show_date=false)->
      dt = if show_date then "<span class='date'>#{data.date or '-'}</span>"
      hm = if data.start_at or data.end_at
        c1 = if data.emph_start_at then "emphasis" else ""
        c2 = if data.emph_end_at then "emphasis" else ""
        "<span class='hourmin #{c1}'>#{data.start_at ? ''}</span> &sim; <span class='hourmin #{c2}'>#{data.end_at ? ''}</span>"
      pl = if data.place
        c = if data.emph_place then "emphasis" else ""
        plc = _.escape(data.place ? '')
        if data.map_bookmark_id?
          " @ <a class='#{c}' target='_blank' href='map#bookmark/#{data.map_bookmark_id}' >#{plc}</a>"
        else
          " @ <span class='place #{c}'>#{plc}</span>"
      ds = if data.description
        "<div class='description panel left pre'>#{_.replace_url_escape(data.description)}</div>"
      tt = if data.name
        c = if data.emph_name then "emphasis" else ""
        "<span class='title #{c}'>#{_.escape(data.name)}</span>"
      dthm = if dt or hm then "[ #{dt ? ''} #{hm ? ''} ] "
      ss = (dthm ? '') + (tt ? '') + (pl ? '')
      "<div>#{ss}</div>" + (ds ? '')
  ScheduleModel = Backbone.Model.extend
    url: ->
      [y,m,d] = (@get(x) for x in ['year','mon','day'])
      "api/schedule/get/#{y}-#{m}-#{d}"
    parse: (data)->
      data.current = true unless data.current?
      data

  ScheduleItemView = Backbone.View.extend
    events:
      "click":"do_when_click"
    template: _.template_braces($("#templ-schedule-item").html())
    template_edit_info: _.template($("#templ-schedule-item-edit-info").html())
    el: "<li>"
    initialize: ->
      _.bindAll(this,"refresh","render")
      @listenTo(@model,"sync",@render)
    refresh: ->
      @model.fetch()
    do_when_click: ->
      return if @edit_info or not @model.get('current')
      [year,mon,day] = (@model.get(x) for x in ['year','mon','day'])
      reveal_detail(@model,year,mon,day)
    get_date: ->
      if @model.get('current')
        _.gen_date(@model)
    show_day: (date) ->
      date = if date? then date else @get_date()
      if date
        (if window.show_schedule_month then "#{date.getMonth()+1} / " else "") +
        date.getDate() +
        (if window.show_schedule_weekday then " (#{_.weekday_ja()[date.getDay()]})" else "")
    render: ->
      @edit_info = false
      info = @model.get('info')
      date = @get_date()
      @$el.html(@template(
            item: @model.get('item')
            event: @model.get('event')
            info: info
            day: @show_day(date)
            date: date.toDateString() if date
      ))
      info_item = @$el.find(".info-item")
      if @model.get('current')
        info_item.addClass("current")
        today = new Date()
        if today.toDateString() == date.toDateString()
          info_item.addClass('today')
        if (info and info.is_holiday) or (date.getDay() == 0)
          info_item.addClass("holiday")
        else if date.getDay() == 6
          info_item.addClass("saturday")
        else
          info_item.addClass("weekday")
      else
        info_item.addClass("not-current")
    render_edit_info: ->
      @edit_info = true
      info = @model.get('info')
      @$el.html(@template_edit_info(
        info: info
        day: @show_day()
      ))
      if info and info.is_holiday
        @$el.find(".holiday").prop("checked",true)
      if not @model.get('current')
        @$el.find(".info-item-edit").addClass("not-current-edit")

  ScheduleDetailModel = Backbone.Model.extend
    urlRoot: "api/schedule/detail/item"

  ScheduleDetailCollection = Backbone.Collection.extend
    url: -> "api/schedule/detail/#{@year}-#{@mon}-#{@day}"
    model: ScheduleDetailModel
    refresh: (year,mon,day) ->
      @year = year
      @mon = mon
      @day = day
    parse: (data) ->
      @year = data.year
      @mon = data.mon
      @day = data.day
      @day_infos = data.day_infos
      @events = data.events
      data.list
  ScheduleDetailItemView = Backbone.View.extend
    template: _.template($("#templ-schedule-detail-item").html())
    template_edit: _.template_braces($("#templ-schedule-detail-item-edit").html())
    events:
      "click .edit":"toggle_edit"
      "click .delete":"delete_item"
      "click .edit-cancel":"toggle_edit"
      "click .edit-done":"edit_done"
    refresh_day: ->
      window.schedule_detail_view.options.parent_model.fetch()
    delete_item: ->
      that = this
      _.cb_prompt('??????????????????delete?????????????????????').done((res)->
        if res == "delete"
          that.model.destroy().done(->
            window.schedule_detail_view.refresh()
            that.refresh_day()))
    edit_done: ->
      obj = @$el.find('.item-detail-form').serializeObj()
      that = this
      when_done = if @model.isNew()
        ->
          window.schedule_detail_view.refresh()
          that.refresh_day()
      else
        ->
          that.toggle_edit()
          that.refresh_day()
      _.save_model_alert(@model,obj,null,true).done(->
        when_done()
        $(locals.schedule_detail_target).removeClass("form-changed")
      )
    toggle_edit: ->
      $(locals.schedule_detail_target).removeClass("form-changed")
      if @model.isNew()
        @$el.remove()
      else
        @edit_mode ^= true
        if @edit_mode
          @model.fetch().done(@render_edit)
        else
          @model.fetch().done(@render)
    initialize: ->
      @edit_mode = false
      _.bindAll(this,"toggle_edit","edit_done","render","render_edit")
    render: ->
      @$el.html(@template(data:@model.toJSON()))
    render_edit: ->
      @edit_mode = true
      @$el.html(@template_edit(is_new:@model.isNew(),data:@model.toJSON()))
      @$el.find("[name='kind']").val(@model.get("kind"))
      _.ie9_placeholder(@el)
  ScheduleDetailEventView = Backbone.View.extend
    events:
      "click .detail" : "show_detail"
      "click .comment" : "show_comment"
    show_detail: ->
      $ed.reveal_detail("#container-event-detail",@data.id)
    show_comment: ->
      $co.reveal_comment("event","#container-event-comment",@data.id,null,$ed.additional_data(@data.id))
    template: _.template_braces($("#templ-schedule-detail-event").html())
    initialize: (arg) -> @data = arg.data

    render: ->
      @$el.html(@template(data:@data))

  ScheduleDetailView = Backbone.View.extend
    template: _.template($("#templ-schedule-detail").html())
    events:
      "click #add-new-item": "do_add_new"
    do_add_new: ->
      m = new ScheduleDetailModel(year:@collection.year,mon:@collection.mon,day:@collection.day,public:true)
      v = new ScheduleDetailItemView(model:m)
      $("#container-new-item").empty()
      v.render_edit()
      $("#container-new-item").append(v.$el)
     initialize: ->
      _.bindAll(this,"render","do_add_new")
      @collection = new ScheduleDetailCollection()
    refresh: (year,mon,day) ->
      if year?
        @collection.refresh(year,mon,day)
      else
      @collection.fetch().done(@render)
    render: ->
      [year,mon,day] = (@collection[x] for x in ["year","mon","day"])
      date = _.gen_date(year,mon,day)
      di = @collection.day_infos
      names = if di then di.names
      is_holiday = if di then di.holiday
      @$el.html(@template(data:
        is_holiday: is_holiday
        day_infos: names
        year: year
        mon: mon
        day: day
        wday: _.weekday_ja()[date.getDay()]
      ))
      @$el.appendTo(locals.schedule_detail_target)
      body =@$el.find('.body')
      for m in @collection.events
        v = new ScheduleDetailEventView(data:m)
        v.render()
        body.append(v.$el)
      for m in @collection.models
        v = new ScheduleDetailItemView(model:m)
        v.render()
        body.append(v.$el)
  reveal_detail = (model,year,mon,day)->
    v = new ScheduleDetailView(parent_model:model)
    window.schedule_detail_view = v
    t = locals.schedule_detail_target
    _.reveal_view(t,v,true)
    v.refresh(year,mon,day)
  {
    ScheduleModel: ScheduleModel
    ScheduleItemView: ScheduleItemView
    init: (arg) ->
      locals.schedule_detail_target = if arg and arg.target then arg.target else "#container-schedule-detail"
  }
