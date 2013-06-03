#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

HAGAKURE_BASE="/home/maho/hagakure/subdomains/hagakure/httpdocs"
NUM_THREADS = 8

require './init'
require 'nkf'
require 'parallel'

SHURUI = {}

class String
  def sjis!
    self.replace NKF.nkf("-Sw",self)
  end
  def body_replace
    self.gsub("<br>","\n")
      .gsub("&gt;",">")
      .gsub("&lt;","<")
      .gsub("&amp;","&")
      .gsub("&quot;","'")
      .gsub("&apos;","`")
  end
end

def import_zokusei
  File.readlines(File.join(HAGAKURE_BASE,"txts","zokusei.cgi")).each_with_index{|b,i|
    b.chomp!
    b.sjis!
    cols = b.split(/\t/)
    keys = cols[0].split(/<>/)
    verbose_name = keys[0]
    values = cols[1].split(/<>/)
    attr_key = UserAttributeKey.create(name:verbose_name, index: i)
    values.each_with_index{|v,ii|
      UserAttributeValue.create(user_attribute_key:attr_key,value:v,index:ii)
    }
  }

end

def import_user
  Parallel.each_with_index(File.readlines(File.join(HAGAKURE_BASE,"txts","namelist.cgi")),in_threads: NUM_THREADS){|code,index|
    next if index == 0
    code.chomp!
    File.readlines(File.join(HAGAKURE_BASE,"passdir","#{code}.cgi")).each_with_index{|line,lineno|
      begin
        line.chomp!
        line.sjis!
        (uid,name,password_hash,login_num,last_login,user_agent) = line.split("\t")
        (uid,auth) = uid.split("<>")
        (name,furigana,zokusei) = name.split("+")
        puts name
        User.create(id: uid, name: name, furigana: furigana)
      rescue DataMapper::SaveFailureError => e
        puts "Error at #{code} line #{lineno+1}"
        p e.resource.errors
        raise e
      end
    }
  }
end


def import_bbs
  Parallel.each(Dir.glob(File.join(HAGAKURE_BASE,"bbs","*.cgi")), in_threads: NUM_THREADS){|fn|
    File.readlines(fn).each_with_index{|line,lineno|
      line.chomp!
      line.sjis!
      title = ""
      is_public = false
      thread = nil
      # there is some data which includes "\t" in body which was created when hagakure was immature
      # thus, we cannot simply split by "\t\t"
      line.scan(/((\t|^)\d+(<>(\d|on)?)?\t\d\t.+?)((?=\t\d+(<>)?\t)|$)/).each_with_index{|kakiko,i|
        kakiko = kakiko[0].sub(/^\t/,"")
        (num,not_deleted,name,host,date,*others) = kakiko.split("\t")
        (host,ip) = host.split(/<>/)
        date = DateTime.parse(date)
        deleted = (not_deleted == "0")
        pat = /<!--ID:(\d+)-->$/
        user = nil
        if pat =~ name then
          user = User.first(id: $1)
          name.sub!(pat,"")
        end
        item_props = {
          deleted: deleted,
          created_at: date,
          user_name: name,
          user_host: host,
          user: user
        }
        begin
          if i == 0 then
            title = others[0] || ""
            body = (others[1..-1] || []).join("\t").body_replace
            (num,is_public) = num.split("<>")
            is_public = ["1","on"].include?(is_public)
            thread = BbsThread.create(deleted: deleted, created_at: date, title: title, public: is_public)
            item = BbsItem.create(item_props.merge(id: num, body: body, bbs_thread: thread))
            thread.first_item = item
            thread.save
            # use update! to avoid automatic setting by dm-timestamps
            item.update!(updated_at: date)
            thread.update!(updated_at: date)
            puts title
          else
            body = others.join("\t").body_replace
            item = BbsItem.create(item_props.merge(id: num, body: body, bbs_thread: thread))
            item.update!(updated_at: date)
          end
        rescue DataMapper::SaveFailureError => e
          puts "Error at #{fn} line #{lineno+1} index #{i+1}"
          p e.resource.errors
          raise e
        end
      }
    }
  }
end

