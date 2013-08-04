# -*- coding: utf-8 -*-
class MainApp < Sinatra::Base
  namespace '/mobile/schedule' do
    def mobile_emphasis(item,key)
      s = (item[key]||"").escape_html
      if (item["emphasis"] || []).include?(key) then
        s = "<b>#{s}</b>"
      end
      s
    end
    def mobile_paren_private(item,s)
      if not item["public"] then
        s = "(#{s})"
      end
      s
    end
    get '/detail/:year-:month-:day' do
      @year = params[:year].to_i
      @month = params[:month].to_i
      @day = params[:day].to_i
      @info = call_api(:get,"/api/schedule/detail/#{@year}-#{@month}-#{@day}")
      mobile_haml :schedule_detail
    end
    get '/cal/:year-:month' do
      @year = params[:year].to_i
      @month = params[:month].to_i
      @date = Date.new(@year,@month,1)

      @info = call_api(:get,"/api/schedule/cal/#{@year}-#{@month}")
      mobile_haml :schedule
    end
  end
  get '/mobile/schedule' do
    today = Date.today
    call env.merge("PATH_INFO" => "/mobile/schedule/cal/#{today.year}-#{today.month}")
  end
end
