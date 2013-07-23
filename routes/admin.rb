# -*- coding: utf-8 -*-
class MainApp < Sinatra::Base
  namespace '/api/admin' do
    get '/list' do
      # UserAttribute.all(fields:[:user_id,:value_id]).map{|x|[x.user_id,x.value_id]} が遅いので手動でクエリする
      # TODO: 上記が遅い原因を探り, 手動クエリを使わない方法を見つける
      user_attrs = Hash[repository(:default).adapter
        .select('SELECT user_id, value_id FROM user_attributes')
        .group_by{|x| x[:user_id]}.map{|xs|[xs[0],xs[1].map{|x|x[:value_id]}]}]
      attr_values = Hash[UserAttributeValue.all
        .map{|x| [x.id, x.select_attr(:index,:value,:default).merge({key_id:x.attr_key.id})]}]
      key_names = UserAttributeKey.all(order: [:index.asc]).map{|x|[x.id,x.name]}
      key_values = Hash[UserAttributeKey.all.map{|x|[x.id,x.values.map{|v|v.id}]}]

      values_indexes = Hash[UserAttributeValue.all.map{|x|[x.id,x.attr_key.index]}]

      login_latests = Hash[UserLoginLatest.all(fields:[:user_id,:updated_at]).map{|x|
        [x.user_id,x.updated_at.to_date]
      }]
      fields = [:id,:name,:furigana,:admin,:loginable,:permission]
      list = User.all(fields:fields).map{|u|
        r = u.select_attr(*fields)
        r[:login_latest] = login_latests[u.id]
        a = user_attrs[u.id].sort_by{|x|values_indexes[x]} if user_attrs[u.id]
        r[:attrs] = a if a
        r
      }
      {
        key_names: key_names,
        attr_values: attr_values,
        key_values: key_values,
        list: list
      }
    end
    post '/permission' do
      is_add = (@json["mode"] == "add")
      sym = @json["type"].to_sym
      users = User.all(id: @json["uids"])
      case @json["type"]
      when "admin","loginable" then
        change_admin_or_loginable(is_add,sym,users)
      else
        change_permission(is_add,sym,users)
      end
    end

    post '/change_attr' do
      users = User.all(id: @json["uids"])
      Kagetra::Utils.dm_debug{
        users.map{|u|u.attrs.create(value_id:@json["value"].to_i)}
      }
    end
    post '/apply_edit' do
      User.transaction{
        @json.each{|x|
          u = User.get(x["uid"].to_i)
          case x["type"]
          when "attr"
            u.attrs.create(value_id:x["new_val"].to_i)
          when "furigana"
            u.update(furigana:x["new_val"])
          when "name"
            u.update(name:x["new_val"])
          end
        }
      }
    end

    def change_admin_or_loginable(is_add,sym,users)
      users.update(sym => is_add)
    end

    def change_permission(is_add,sym,users)
      users.each{|u|
        np = if is_add then
          u.permission + [sym]
        else
          u.permission.reject{|x|x==sym}
        end
        u.update(permission: np)
      }
    end
  end
  get '/admin' do
    @new_salt = Kagetra::Utils.gen_salt
    haml :admin
  end
  get '/admin_config' do
    @cur_shared_salt = MyConf.first(name: "shared_password").value["salt"]
    @new_shared_salt = Kagetra::Utils.gen_salt
    haml :admin_config
  end
end