def import_schedule
  Parallel.each(Dir.glob(File.join(HAGAKURE_BASE,"scheduledir","*.cgi")), in_threads: NUM_THREADS){|fn|
    base = File.basename(fn)
    raise Exception.new("bad schedule filename: #{base}") unless /^(\d+)_(\d+).cgi$/ =~ base
    year = $1.to_i
    mon = $2.to_i
    File.readlines(fn).each_with_index{|line,lineno|
      begin
        day = lineno + 1
        line.chomp!
        line.sjis!
        (day_info,*others) = line.split(/<&&>/)
        others.each{|oth|
          (kind,wdate,name,title,place,start_at,end_at,desc) = oth.split(/\t/)
          (title,not_public) = title.split(/<>/) if title
          (place,emphasis_place) = place.split(/<>/) if place
          (start_at,emphasis_start) = start_at.split(/<>/) if start_at
          (end_at,emphasis_end) = end_at.split(/<>/) if end_at
          start_at = nil if start_at && start_at.empty?
          end_at = nil if end_at && end_at.empty?

          puts "#{kind} - #{title}"
          kind = case kind
                 when "1"
                   :practice
                 when "2"
                   :party
                 else
                   :etc
                 end
          emphasis = []
          emphasis << :place if emphasis_place == "1"
          emphasis << :start_at if emphasis_start == "1"
          emphasis << :end_at if emphasis_end == "1"

          date = Date.new(year,mon,day)
          created_at = DateTime.parse(wdate)
          user = User.first(name: name)
          if user.nil? then
            user = User.first(name: CONF_USERNAME_CHANGED[name])
            if user.nil? then
              raise Exception.new("no user named: '#{name}'")
            end
          end
          item = ScheduleItem.create(
            user: user,
            kind: kind,
            public: not_public != "1",
            emphasis: emphasis,
            title: title,
            date: date,
            start_at: start_at,
            end_at: end_at,
            place: place,
            description: desc,
            created_at: created_at
          )
          item.update!(updated_at: created_at)
           
        }
        if day_info then
          (holiday,day_info) = day_info.split(/\t/)
          is_holiday = holiday == "1"
          day_info = if day_info then
            day_info.split(/<br>/)
          else
            []
          end
          if is_holiday or day_info.empty?.! then
            date = Date.new(year,mon,day)
            ScheduleDateInfo.create(
              names: day_info,
              holiday: is_holiday,
              date: date
            )
            puts "#{date} => #{is_holiday} #{day_info}"
          end
        end
      rescue DataMapper::SaveFailureError => e
        puts "Error at #{fn} line #{lineno+1}"
        p e.resource.errors
        raise e
      end
    }
  }
end

def import_shurui
  lines = File.readlines(File.join(HAGAKURE_BASE,"txts","shurui.cgi"))
  lines.each{|line|
    line.chomp!
    line.sjis!
    (num,name,description) = line.split("\t")
    group = EventGroup.create(id:num, name:name, description:description)
    SHURUI[num.to_i] = group
  }
end

def iskonpa2etype(iskonpa)
  case iskonpa
  when "-1" then :contest
  when "0" then  :etc
  when "1" then  :practice
  when "2" then  :party
  else raise Exception.new("invalid type: #{iskonpa}")
  end
end

def parse_common(tbuf)
  choices = []
  (taikainame,seisikimeishou,choices,kounin,teamnum,bikou,place) = nil
  tbuf.each_with_index{|curl,lineno|
    nextline = tbuf[lineno+1]
    case curl
    when "[NAME]"
      (taikainame,seisikimeishou) = nextline.split('<>')
    when "[ANSWER]"
      (yes,no,notyet) = nextline.split('/')
      yeses = yes && yes.split('<>')
      choices = yeses && yeses.map{|y| ['YES',y]} + [['NO',no]]
    when /^\[BIKOU\]/
      (kounin,teamnum) = curl[7..-1].split('-')
      kounin = (kounin == '1')
      teamnum = teamnum.to_i
      bikou = nextline.body_replace
    when "[PLACE]"
      place = nextline
    end
  }
  [taikainame,seisikimeishou,choices,kounin,teamnum,bikou,place]
end

