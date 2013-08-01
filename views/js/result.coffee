define (require,exports,module) ->
  # Requirng schedule_item in multiple scripts cause minified file larger
  # since both scripts contains whole content of schedule_item.js.
  # TODO: do not require schedule_item here and load it dynamically.
  $ed = require("event_detail")
  $co = require("comment")
  $rc = require("result_common")

  _.mixin
    order_to_ja: (x)->
      switch x
        when 1 then "主将"
        when 2 then "副将"
        else "#{x}将"
    show_opponent_belongs: (team_size,s) ->
      return "" unless s
      r = []
      if team_size == 1
        r.push s
      else
        r.push s.opponent_belongs if s.opponent_belongs
        r.push(_.order_to_ja(s.opponent_order)) if s.opponent_order?
      "(#{r.join(" / ")})" if r.length > 0
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

  ContestResultEditView = Backbone.View.extend
    el: '#contest-result-body'
    events:
      'click .round-name' : 'edit_round'
      'cilck .row-info' : 'edit_player'
      'click .num-person' : 'edit_num_person'
    edit_round: ->
      
    edit_player: ->

    initialize: ->
      @render()
    render: ->
      @$el.find(".round-name").addClass("editable")
      @$el.find(".row-info").addClass("editable")
      $("#edit-player").after($("<ul>",{id:"edit-help"}))
      $("#edit-help").append($("<li>",{text:"名前をクリックするとその選手の成績を編集できます"}))
      $("#edit-help").append($("<li>",{text:"〜回戦をクリックするとその回戦の成績を編集できます"}))
      $("#edit-help").append($("<li>",{text:"級の参加人数をクリックするとそれを編集できます"}))
      $("#edit-player").hide()
      @$el.find(".num-person").show().addClass("editable")
  ContestResultCollection = Backbone.Collection.extend
    url: -> 'api/result/contest/' + (@id or "latest")
    model: ContestChunkModel
    parse: (data)->
      for x in ["recent_list","name","date","id",
        "contest_classes","group","team_size","event_group_id"]
        @[x] = data[x]
      data.contest_results
  ContestPlayerModel = Backbone.Model.extend
    urlRoot: 'api/result/players'
    defaults: ->
      deleted_classes: []
      deleted_users: []
      deleted_teams: []
  ContestPlayerView = Backbone.View.extend
    events:
      "click .apply-edit" : "apply_edit"
      "click .add-class" : "add_class"
      "click .delete-class" : "delete_class"
      "click .delete-player" : "delete_player"
      "click .add-player" : "add_player"
      "click .move-player" : "move_player"
    apply_edit: ->
      that = this
      @model.save().done(->
        alert("更新しました")
        window.result_view.collection.fetch()
        $("#container-result-edit").foundation("reveal","close")
      )
    get_checked: ->
      $.makeArray(@$el.find("form :checked").map(->$(@).data("id")))
    initialize: ->
      @newid = 1
      @model = new ContestPlayerModel(id:@options.id)
      @listenTo(@model,'sync',@render)
      @model.fetch()
    render: ->
      @$el.html(@template(data:@model.toJSON()))
      @$el.appendTo(@options.target)
    add_class: ->
      classes = @$el.find(".class-to-add").val().split(/\s+/)
      classes.reverse()
      target = @$el.find(".add-class-target select").val()
      position = @$el.find(".add-class-position").val()
      kls = @model.get('classes')
      index = (i.toString() for [i,j] in kls).indexOf(target)
      if position == "after"
        index += 1
      for c in classes
        nid = "new_#{@newid}"
        @newid += 1
        kls.splice(index,0,[nid,c])
        for s in ["user_classes","team_classes"]
          if @model.has(s)
            @model.get(s)[nid] = []
      @render()
    delete_class_common: (cs...)->
      cl = @$el.find(".class-to-delete select").val()
      for c in cs
        kls = @model.get(c)
        if not _.isEmpty(kls[cl])
          alert("空でない級は削除できません")
          return
      for c in cs
        kls = @model.get(c)
        delete kls[cl]
      @model.get("deleted_classes").push(cl) if cl.toString().indexOf("new_") != 0
      nclass = ([k,v] for [k,v] in @model.get('classes') when k.toString() != cl.toString())
      @model.set('classes',nclass)
      @render()
    add_player_common: (belongs)->
      players = @$el.find(".player-to-add").val().split(/\s+/)
      cl = @$el.find(".player-to-add-belong select").val()
      for p in players
        nid = "new_#{@newid}"
        @newid += 1
        @model.get(belongs)[cl].push(nid)
        @model.get('users')[nid] = p
      @render()
    move_player_common: (belongs)->
      checked = @get_checked()
      cl = @$el.find(".player-to-move-belong select").val()
      @remove_player_belong(checked)
      ucs = @model.get(belongs)
      ucs[cl] = ucs[cl].concat(checked)
      @render()
    delete_player: ->
      checked = @get_checked()
      users = @model.get('users')
      @remove_player_belong(checked)
      for c in checked
        @model.get("deleted_users").push(c) if c.toString().indexOf("new_") != 0
        delete users[c]
      @render()
    remove_player_belong_common: (checked, belongs...)->
      for b in belongs
        belong = @model.get(b)
        for k,v of belong
          belong[k] = _.difference(v,checked)

  class ContestSinglePlayerView extends ContestPlayerView
    template: _.template_braces($('#templ-single-player').html())
    remove_player_belong: (checked)->
      @remove_player_belong_common(checked,'user_classes')
    delete_class: ->
      @delete_class_common('user_classes')
    add_player: ->
      @add_player_common('user_classes')
    move_player: ->
      @move_player_common('user_classes')

  class ContestTeamPlayerView extends ContestPlayerView
    template: _.template_braces($('#templ-team-player').html())
    events:
      _.extend(ContestPlayerView.prototype.events,
        "click .delete-team" : "delete_team"
        "click .add-team" : "add_team"
      )
    delete_class: ->
      @delete_class_common('team_classes','neutral')
    add_player: ->
      @add_player_common('user_teams')
    move_player: ->
      @move_player_common('user_teams')
    remove_player_belong: (checked)->
      @remove_player_belong_common(checked,'user_teams','neutral')
    add_team: ->
      team = @$el.find(".team-to-add").val().split(/\s+/)
      cl = @$el.find(".team-to-add-class select").val()
      for t in team
        nid = "new_#{@newid}"
        @newid += 1
        @model.get('team_classes')[cl].push(nid)
        @model.get('teams')[nid] = t
        @model.get('user_teams')[nid] = []
      @render()

    delete_team: ->
      tid = _.to_int_if_digit(@$el.find(".team-to-delete select").val())
      team = @model.get('user_teams')
      if not _.isEmpty(team[tid])
        alert("空でないチームは削除できません")
        return
      delete team[tid]
      delete @model.get("teams")[tid]
      @model.get("deleted_teams").push(tid) if tid.toString().indexOf("new_") != 0
      team_classes = @model.get('team_classes')
      for k,v of team_classes
        team_classes[k] = _.without(v,tid)
      @render()


    
  # TODO: split this view to ContestInfoView which has name, date, group, list  and ContestResultView which only has result
  ContestResultView = Backbone.View.extend
    el: '#contest-result'
    template: _.template_braces($('#templ-contest-result').html())
    events:
      "click .contest-link": "contest_link"
      "click #show-event-group": "show_event_group"
      "click #contest-add": "contest_add"
      "click #toggle-edit-mode" : "toggle_edit_mode"
      "click #edit-player" : "edit_player"
    edit_player : ->
      target = "#container-result-edit"
      klass = if @collection.team_size == 1 then ContestSinglePlayerView else ContestTeamPlayerView
      v = new klass(target:target,id:@collection.id)
      _.reveal_view(target,v)

    toggle_edit_mode: ->
      if window.contest_result_edit_view?
        window.contest_result_edit_view.remove()
        delete window.contest_result_edit_view
        @collection.fetch()
      else
        $("#toggle-edit-mode").toggleBtnText(false)
        $("#edit-class-info").hide()
        window.contest_result_edit_view = new ContestResultEditView()
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
          cinfo = col.contest_classes[cur_class]
          c = $("<div>",{class:"class-info"})
          c.append($("<span>",{class:"class-name label round",text:cinfo.class_name}))
          np = cinfo.num_person || 0
          cl = $("<span>",{class:"num-person label",text:np + "人"})
          c.append(cl)
          cl.hide() if np == 0

          $("#contest-result-body").append(c)
        v = new ContestChunkView(model:m)
        $("#contest-result-body").append(v.$el)

      @$el.foundation('section','reflow')
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
    $rc.init()
    Backbone.history.start()
