# -*- coding: utf-8 -*-
class MainApp < Sinatra::Base
  BBS_THREADS_PER_PAGE = 10
  namespace '/api/bbs' do
    get '/threads' do
      user = get_user
      page = params["page"].to_i - 1
      qs = params["qs"]
      query = BbsThread.all
      if qs then
        qs.strip.split(/\s+/).each{|q|
          # 一件もヒットしないダミーのクエリ
          # TODO: 以下をする正しい方法
          qb = BbsThread.all(id: -1)
          [
            :title,
            BbsThread.items.user_name,
            BbsThread.items.body
          ].each{|sym|
            # TODO: クエリのエスケープ
            qb |= BbsThread.all(sym.like => "%#{q}%")
          }
          query &= qb
        }
      end
      query.all(order: [:updated_at.desc ]).chunks(BBS_THREADS_PER_PAGE)[page].map{|t|
        items = t.items.map{|i|
          i.select_attr(:body,:user_name).merge(
          {
            date: i.created_at.strftime("%Y-%m-%d %H:%M:%S"),
            is_new: i.is_new(user)
          })
        }
        title = t.title
        {id: t.id, title: title, items: items, public: t.public}
      }
    end
    post '/thread' do
      Kagetra::Utils.dm_response{
        BbsItem.transaction{
          user = get_user
          title = @json["title"]
          body = @json["body"]
          public = @json["public"].to_s.empty?.!
          thread = BbsThread.create(title: title, public: public)
          item = thread.items.create(body: body, user: user, user_name: user.name)
          thread.first_item = item
          thread.save
        }
      }
    end
    post '/item' do
      Kagetra::Utils.dm_response{
        BbsThread.transaction{
          user = get_user
          body = @json["body"]
          thread_id = @json["thread_id"]
          thread = BbsThread.get(thread_id.to_i)
          item = thread.items.create(body: body, user: user, user_name: user.name)
          thread.touch
        }
      }
    end
  end
  get '/bbs' do
    user = get_user
    haml :bbs,{locals: {user: user}}
  end
end
