# -*- coding: utf-8 -*-
class MainApp < Sinatra::Base
  ATTACHED_LIST_PER_PAGE = 50
  WIKI_ALL_PER_PAGE = 30
  WIKI_LOG_PER_PAGE = 10
  WIKI_LOG_MAX_PAGE = 20 # 現在過去ログは遅いのでページ制限を設ける TODO: ページ制限をなくす
  MARKDOWN = Redcarpet::Markdown.new(
  Redcarpet::Render::HTML.new(hard_wrap:true),tables:true,fenced_code_blocks:true)
  namespace '/api/wiki' do
    def render_wiki(body_text,public_mode)
      body_text = body_text.clone
      # 本文中に出現しないランダムな文字列生成
      gen_tag = ->(){
        loop{
          t = SecureRandom.base64(24).gsub(/\W/,"")
          break t unless body_text.include?(t)
        }
      }
      (tag_link,tag_private_s,tag_private_e) = Array.new(3){gen_tag.call}

      # [[ keyword | text ]] と [[ keyword ]] はWiki内リンク
      links = []
      body_text.gsub!(/\[\[((.+?)(\|(.+?))?)\]\]/).with_index(0){|_,i|
        links << $1
        # i は数字なので閉じタグは必要ない
        "#{tag_link}:#{i}:"
      }
      # /* */ で囲まれた部分は非公開
      body_text.gsub!(%r(/\*(.+?)\*\/)m){
        if not public_mode then
          "#{tag_private_s}:#{$1}:#{tag_private_e}"
        end
      }

      html = MARKDOWN.render(body_text)

      if not public_mode then
        html.gsub!(%r(#{tag_private_s}:(.*?):#{tag_private_e})m){
          tag = if $1.include?("\n") then "div" else "span" end
          %(<#{tag} class="private">#{$1}</#{tag}>)
        }
      end

      html.gsub!(/#{tag_link}:(\d+):/){
        (keyword,text) = links[$1.to_i].split('|').map{|x|x.strip}
        text ||= keyword
        item = WikiItem.first(title:keyword)
        if item.nil? then
          %(<a class="link-new" data-link-new="#{Rack::Utils.escape_html(keyword)}">#{text}</a>)
        else
          %(<a class="link-page" data-link-id="#{item.id}">#{text}</a>)
        end
      }
      html
    end
    get '/item/all' do
      page = if params[:page] then params[:page].to_i else 1 end
      # chunksを使うときはorderに同じ物がある可能性があるものを指定するとバグるので:id.descも一緒に指定すること
      cond = if @public_mode then {public:true} else {} end
      chunks = WikiItem.all(cond.merge({order:[:updated_at.desc,:id.desc]})).chunks(WIKI_ALL_PER_PAGE)
      html = ""
      if page > 1 then
        html += "<a class='goto-page' data-page-num='#{page-1}'>前のページ</a>"
      end
      html += "<ul>" + chunks[page-1].map{|x|
          "<li>[#{x.updated_at.to_date}] <a data-link-id='#{x.id}' class='link-page'>#{x.title}</a></li>"
      }.join() + "</ul>"
      if page < chunks.size then
        html += "<a class='goto-page' data-page-num='#{page+1}'>次のページ</a>"
      end
      {
        title: "全一覧",
        html: html
      }
    end
    get '/item/:id' do
      item = WikiItem.get(params[:id].to_i)
      halt 403 unless (not @public_mode or (@public_mode and item.public))
      r = item.select_attr(:title,:revision,:public)
      if not @public_mode then
        r[:deletable] = @user.admin || item.owner_id == @user.id
      end
      if params[:edit].to_s.empty?.! then
        r[:body] = item.body
      else
        r[:html] = render_wiki(item.body,@public_mode)
      end
      r
    end
    delete '/item/:id' do
      item = WikiItem.get(params[:id].to_i)
      # destory するには関連するmodelを削除しないといけないけどそれはイヤなので deleted フラグを付けるだけ
      # ただし title が unique なので削除したはずのものと同じ名前ページを作ろうとするとエラーが出るのを防ぐ
      item.update(deleted:true,title:"__DELETED__:" + item.title)
    end

    def update_or_create_item(item)
      dm_response{
        WikiItem.transaction{
          (updates,updates_patch) = make_comment_log_patch(item,@json,"body","revision")
          if updates then @json.merge!(updates) end
          if item then
            item.update(@json)
          else
            item = WikiItem.create(@json)
          end
          if updates_patch
            item.item_logs.create(updates_patch.merge({user:@user}))
          end
          item.attributes
        }
      }
    end

    put '/item/:id' do
      item = WikiItem.get(params[:id].to_i)
      update_or_create_item(item)
    end
    post '/item', private:true do
      update_or_create_item(nil)
    end
    post '/preview', private:true do
      {html: render_wiki(params[:body],false)}
    end

    get '/attached_list/:id', private:true do
      page = (params[:page] || 1).to_i
      chunks = WikiAttachedFile.all(wiki_item_id:params[:id].to_i,order:[:created_at.desc,:id.desc]).chunks(ATTACHED_LIST_PER_PAGE)
      pages = chunks.size
      list = chunks[page-1].map{|x|
        x.select_attr(:id,:orig_name,:description,:size).merge({
          date:x.created_at.to_date.strftime('%Y-%m-%d'),
          editable: @user.admin || x.owner_id == @user.id
        })
      }
      {item_id:params[:id].to_i,list: list, pages: pages, cur_page: page}
    end
    get '/log/:id', private:true do
      page = if params[:page].to_s.empty?.! then params[:page].to_i else 1 end
      item = WikiItem.get(params[:id].to_i)
      list = item.each_diff_htmls_until(WIKI_LOG_PER_PAGE,WIKI_LOG_PER_PAGE*(page-1)).map{|x|
        log = x[:log]
        # TODO: これだと <ins> や </ins> のある行しか表示されないので
        # 複数行編集されてる場合途中が表示されない
        html = x[:html].lines.select{|x| /<\/?(ins|del)/ =~ x}.join("")
        {
          html:html,
          user_name: if log.user.nil?.! then log.user.name else "" end,
          date: log.created_at.strftime("%Y-%m-%d"),
          revision: log.revision
        }
      }
      {
        list:list,
        next_page: if page+1 > WIKI_LOG_MAX_PAGE then nil else page+1 end
      }

    end
    delete '/attached/:id' do
      WikiAttachedFile.get(params[:id].to_i).update!(deleted:true)
    end
  end
  comment_routes("/api/wiki",WikiItem,WikiComment,true)
  get '/wiki' do
    haml :wiki
  end
  get '/static/wiki/attached/:id', private:true do
    attached_base = File.join(G_STORAGE_DIR,"attached")
    attached = WikiAttachedFile.get(params[:id].to_i)
    send_file(File.join(attached_base,attached.path),filename:attached.orig_name)
  end
  post '/wiki/attached/:id', private:true do
    item = WikiItem.get(params[:id].to_i)
    attached =  if params[:attached_id] then
                  item.attacheds.get(params[:attached_id])
                end
    attached_base = File.join(G_STORAGE_DIR,"attached")
    file =  if params[:file] then
              params[:file]
            else
              {
                tempfile: nil,
                filename: params[:orig_name]
              }
            end
    tempfile = file[:tempfile]
    filename = file[:filename]
    target_file =
      if attached then
        File.join(attached_base,attached.path)
      else
        date = Date.today
        target_dir = File.join(attached_base,date.year.to_s,date.month.to_s)
        FileUtils.mkdir_p(target_dir)
        Kagetra::Utils.unique_file(@user,["attached-",".dat"],target_dir)
      end
    res = begin
      WikiAttachedFile.transaction{
        FileUtils.cp(tempfile.path,target_file) if tempfile
        if attached then
          base = params.select_attr("description")
          base[:orig_name] = filename
          if tempfile then
            base[:size] = File.size(tempfile)
          end
          attached.update(base)
        else
          rel_path = Pathname.new(target_file).relative_path_from(Pathname.new(attached_base))
          item.attacheds.create(owner:@user,path:rel_path,orig_name:filename,description:params[:description],size:File.size(target_file))
        end
      }
      {result:"OK"}
    rescue Exception=>e
      FileUtils.rm(target_file) unless attached
      logger.warn e.message
      $stderr.puts e.message
      {_error_:"送信失敗"}
    end
    "<div id='response'>#{res.to_json}</div>"
  end
end
