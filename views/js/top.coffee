define (require,exports,module) ->
  $si = require("schedule_item")
  $ed = require("event_detail")
  _.mixin
    show_new_comment: (count,has_new)->
      c = if has_new
        " <span class='new-comment'>new</span>"
      else
        ""
      "( <span class='comment-count'>#{count}</span>#{c} )"
    show_date: (s) ->
      return "なし" unless s
      today = new Date()
      [y,m,d] = (parseInt(x) for x in s.split('-'))
      date = new Date(y,m-1,d)
      sa = "<span class='event-date'>"
      sb = "</span>"
      sw = "<span class='event-weekday'>"
      wday = _.weekday_ja()[date.getDay()]

      ymd = "#{sa}#{m}#{sb} 月 #{sa}#{d}#{sb} 日 (#{sw}#{wday}#{sb})"
      if today.getFullYear() != y
        ymd = "#{sa}#{y}#{sb} 年 " + ymd
      ymd
  show_deadline = (deadline_day) ->
    if not deadline_day?
      "なし"
    else if deadline_day < 0
      "<span class='deadline-expired'>過ぎました</span>"
    else if deadline_day == 0
      "<span class='deadline-today'>今日</span>"
    else if deadline_day == 1
      "<span class='deadline-tomorrow'>明日</span>"
    else
      "あと <span class='deadline-future'>#{deadline_day}</span> 日"

  SchedulePanelCollection = Backbone.Collection.extend
    model: $si.ScheduleModel
    url: "/api/schedule/panel"

  SchedulePanelView = Backbone.View.extend
    el: '#schedule-panel'
    initialize: ->
      _.bindAll(this,"render")
      @collection = new SchedulePanelCollection()
      @collection.fetch().done(@render)
    render: ->
      @subviews = {}
      for m in @collection.models
        v = new $si.ScheduleItemView(model:m)
        v.render()
        @$el.append(v.$el)
        [y,m,d] = (m.get(x) for x in ["year","mon","day"])
        @subviews["#{y}-#{m}-#{d}"] = v
    get_subview: (year,mon,day) ->
      @subviews["#{year}-#{mon}-#{day}"]

  EventListCollection = Backbone.Collection.extend
    model: $ed.EventItemModel
    url: "/api/event/list"
    set_comparator: (attr) ->
      @order = attr
      sign = if attr in ["created_at","latest_comment_date","participant_count"] then -1 else 1
      ETERNAL_FUTURE = "9999-12-31_"
      ETERNAL_PAST = "0000-01-01_"
      f = if attr in ["created_at","date","latest_comment_date"]
            PREFIX = if sign == -1 then ETERNAL_PAST else ETERNAL_FUTURE
            (x)-> x.get(attr) || (PREFIX + x.get("name"))
          else if attr == "deadline_day"
            (x)->
              dd = x.get("deadline_day")
              if not dd?
                999999999
              else if dd < 0
                999999 - dd
              else
                dd
      @comparator = (x,y) -> fx=f(x);fy=f(y);if fx>fy then sign else if fx<fy then -sign else 0
  EventItemView = Backbone.View.extend
    el: '<li>'
    template: _.template($('#templ-event-item').html())
    events:
      "click .show-detail": "show_detail"
      "click .show-comment": "show_comment"
    render: ->
      json = @model.toJSON()
      json.deadline = show_deadline(@model.get('deadline_day'))
      @$el.html(@template(data:json))
    initialize: ->
      _.bindAll(this,"show_detail","show_comment")
    show_detail: ->
      window.event_detail_view.reveal(@model)
    show_comment: ->
      window.event_comment_view
        .reveal(@model.get('id'),@$el.find(".comment-count"))

      

  EventListView = Backbone.View.extend
    el: '#event-list'
    template: _.template($('#templ-event-list').html())
    events:
      "click #event-order .choice": "reorder"
    reorder: (ev) ->
      target = $(ev.currentTarget)
      order = target.attr("data-order")
      @collection.set_comparator(order)
      @collection.sort()
    initialize: ->
      _.bindAll(this,"reorder")
      @collection = new EventListCollection()
      @collection.bind("sort", @render, this)
      @collection.set_comparator('date')
      @collection.fetch()
    render: ->
      @$el.html(@template())
      @$el.find(".choice[data-order='#{@collection.order}']").addClass("active")
      @subviews = []
      for m in @collection.models
        v = new EventItemView(model:m)
        v.render()
        @$el.find(".event-body").append(v.$el)
        cm = new EventChoiceModel(choices:m.get('choices'),choice:m.get('choice'),eid:m.get('id'))
        cv = new EventChoiceView(model:cm,event_name:m.get('name'),parent:v)
        cv.render()
        v.$el.find(".event-choice").append(cv.$el)
        @subviews.push(v)

  EventChoiceModel = Backbone.Model.extend
    url: -> "/api/event/choose/#{@get('eid')}/#{@get('choice')}"

  EventChoiceView = Backbone.View.extend
    el: "<dd class='sub-nav'>"
    template: _.template_braces($("#templ-event-choice").html())
    template_alert: _.template($("#templ-sticky-alert").html())
    events:
      "click .choice" : "do_when_click"
    initialize: (arg)->
      this.event_name = arg.event_name
      this.parent = arg.parent
      _.bindAll(this,"do_when_click")
      @model.bind("change",@render,this)
    do_when_click: (ev)->
      ct = $(ev.currentTarget)
      id = ct.attr('data-id')
      @model.set('choice',id)
      that = this
      @model.save().done((data)->
        c = $("#sticky-alert-container")
        if c.find("#sticky-alert").length == 0
          c.append(that.template_alert())
        c.find(".content").append($("<div/>",{html:"登録完了: " + that.event_name + " &rArr;" + ct.text()}))
        that.parent.$el.find(".participant-count").text(data.count)
      )
    render: ->
      choices = @model.get("choices")
      data = {data:
        x for x in choices
      }
      @$el.html(@template(data))
      @$el.find("dd[data-id='#{@model.get('choice')}']").addClass("active")

  init: ->
    window.show_schedule_weekday = true
    window.show_schedule_month = true
    window.schedule_panel_view = new SchedulePanelView()
    window.event_list_view = new EventListView()
    window.event_detail_view = new $ed.EventDetailView()
    window.schedule_detail_view = new $si.ScheduleDetailView(parent:window.schedule_panel_view)
    window.event_comment_view = new $ed.EventCommentView()
