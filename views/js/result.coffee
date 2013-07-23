define (require,exports,module) ->
  # Requirng schedule_item in multiple scripts cause minified file larger
  # since both scripts contains whole content of schedule_item.js.
  # TODO: do not require schedule_item here and load it dynamically.
  $ed = require("event_detail")
  $co = require("comment")

  _.mixin
    result_str: (s) ->
      {win: '○'
      lose: '●'
      now: '対戦中'
      default_win: '不戦'
      }[s]
    show_opponent_belongs: (team_size,s) ->
      return "" unless s
      r = []
      if team_size == 1
        r.push s
      else
        r.push s.opponent_belongs if s.opponent_belongs
        r.push(switch s.opponent_order
          when 1 then "主将"
          when 2 then "副将"
          else "#{s.opponent_order}将") if s.opponent_order?
      "(#{r.join(" / ")})" if r.length > 0
    show_prize: (s) ->
      r = []
      ss = s.prize
      if s.point then r.push "#{s.point}pt"
      if s.point_local then r.push "#{s.point_local}kpt"
      if r.length > 0
        ss += " [#{r.join(",")}]"
      ss
    show_header_left: (s) ->
      if not s?
        "名前"
      else
        a = $("<div>",text:_.escape(s.team_name))
        b = $("<div>",class:"team-prize",text:_.escape(s.team_prize))
        a[0].outerHTML + b[0].outerHTML
        
  
  ContestResultRouter = Backbone.Router.extend
    routes:
      "contest/:id": "contest"
      "": "contest"
    contest: (id)->
      window.result_view.refresh(id)

  ContestChunkModel = Backbone.Model.extend {}

  ContestChunkView = Backbone.View.extend
    template: _.template_braces($('#templ-contest-chunk').html())
    initialize: ->
      @render()
    render: ->
      @$el.html(@template(data:_.extend(@model.toJSON(),team_size:window.result_view.collection.team_size)))
  ContestResultCollection = Backbone.Collection.extend
    url: -> 'api/result/contest/' + (@id or "latest")
    model: ContestChunkModel
    parse: (data)->
      for x in ["recent_list","name","date","id",
        "contest_classes","group","team_size","event_group_id"]
        @[x] = data[x]
      data.contest_results
  # TODO: split this view to ContestInfoView which has name, date, group, list  and ContestResultView which only has result
  ContestResultView = Backbone.View.extend
    el: '#contest-result'
    template: _.template_braces($('#templ-contest-result').html())
    events:
      "click .contest-link": "contest_link"
      "click #show-event-group": "show_event_group"
      "click #contest-add": "contest_add"
    show_event_group: _.wrap_submit ->
      $ed.show_event_group(@collection.event_group_id)
      false
    contest_add: ->
      $ed.show_event_edit(
        new $ed.EventItemModel(kind:"contest",id:"contest",done:true),
        {do_when_done:(m)-> window.result_router.navigate("contest/#{m.get('id')}",trigger:true)}
      )
    contest_link: (ev) ->
      id = $(ev.currentTarget).data('id')
      window.result_router.navigate("contest/#{id}",trigger:true)
    initialize: ->
      _.bindAll(this,"render","refresh","contest_link","show_event_group")
      @collection = new ContestResultCollection()
      @listenTo(@collection,"sync",@render)
    render: ->
      col = @collection
      @$el.html(@template(_.pick(@collection,"id","recent_list","group","name","date")))
      cur_class = null
      col.each (m)->
        if m.get("class_id") != cur_class
          cur_class = m.get("class_id")
          class_name = col.contest_classes[cur_class]
          $("#contest-result-body").append($("<div>",{class:"class-name label round",text:class_name}))
        v = new ContestChunkView(model:m)
        $("#contest-result-body").append(v.$el)

      this.$el.foundation('section','reflow')
      $co.section_comment(
        "event",
        "#event-comment",
        col.id,
        $("#event-comment-count"))
      new ContestInfoView(id:col.id)
    refresh: (id) ->
      @collection.id = id
      @collection.fetch()
  ContestInfoView = Backbone.View.extend
    el: "#contest-info"
    initialize: ->
      @render()
    render: ->
      @model = new $ed.EventItemModel(id:@options.id)
      v = new $ed.EventDetailView(target:"#contest-info",model:@model,no_participant:true)
      @model.fetch(data:{detail:true,no_participant:true})
  init: ->
    window.result_router = new ContestResultRouter()
    window.result_view = new ContestResultView()
    Backbone.history.start()