def import_event
  lines = File.readlines(File.join(HAGAKURE_BASE,"txts","taikailist.cgi"))[1..-1]
  if SHURUI.empty? then
    raise Exception.new("import_shurui not executed")
  end
  Parallel.each(lines,in_threads:NUM_THREADS){|line|
    line.chomp!
    line.sjis!
    (taikainum,kaisaidate,iskonpa,kanrisha,koureitaikai) = line.split("\t")
    shurui = SHURUI[koureitaikai.to_i]
    (kyear,kmon,kday,khour,kmin,kweekday) = kaisaidate.split('/')
    if kyear == "なし" then
      kaisaidate = nil
    else
      kaisaidate = Date.new(kyear.to_i,kmon.to_i,kday.to_i)
      kstart_at = Kagetra::HourMin.new(khour.to_i,kmin.to_i)
    end
    (tourokudate,kanrisha) = kanrisha.split('<>')
    etype = iskonpa2etype(iskonpa)
    kanrishas = kanrisha.split(',').map{|k| k.strip}
    tbuf = File.readlines(File.join(HAGAKURE_BASE,"taikai","#{taikainum}.cgi")).map{|x|
      x.chomp!
      x.sjis!
    }
    (taikainame,seisikimeishou,choices,kounin,teamnum,bikou,place) = parse_common(tbuf)
    (bikou_opt,simekiri,agg_attr,show_choice) = nil
    tbuf.each_with_index{|curl,lineno|
      nextline = tbuf[lineno+1]
      case curl
      when '[SIMEKIRI]'
       simekiri = nextline
       (syear,smon,sday,sweekday) = simekiri.split('/')
       simekiri = if syear == 'なし' then nil else Date.new(syear.to_i,smon.to_i,sday.to_i) end
      when '[FUKA]'
        fukas = nextline.split('#')
        fukalist = fukas.map{|f|
          next if f.empty?
          (key,val) = f.split('.')
          k = UserAttributeKey.first(index:key.to_i-1)
          v = UserAttributeValue.first(user_attribute_key:k,index:val.to_i)
        }.compact
      when /^\[KAIHI\](\d?)/
        agg_attr = UserAttributeKey.first(index:$1.to_i-1)
        bikou_opt = ''
        next unless agg_attr
        if nextline.to_s.empty?.! then
          xx = tbuf[lineno+2].split('&')
          zz = xx.each_with_index.map{|x,ii|
            next if x.empty?
            v = UserAttributeValue.first(user_attribute_key:agg_attr,index:ii)
            if not v then raise Exception.new("no UserAttributeValue which has user_attribute_key:#{agg_attr.id} and index:#{ii-1} at taikainum:#{taikainum}") end
            v.value + x
          }.compact
          if zz.empty?.! then
            bikou_opt = nextline + ": " + zz.join(", ")
          end
        end
      when /^\[SANKA\](\d?)/
        revised = $1 == '1'
        member_yes= nextline
        member_no = tbuf[lineno+2]
        show_choice = true
        userchoice = [[:yes,member_yes],[:no,member_no]].map{|typ,m|
          case m[0]
          when 1 then show = true
          when 2 then show_choice = false
          end
          tts = m[1..-1].split(/<!--[0-9]-->/)
          ttss = tts[1..-1]
          next unless ttss
          ttss.map{|zz|
            zz.split(/\t/).each_with_index.map{|mm,ci|
              mm.split(/ *, */).map{|ss|
                next if ss.empty?
                (name,date) = ss.split(/ *<> */).map{|x|x.strip}
                {
                  typ:typ,
                  date:DateTime.parse(date.sub(/\*/,"")),
                  name:name,
                  ci:ci
                }
              }
            }
          }
        }.flatten.compact
      end
    }
    begin
      evt = Event.create(
        name:taikainame,
        formal_name: seisikimeishou,
        official: kounin,
        kind:etype,
        num_teams: teamnum,
        description: "#{bikou}\n#{bikou_opt}",
        deadline: simekiri,
        date: kaisaidate,
        created_at: DateTime.parse(tourokudate),
        place: place,
        event_group: shurui,
        show_choice: show_choice,
        aggregate_attr: agg_attr)
    rescue DataMapper::SaveFailureError => e
      puts "Error at #{taikainame}"
      p e.resource.errors
      raise e
    end
  }
end
import_zokusei
import_user
import_bbs
import_schedule
import_shurui
import_event
