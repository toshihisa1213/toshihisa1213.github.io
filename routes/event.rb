# -*- coding: utf-8 -*-
class MainApp < Sinatra::Base
  namespace '/api/event' do
    def event_info(ev,user,user_choices=nil)
      today = Date.today
      r = ev.select_attr(:name,:date,:deadline,:created_at,:id,:participant_count,:comment_count)
      r[:deadline_day] = (r[:deadline]-today).to_i if r[:deadline]
      r[:choices] = ev.choices(order:[:index.asc]).map{|x|x.select_attr(:positive,:name,:id)}
      r[:choice] = if user_choices then user_choices[ev.id] 
                   else
                     t = user.event_user_choices.event_choices.first(event:ev)
                     t && t.id
                   end
      r
    end
    get '/item/:id' do
      user = get_user
      ev = Event.first(id:params[:id].to_i)
      r = event_info(ev,user)
      if params[:mode] == "detail"
        r.merge!({description: Kagetra::Utils.escape_html_br(ev.description)})
        r[:participant] = ev.choices(positive:true).each_with_object({}){|c,obj|
          obj[c.id] = c.users.map{|u|
            u.name
          }
        }
      end
      r
    end
    get '/list' do
      user = get_user
      events = (Event.all(:date.gte => Date.today) + Event.all(date: nil))

      # 各eventごとに取得するのは遅いのでまとめて取得しておく
      user_choices = user.event_user_choices.event_choice(event:events).to_enum.with_object({}){|x,h|h[x.event_id]=x.id}

      events.map{|ev|
        event_info(ev,user,user_choices)
      }
    end
    post '/choose/:eid/:cid' do
      begin
        user = get_user
        evt = Event.first(id:params[:eid].to_i)
        evt.choices.first(id:params[:cid].to_i).user_choices.create(user:user)
        {count: evt.choices(positive: true).users.count}
      rescue DataMapper::SaveFailureError => e
        p e.resource.errors
      end
    end
    get '/comment/list/:id' do
      evt = Event.first(id:params[:id].to_i)
      list = evt.comments(order: [:created_at.desc]).map{|x|
        x.select_attr(:user_name)
          .merge({
            date: x.created_at.strftime('%Y-%m-%d %H:%M:%S'),
            body: Kagetra::Utils.escape_html_br(x.body)
          })
      }
      {
        event_name: evt.name,
        list: list
      }
    end
    post '/comment/item' do
      begin
        user = get_user
        evt = Event.first(id:params[:event_id].to_i)
        # TODO: automatically set user_name from user in model's :save hook
        c = evt.comments.create(user:user,body:params[:body],user_name:user.name)
      rescue DataMapper::SaveFailureError => e
        p e.resource.errors
      end
    end
  end
end