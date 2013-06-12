define (require, exports, module) ->
  _ = require("underscore")
  $ = require("zep_or_jq")
  _.mixin
    result_str: (s) ->
      {win: '○'
      lose: '●'
      now: '対戦中'
      default_win: '不戦'
      }[s]
    template_braces: (x) ->
      _.template(x,false,interpolate: /\{\{(.+?)\}\}/g)
    gen_date: (args...) ->
      ymd = ["year","mon","day"]
      [year,mon,day] =
        if args.length == 1
          if args[0].get?
            args[0].get(x) for x in ymd
          else
            args[0][x] for x in ymd
        else
          args
      new Date(year,mon-1,day)
    weekday_ja: ->
      ["日","月","火","水","木","金","土"]
    wrap_submit: (f) ->
      ->
        try
          _.bind(f,this)()
        catch e
          console.log e
        return false
  $.fn.serializeObj = ->
    o = {}
    a = this.serializeArray()
    $.each a, ->
      if o[this.name]?
        if !o[this.name].push
          o[this.name] = [o[this.name]]
        o[this.name].push(this.value || '')
      else
        o[this.name] = this.value || ''
    o